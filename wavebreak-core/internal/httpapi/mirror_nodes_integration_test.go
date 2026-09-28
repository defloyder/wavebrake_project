package httpapi

import (
	"bytes"
	"context"
	"database/sql"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/pressly/goose/v3"

	"wavebreak-core/internal/accounts"
	"wavebreak-core/internal/app"
	"wavebreak-core/internal/config"
	"wavebreak-core/internal/database"
	"wavebreak-core/internal/security"
	"wavebreak-core/internal/store"
)

// TestMirrorNodeE2E: a second location serving the primary's accounts —
// its links in /me/access, the same credentials in its desired state,
// traffic from both nodes counted once each, never picked for new
// credentials, not listed as its own location. Needs a throwaway database
// (WAVEBREAK_TEST_DATABASE_URL): it takes every other node offline.
func TestMirrorNodeE2E(t *testing.T) {
	dsn := os.Getenv("WAVEBREAK_TEST_DATABASE_URL")
	if dsn == "" {
		t.Skip("WAVEBREAK_TEST_DATABASE_URL not set")
	}
	ctx := context.Background()
	sqlDB, err := sql.Open("pgx", dsn)
	if err != nil {
		t.Fatal(err)
	}
	defer sqlDB.Close()
	_ = goose.SetDialect("postgres")
	if err := goose.Up(sqlDB, "../../migrations"); err != nil {
		t.Fatalf("migrations: %v", err)
	}
	pool, err := database.Open(ctx, dsn)
	if err != nil {
		t.Fatal(err)
	}
	defer pool.Close()
	st := store.New(pool)
	a := &app.App{Config: config.Config{
		JWTSecret: "e2e-secret", AccessTokenTTL: time.Hour, RefreshTokenTTL: time.Hour,
		Accounts: config.AccountsConfig{SubscriptionURLBase: "https://api.e2e.test/v1/sub/", AccessProtocol: "vless", SubscriptionGrace: accounts.DefaultGracePeriod},
		VLESS: config.VLESSConfig{
			PublicHost: "45.15.41.3", PublicPort: 443, RealityPublicKey: "pbk-tr", RealityShortID: "ab12", RealityServerName: "r.e2e.test",
			Fingerprint: "chrome", PublishDirect: true,
			DirectTLSHost: "direct.e2e.test", DirectTLSPort: 443, DirectTLSPath: "/wvb-dt",
			HysteriaHost: "45.15.41.3", HysteriaPort: 443,
			CDNHost: "cdn.e2e.test", CDNPort: 443, PublishCDNWS: true,
		},
	}, Store: st}
	srv := newServer(a)
	h := srv.router()

	suffix := strings.ReplaceAll(time.Now().Format("150405.000000"), ".", "")
	if _, err := pool.Exec(ctx, `update nodes set status = 'offline'`); err != nil {
		t.Fatal(err)
	}
	var primaryID, mirrorID string
	if err := pool.QueryRow(ctx, `insert into nodes (code, region, status, last_heartbeat_at) values ($1, 'TR', 'online', now() - interval '1 minute') returning id::text`, "TR-P-"+suffix).Scan(&primaryID); err != nil {
		t.Fatal(err)
	}
	// Enrolled and fresher than the primary: must still never get new credentials.
	if err := pool.QueryRow(ctx, `insert into nodes (code, region, status, last_heartbeat_at) values ($1, 'RU', 'online', now()) returning id::text`, "RU-M-"+suffix).Scan(&mirrorID); err != nil {
		t.Fatal(err)
	}
	// A primary that already serves credentials wins over the empty newcomer.
	hash, _ := security.HashPassword("mirror-password-1")
	var planID string
	if err := pool.QueryRow(ctx, `
		insert into plans (code, name, price_cents, price_minor, interval, duration_days, device_limit, traffic_limit_bytes, is_active)
		values ($1, 'Mirror Plus', 499, 499, 'month', 30, 3, 0, true) returning id::text`, "mirror-"+suffix).Scan(&planID); err != nil {
		t.Fatal(err)
	}
	seed, _ := st.CreateUser(ctx, "mirror-seed-"+suffix+"@e2e.test", hash)
	end := time.Now().Add(30 * 24 * time.Hour)
	if _, err := st.CreateSubscriptionForOptions(ctx, seed.ID, planID, "admin", seed.ID, "active", &end); err != nil {
		t.Fatal(err)
	}
	if _, err := st.CreateAccessGrant(ctx, seed.ID, primaryID, "vless", "", end); err != nil {
		t.Fatal(err)
	}

	user, err := st.CreateUser(ctx, "mirror-"+suffix+"@e2e.test", hash)
	if err != nil {
		t.Fatal(err)
	}
	tok, _ := srv.issueAccessToken(user.ID, user.Email, user.Role)
	call := func(method, path string, body any) (int, map[string]any) {
		var buf bytes.Buffer
		if body != nil {
			_ = json.NewEncoder(&buf).Encode(body)
		}
		req := httptest.NewRequest(method, path, &buf)
		req.Header.Set("Authorization", "Bearer "+tok)
		rec := httptest.NewRecorder()
		h.ServeHTTP(rec, req)
		out := map[string]any{}
		_ = json.Unmarshal(rec.Body.Bytes(), &out)
		return rec.Code, out
	}
	if code, d := call(http.MethodPost, "/v1/subscriptions", map[string]string{"plan_id": planID}); code != 201 {
		t.Fatalf("purchase: %d %v", code, d)
	}
	code, d := call(http.MethodPost, "/v1/me/access", nil)
	if code != 200 {
		t.Fatalf("me/access: %d %v", code, d)
	}
	credential := d["credential_id"].(string)
	var grantNode string
	_ = pool.QueryRow(ctx, `select node_id::text from access_grants where id = $1`, credential).Scan(&grantNode)
	if grantNode != primaryID {
		t.Fatalf("credential issued on %s, want the primary %s", grantNode, primaryID)
	}
	before := len(d["links"].([]any))

	// Link the mirror (what `wavebreak-cli node mirror` does).
	publicConfig := `{"PublicHost":"203.0.113.9","PublicPort":443,"RealityPublicKey":"pbk-ru","RealityShortID":"cd34",
		"RealityServerName":"r.ru.test","PublishDirect":true,"DirectTLSHost":"ru.e2e.test","DirectTLSPort":443,
		"DirectTLSPath":"/wvb-dt","HysteriaHost":"203.0.113.9","HysteriaPort":443}`
	if _, err := st.LinkMirrorNode(ctx, "RU-M-"+suffix, "TR-P-"+suffix, json.RawMessage(publicConfig)); err != nil {
		t.Fatal(err)
	}
	state, err := st.LatestDesiredState(ctx, mirrorID)
	if err != nil || !strings.Contains(string(state.State), credential) {
		t.Fatalf("mirror desired state lacks the credential: %s %v", state.State, err)
	}

	code, d = call(http.MethodPost, "/v1/me/access", nil)
	links := d["links"].([]any)
	if code != 200 || len(links) != 2*before {
		t.Fatalf("links with the mirror: %d %d %v", code, len(links), links)
	}
	for i, l := range links {
		s := l.(string)
		mirrorLink := i >= before
		if mirrorLink != (strings.Contains(s, "203.0.113.9") || strings.Contains(s, "ru.e2e.test")) {
			t.Fatalf("link %d on the wrong node: %s", i, s)
		}
		if mirrorLink && (!strings.Contains(s, "Russia") || strings.Contains(s, "45.15.41.3") || strings.Contains(s, "cdn.e2e.test")) {
			t.Fatalf("mirror link %d: %s", i, s)
		}
		if !strings.Contains(s, credential) {
			t.Fatalf("link %d uses another credential: %s", i, s)
		}
	}

	// A grant change on the primary republishes the mirror too.
	rev := state.Revision
	if _, err := st.CreateAccessGrant(ctx, user.ID, primaryID, "vless", "", time.Now().Add(time.Hour)); err == nil {
		if s2, _ := st.LatestDesiredState(ctx, mirrorID); s2.Revision <= rev {
			t.Fatal("mirror not republished after a primary grant change")
		}
	}

	// Traffic from both nodes: each node's counters are its own.
	must := func(err error) {
		if err != nil {
			t.Helper()
			t.Fatal(err)
		}
	}
	now := time.Now()
	must(st.RecordNodeUsageReport(ctx, primaryID, credential, 1000, 2000, now))
	must(st.RecordNodeUsageReport(ctx, mirrorID, credential, 500, 700, now))
	must(st.RecordNodeUsageReport(ctx, primaryID, credential, 1500, 2600, now))
	must(st.RecordNodeUsageReport(ctx, mirrorID, credential, 600, 700, now))
	var up, down int64
	_ = pool.QueryRow(ctx, `
		select u.bytes_up, u.bytes_down from subscription_usage u
		join access_grants g on g.subscription_id = u.subscription_id where g.id = $1`, credential).Scan(&up, &down)
	if up != 2100 || down != 3300 {
		t.Fatalf("usage up/down = %d/%d, want 2100/3300", up, down)
	}
	// An unrelated node can't report this credential.
	var otherID string
	_ = pool.QueryRow(ctx, `insert into nodes (code, region, status) values ($1, 'DE', 'offline') returning id::text`, "DE-X-"+suffix).Scan(&otherID)
	if err := st.RecordNodeUsageReport(ctx, otherID, credential, 1, 1, now); err != store.ErrNotFound {
		t.Fatalf("foreign node usage accepted: %v", err)
	}

	// Not its own location in the apps; still visible to admins.
	nodes, _ := st.ListPrimaryNodes(ctx)
	for _, n := range nodes {
		if n.ID == mirrorID {
			t.Fatal("mirror listed as an app location")
		}
	}
	// New credentials never go to the mirror.
	if id, err := st.Accounts().DefaultNodeID(ctx); err != nil || id != primaryID {
		t.Fatalf("default node %s (%v), want the primary", id, err)
	}

	// A mirror that stopped checking in isn't offered.
	_, _ = pool.Exec(ctx, `update nodes set last_heartbeat_at = now() - interval '10 minutes' where id = $1`, mirrorID)
	if _, d = call(http.MethodPost, "/v1/me/access", nil); len(d["links"].([]any)) != before {
		t.Fatalf("stale mirror still offered: %v", d["links"])
	}
	_, _ = pool.Exec(ctx, `update nodes set status = 'offline' where id in ($1, $2)`, primaryID, mirrorID)
}
