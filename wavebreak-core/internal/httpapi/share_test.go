package httpapi

import (
	"bytes"
	"context"
	"database/sql"
	"encoding/json"
	"errors"
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

func TestShareTokenRoundTrip(t *testing.T) {
	owner := "0f8b2c4e-1a2b-4c3d-8e9f-a0b1c2d3e4f5"
	now := time.Unix(1_800_000_000, 0)
	token, err := signShareToken("secret-1", owner, now.Add(time.Hour))
	if err != nil {
		t.Fatal(err)
	}
	if len(token) != 48 || strings.ContainsAny(token, "+/=") {
		t.Fatalf("token not compact url-safe: %q", token)
	}
	got, err := parseShareToken("secret-1", token, now)
	if err != nil || got != owner {
		t.Fatalf("parse: %q %v", got, err)
	}
	if _, err := parseShareToken("secret-1", token, now.Add(time.Hour)); !errors.Is(err, errShareTokenExpired) {
		t.Fatalf("expired token accepted: %v", err)
	}
	if _, err := parseShareToken("secret-2", token, now); !errors.Is(err, errShareTokenInvalid) {
		t.Fatalf("token from another secret accepted: %v", err)
	}
	// Any flipped byte breaks the signature (owner, expiry or MAC).
	raw := []byte(token)
	for _, i := range []int{0, 22, 30, 47} {
		tampered := append([]byte(nil), raw...)
		if tampered[i] == 'A' {
			tampered[i] = 'B'
		} else {
			tampered[i] = 'A'
		}
		if _, err := parseShareToken("secret-1", string(tampered), now); err == nil {
			t.Fatalf("tampered token (byte %d) accepted", i)
		}
	}
	for _, bad := range []string{"", "abc", token + "A", "not-a-token-at-all-!!"} {
		if _, err := parseShareToken("secret-1", bad, now); !errors.Is(err, errShareTokenInvalid) {
			t.Fatalf("bad token %q: %v", bad, err)
		}
	}
	if _, err := signShareToken("secret-1", "not-a-uuid", now); err == nil {
		t.Fatal("non-uuid owner signed")
	}
}

func TestShareURLBase(t *testing.T) {
	for base, want := range map[string]string{
		"https://core.example.test/v1/sub/": "https://core.example.test/v1/share/",
		"https://core.example.test/v1/sub":  "https://core.example.test/v1/share/",
		"":                                  "https://core.wavebreak.com.tr/v1/share/",
	} {
		s := &Server{app: &app.App{Config: config.Config{Accounts: config.AccountsConfig{SubscriptionURLBase: base}}}}
		if got := s.shareURLBase(); got != want {
			t.Fatalf("%q -> %q, want %q", base, got, want)
		}
	}
}

// TestShareSubscriptionE2E: the owner's share QR, redeemed by other
// accounts against the owner's device limit — against a real PostgreSQL.
func TestShareSubscriptionE2E(t *testing.T) {
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
		Accounts: config.AccountsConfig{SubscriptionURLBase: "https://api.e2e.test/v1/sub/", AccessProtocol: "vless", SubscriptionGrace: accounts.DefaultGracePeriod, SelfServeSubscriptions: true},
		VLESS: config.VLESSConfig{
			PublicHost: "45.15.41.3", PublicPort: 443, RealityPublicKey: "pbk-e2e", RealityShortID: "ab12", RealityServerName: "r.e2e.test",
			Fingerprint: "chrome", PublishDirect: true,
			HysteriaHost: "45.15.41.3", HysteriaPort: 443,
		},
	}, Store: st}
	srv := newServer(a)
	h := srv.router()

	suffix := time.Now().Format("150405.000000")
	hash, _ := security.HashPassword("initial-password-1")
	newUser := func(name string) (string, string) {
		u, err := st.CreateUserWithRole(ctx, name+"-"+suffix+"@e2e.test", hash, "user")
		if err != nil {
			t.Fatal(err)
		}
		tok, err := srv.issueAccessToken(u.ID, u.Email, u.Role)
		if err != nil {
			t.Fatal(err)
		}
		return u.ID, tok
	}
	ownerID, owner := newUser("share-owner")
	_, bob := newUser("share-bob")
	_, carol := newUser("share-carol")
	var planID string
	if err := pool.QueryRow(ctx, `
		insert into plans (code, name, price_cents, price_minor, interval, duration_days, device_limit, traffic_limit_bytes, is_active)
		values ($1, 'E2E Duo', 499, 499, 'month', 30, 2, 10737418240, true) returning id::text`, "share-"+suffix).Scan(&planID); err != nil {
		t.Fatal(err)
	}
	if _, err := pool.Exec(ctx, `
		insert into nodes (code, region, status, last_heartbeat_at) values ($1, 'TR', 'online', now())`, "SHARE-"+suffix); err != nil {
		t.Fatal(err)
	}
	call := func(tok, method, path string, body any) (int, map[string]any) {
		var buf bytes.Buffer
		if body != nil {
			_ = json.NewEncoder(&buf).Encode(body)
		}
		req := httptest.NewRequest(method, path, &buf)
		if tok != "" {
			req.Header.Set("Authorization", "Bearer "+tok)
		}
		rec := httptest.NewRecorder()
		h.ServeHTTP(rec, req)
		out := map[string]any{}
		_ = json.Unmarshal(rec.Body.Bytes(), &out)
		return rec.Code, out
	}
	errCode := func(d map[string]any) any {
		e, _ := d["error"].(map[string]any)
		return e["code"]
	}
	redeem := func(tok, token, device string) (int, map[string]any) {
		return call(tok, http.MethodPost, "/v1/share/redeem", map[string]string{"token": token, "device_name": device, "platform": "android"})
	}

	// No subscription -> nothing to share.
	if code, d := call(owner, http.MethodPost, "/v1/me/share", nil); code != 404 || errCode(d) != accounts.CodeSubscriptionNotFound {
		t.Fatalf("share without subscription: %d %v", code, d)
	}
	if code, d := call(owner, http.MethodPost, "/v1/subscriptions", map[string]string{"plan_id": planID}); code != 201 {
		t.Fatalf("purchase: %d %v", code, d)
	}
	// The owner's own phone takes the first of two slots.
	if code, d := call(owner, http.MethodPost, "/v1/me/devices", map[string]string{"name": "Owner phone", "platform": "android"}); code != 201 {
		t.Fatalf("owner device: %d %v", code, d)
	}

	code, d := call(owner, http.MethodPost, "/v1/me/share", nil)
	if code != 200 {
		t.Fatalf("me/share: %d %v", code, d)
	}
	shareURL, _ := d["share_url"].(string)
	if !strings.HasPrefix(shareURL, "https://api.e2e.test/v1/share/") {
		t.Fatalf("share url: %v", d)
	}
	limits := d["limits"].(map[string]any)
	if limits["device_limit"] != float64(2) || limits["devices_used"] != float64(1) || limits["traffic_limit_bytes"] != float64(10737418240) {
		t.Fatalf("limits: %v", limits)
	}
	token := strings.TrimPrefix(shareURL, "https://api.e2e.test/v1/share/")
	var credential string
	if err := pool.QueryRow(ctx, `select primary_grant_id::text from subscriptions where user_id = $1`, ownerID).Scan(&credential); err != nil {
		t.Fatal(err)
	}
	if strings.Contains(shareURL, credential) {
		t.Fatal("share url leaks the credential")
	}
	// A plain camera app opening the URL learns nothing.
	if code, d := call("", http.MethodGet, "/v1/share/"+token, nil); code != 200 || len(d) != 0 {
		t.Fatalf("landing: %d %v", code, d)
	}

	// Owner scanning their own code.
	if code, d := redeem(owner, token, "Owner phone"); code != 409 || errCode(d) != "SHARE_OWN_SUBSCRIPTION" {
		t.Fatalf("own redeem: %d %v", code, d)
	}
	// Garbage and anonymous redeem.
	if code, d := redeem(bob, "garbage", "Bob phone"); code != 400 || errCode(d) != "SHARE_INVALID" {
		t.Fatalf("garbage redeem: %d %v", code, d)
	}
	if code, _ := redeem("", token, "Anon"); code != 401 {
		t.Fatalf("anonymous redeem: %d", code)
	}
	expired, _ := signShareToken("e2e-secret", ownerID, time.Now().Add(-time.Minute))
	if code, d := redeem(bob, expired, "Bob phone"); code != 410 || errCode(d) != "SHARE_EXPIRED" {
		t.Fatalf("expired redeem: %d %v", code, d)
	}

	// Bob takes the second slot and gets the owner's links.
	code, d = redeem(bob, token, "Bob phone")
	if code != 200 {
		t.Fatalf("bob redeem: %d %v", code, d)
	}
	links, _ := d["links"].([]any)
	if d["subscription_url"] != "https://api.e2e.test/v1/sub/"+credential || len(links) == 0 || d["plan_name"] != "E2E Duo" {
		t.Fatalf("bob payload: %v", d)
	}
	for _, l := range links {
		if !strings.Contains(l.(string), credential) {
			t.Fatalf("link without the owner's credential: %v", l)
		}
	}
	bobDevice := d["device_id"].(string)
	// Bob's app lists it with the owner's plan and limits; the owner's
	// own entry shows the same limits, Bob has none of his own.
	received := func(tok string) []any {
		code, d := call(tok, http.MethodGet, "/v1/me/sharing", nil)
		if code != 200 {
			t.Fatalf("me/sharing: %d %v", code, d)
		}
		return d["received"].([]any)
	}
	if code, d := call(bob, http.MethodGet, "/v1/me/sharing", nil); code != 200 || d["own"] != nil {
		t.Fatalf("bob sharing: %d %v", code, d)
	}
	got := received(bob)
	if len(got) != 1 {
		t.Fatalf("bob received: %v", got)
	}
	shared := got[0].(map[string]any)
	sharedLimits := shared["limits"].(map[string]any)
	if shared["device_id"] != bobDevice || shared["plan_name"] != "E2E Duo" || shared["status"] != "active" ||
		shared["subscription_url"] != "https://api.e2e.test/v1/sub/"+credential || len(shared["links"].([]any)) != len(links) ||
		sharedLimits["devices_used"] != float64(2) || sharedLimits["device_limit"] != float64(2) {
		t.Fatalf("bob received entry: %v", shared)
	}
	_, d = call(owner, http.MethodGet, "/v1/me/sharing", nil)
	if own := d["own"].(map[string]any); own["plan_name"] != "E2E Duo" || own["limits"].(map[string]any)["devices_used"] != float64(2) || own["subscription_url"] != nil {
		t.Fatalf("owner sharing: %v", d)
	}
	// Scanning again reuses Bob's slot.
	if code, d := redeem(bob, token, "Bob phone"); code != 200 || d["device_id"] != bobDevice {
		t.Fatalf("bob again: %d %v", code, d)
	}
	// Carol: both slots taken.
	if code, d := redeem(carol, token, "Carol phone"); code != 403 || errCode(d) != accounts.CodeDeviceLimitReached {
		t.Fatalf("carol over limit: %d %v", code, d)
	}
	// The owner sees Bob's device and frees the slot; now Carol fits and
	// Bob, coming back, doesn't.
	_, d = call(owner, http.MethodGet, "/v1/me/devices", nil)
	var seen bool
	for _, item := range d["devices"].([]any) {
		dev := item.(map[string]any)
		if dev["id"] == bobDevice {
			seen = dev["name"] == "QR · Bob phone"
		}
	}
	if !seen {
		t.Fatalf("owner doesn't see the shared device: %v", d)
	}
	if code, _ := call(owner, http.MethodDelete, "/v1/me/devices/"+bobDevice, nil); code >= 300 {
		t.Fatalf("revoke bob: %d", code)
	}
	if got := received(bob); len(got) != 0 {
		t.Fatalf("revoked slot still listed: %v", got)
	}
	if code, d := redeem(carol, token, "Carol phone"); code != 200 {
		t.Fatalf("carol after revoke: %d %v", code, d)
	}
	if code, d := redeem(bob, token, "Bob phone"); code != 403 || errCode(d) != accounts.CodeDeviceLimitReached {
		t.Fatalf("bob after carol: %d %v", code, d)
	}

	// Owner's subscription no longer active -> the code stops working.
	if _, err := pool.Exec(ctx, `update subscriptions set status = 'past_due' where user_id = $1`, ownerID); err != nil {
		t.Fatal(err)
	}
	if code, d := redeem(carol, token, "Carol phone"); code != 422 || errCode(d) != accounts.CodeSubscriptionNotActive {
		t.Fatalf("redeem of inactive subscription: %d %v", code, d)
	}
	// Carol still sees it, now inactive and without links.
	got = received(carol)
	if len(got) != 1 || got[0].(map[string]any)["status"] != "past_due" || got[0].(map[string]any)["links"] != nil {
		t.Fatalf("carol received after past_due: %v", got)
	}
}
