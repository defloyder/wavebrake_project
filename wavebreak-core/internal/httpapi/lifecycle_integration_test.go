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

// TestSubscriptionLifecycleE2E: the app's personal access, the grace
// period with VPN blocked, in-place renewal keeping the link, traffic
// exhaustion and the expiry reset — against a real PostgreSQL. Set
// WAVEBREAK_TEST_DATABASE_URL to a throwaway database to run it.
func TestSubscriptionLifecycleE2E(t *testing.T) {
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
			PublicHost: "45.15.41.3", PublicPort: 443, RealityPublicKey: "pbk-e2e", RealityShortID: "ab12", RealityServerName: "r.e2e.test",
			Fingerprint: "chrome", PublishDirect: true,
			DirectTLSHost: "direct.e2e.test", DirectTLSPort: 443, DirectTLSPath: "/wvb-dt",
			HysteriaHost: "45.15.41.3", HysteriaPort: 443,
			RealityXHTTPServerName: "x.e2e.test", RealityXHTTPPath: "/wvb-rx",
		},
	}, Store: st}
	srv := newServer(a)
	h := srv.router()
	repo := st.Accounts()
	lifecycle := accounts.NewSubscriptionLifecycleService(repo, repo, accounts.DefaultGracePeriod)

	suffix := time.Now().Format("150405.000000")
	hash, _ := security.HashPassword("initial-password-1")
	user, err := st.CreateUserWithRole(ctx, "life-"+suffix+"@e2e.test", hash, "user")
	if err != nil {
		t.Fatal(err)
	}
	var planID string
	if err := pool.QueryRow(ctx, `
		insert into plans (code, name, price_cents, price_minor, interval, duration_days, device_limit, traffic_limit_bytes, is_active)
		values ($1, 'E2E Plus', 499, 499, 'month', 30, 3, 10737418240, true) returning id::text`, "life-"+suffix).Scan(&planID); err != nil {
		t.Fatal(err)
	}
	var nodeID string
	if err := pool.QueryRow(ctx, `
		insert into nodes (code, region, status, last_heartbeat_at) values ($1, 'TR', 'online', now() + interval '1 hour') returning id::text`, "LIFE-"+suffix).Scan(&nodeID); err != nil {
		t.Fatal(err)
	}
	tok, err := srv.issueAccessToken(user.ID, user.Email, user.Role)
	if err != nil {
		t.Fatal(err)
	}
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
	grantExpiry := func(id string) time.Time {
		var at time.Time
		_ = pool.QueryRow(ctx, `select expires_at from access_grants where id = $1`, id).Scan(&at)
		return at
	}
	subStatus := func(id string) string {
		var s string
		_ = pool.QueryRow(ctx, `select status from subscriptions where id = $1`, id).Scan(&s)
		return s
	}

	// 1. No subscription -> no access.
	if code, d := call(http.MethodPost, "/v1/me/access", nil); code != 404 || d["error"].(map[string]any)["code"] != accounts.CodeSubscriptionNotFound {
		t.Fatalf("access without subscription: %d %v", code, d)
	}

	// 2. Buy in the app, then ask for access: one credential, three app links.
	code, d := call(http.MethodPost, "/v1/subscriptions", map[string]string{"plan_id": planID})
	if code != 201 {
		t.Fatalf("purchase: %d %v", code, d)
	}
	subID := d["id"].(string)
	code, d = call(http.MethodPost, "/v1/me/access", nil)
	if code != 200 {
		t.Fatalf("me/access: %d %v", code, d)
	}
	credential := d["credential_id"].(string)
	links := d["links"].([]any)
	if credential == "" || d["subscription_url"] != "https://api.e2e.test/v1/sub/"+credential || len(links) != 4 {
		t.Fatalf("access payload: %v", d)
	}
	if !strings.HasPrefix(links[0].(string), "vless://"+credential+"@") || !strings.Contains(links[0].(string), "security=reality") ||
		!strings.Contains(links[1].(string), "type=xhttp") || !strings.Contains(links[1].(string), "sni=x.e2e.test") || strings.Contains(links[1].(string), "flow=") ||
		!strings.Contains(links[2].(string), "direct.e2e.test") || !strings.HasPrefix(links[3].(string), "hysteria2://") {
		t.Fatalf("links order/content: %v", links)
	}
	// Same credential for every device of the account.
	if _, again := call(http.MethodPost, "/v1/me/access", nil); again["credential_id"] != credential {
		t.Fatalf("credential changed: %v", again)
	}

	// 3. Two devices, the second one used more recently.
	var older, newer string
	for i, name := range []string{"Old phone", "New phone"} {
		code, dev := call(http.MethodPost, "/v1/me/devices", map[string]string{"name": name, "platform": "android"})
		if code != 201 && code != 200 {
			t.Fatalf("device: %d %v", code, dev)
		}
		id := dev["id"].(string)
		_, _ = pool.Exec(ctx, `update devices set last_seen_at = now() - make_interval(hours => $2) where id = $1`, id, 10-i*9)
		if i == 0 {
			older = id
		} else {
			newer = id
		}
	}

	// 4. Period over -> past_due, key no longer served, current shows grace.
	_, _ = pool.Exec(ctx, `update subscriptions set current_period_end = now() - interval '1 minute' where id = $1`, subID)
	if report, err := lifecycle.Run(ctx); err != nil || report.PastDue != 1 {
		t.Fatalf("grace run: %+v %v", report, err)
	}
	if subStatus(subID) != "past_due" || grantExpiry(credential).After(time.Now()) {
		t.Fatalf("grace: status %s, key expiry %v", subStatus(subID), grantExpiry(credential))
	}
	code, d = call(http.MethodGet, "/v1/subscriptions/current", nil)
	if code != 200 || d["status"] != "past_due" || d["grace_ends_at"] == nil {
		t.Fatalf("current in grace: %d %v", code, d)
	}
	if code, d := call(http.MethodPost, "/v1/me/access", nil); code != 422 || d["error"].(map[string]any)["code"] != accounts.CodeSubscriptionNotActive {
		t.Fatalf("access in grace: %d %v", code, d)
	}

	// 5. Renew within grace: same subscription and credential, key served again, usage from zero.
	_, _ = pool.Exec(ctx, `insert into subscription_usage (subscription_id, bytes_up, bytes_down) values ($1, 1, 2) on conflict (subscription_id) do update set bytes_up = 1, bytes_down = 2`, subID)
	code, d = call(http.MethodPost, "/v1/subscriptions", map[string]string{"plan_id": planID})
	if code != 200 || d["id"] != subID || d["status"] != "active" {
		t.Fatalf("renewal: %d %v", code, d)
	}
	if !grantExpiry(credential).After(time.Now().Add(29 * 24 * time.Hour)) {
		t.Fatalf("key not served again after renewal: %v", grantExpiry(credential))
	}
	if _, again := call(http.MethodPost, "/v1/me/access", nil); again["credential_id"] != credential {
		t.Fatalf("renewal changed the credential: %v", again)
	}
	var used int64
	_ = pool.QueryRow(ctx, `select bytes_up + bytes_down from subscription_usage where subscription_id = $1`, subID).Scan(&used)
	if used != 0 {
		t.Fatalf("usage not reset on renewal: %d", used)
	}
	// A second purchase while active is still refused.
	if code, _ := call(http.MethodPost, "/v1/subscriptions", map[string]string{"plan_id": planID}); code != 409 {
		t.Fatalf("purchase while active: %d", code)
	}

	// 6. Traffic exhausted -> past_due immediately, grace counted from now.
	_, _ = pool.Exec(ctx, `update subscription_usage set bytes_down = 10737418240 where subscription_id = $1`, subID)
	if report, err := lifecycle.Run(ctx); err != nil || report.PastDue != 1 {
		t.Fatalf("traffic run: %+v %v", report, err)
	}
	if subStatus(subID) != "past_due" {
		t.Fatalf("traffic exhausted: %s", subStatus(subID))
	}

	// 7. Grace passes -> expired and reset: key revoked, only the most
	// recently active device kept, without a subscription. Login stays.
	_, _ = pool.Exec(ctx, `update subscriptions set current_period_end = now() - interval '8 days' where id = $1`, subID)
	if report, err := lifecycle.Run(ctx); err != nil || report.Expired != 1 {
		t.Fatalf("expiry run: %+v %v", report, err)
	}
	var grantStatus string
	_ = pool.QueryRow(ctx, `select status from access_grants where id = $1`, credential).Scan(&grantStatus)
	var olderRevoked, newerRevoked bool
	var newerSub *string
	_ = pool.QueryRow(ctx, `select revoked_at is not null from devices where id = $1`, older).Scan(&olderRevoked)
	_ = pool.QueryRow(ctx, `select revoked_at is not null, subscription_id::text from devices where id = $1`, newer).Scan(&newerRevoked, &newerSub)
	if subStatus(subID) != "expired" || grantStatus != "revoked" || !olderRevoked || newerRevoked || newerSub != nil {
		t.Fatalf("reset: sub=%s grant=%s older revoked=%v newer revoked=%v newer sub=%v", subStatus(subID), grantStatus, olderRevoked, newerRevoked, newerSub)
	}
	if code, _ := call(http.MethodGet, "/v1/subscriptions/current", nil); code != 404 {
		t.Fatalf("no subscription after reset: %d", code)
	}
	if code, _ := call(http.MethodGet, "/v1/me", nil); code != 200 {
		t.Fatalf("account must survive the reset: %d", code)
	}
	// Buying again starts a new subscription with a new credential.
	if code, d := call(http.MethodPost, "/v1/subscriptions", map[string]string{"plan_id": planID}); code != 201 || d["id"] == subID {
		t.Fatalf("new purchase after reset: %d %v", code, d)
	}
	if _, fresh := call(http.MethodPost, "/v1/me/access", nil); fresh["credential_id"] == credential || fresh["credential_id"] == nil {
		t.Fatalf("new subscription must get a new credential: %v", fresh)
	}

	// Audit trail of the transitions.
	var n int
	_ = pool.QueryRow(ctx, `select count(*) from audit_events where target_user_id = $1 and action = any($2)`, user.ID,
		[]string{accounts.AuditSubscriptionPastDue, accounts.AuditSubscriptionExpired, accounts.AuditSubscriptionRenewed}).Scan(&n)
	if n != 4 {
		t.Fatalf("lifecycle audit events: %d", n)
	}
	_ = nodeID
}
