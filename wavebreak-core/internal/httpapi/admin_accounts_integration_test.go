package httpapi

import (
	"bytes"
	"context"
	"database/sql"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"strings"
	"testing"
	"time"

	_ "github.com/jackc/pgx/v5/stdlib"
	"github.com/pressly/goose/v3"

	"wavebreak-core/internal/accounts"
	"wavebreak-core/internal/app"
	"wavebreak-core/internal/config"
	"wavebreak-core/internal/database"
	"wavebreak-core/internal/security"
	"wavebreak-core/internal/store"
)

// captureNotifier keeps the last reset URL so the test can confirm it.
type captureNotifier struct{ last string }

func (c *captureNotifier) SendPasswordReset(_ context.Context, _, u string, _ time.Time) (string, error) {
	c.last = u
	return "not_configured", nil
}

// TestAdminAccountManagementE2E runs the whole admin flow against a real,
// freshly migrated PostgreSQL. Set WAVEBREAK_TEST_DATABASE_URL to an
// EMPTY throwaway database to run it; it is skipped otherwise.
func TestAdminAccountManagementE2E(t *testing.T) {
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
	if err := goose.SetDialect("postgres"); err != nil {
		t.Fatal(err)
	}
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
		Accounts: config.AccountsConfig{SubscriptionURLBase: "https://api.e2e.test/v1/sub/", PasswordResetURLBase: "https://site.e2e.test/reset", PasswordResetTTL: time.Hour, AccessProtocol: "vless"},
	}, Store: st}
	srv := newServer(a)
	notifier := &captureNotifier{}
	repo := st.Accounts()
	srv.accounts.reset = accounts.NewPasswordResetService(repo, repo, accounts.SecureTokenSource{}, notifier, accounts.Argon2Hasher{}, repo, a.Config.Accounts.PasswordResetURLBase, time.Hour)
	h := srv.router()

	suffix := time.Now().Format("150405.000000")
	mkUser := func(role string) store.User {
		hash, _ := security.HashPassword("initial-password-1")
		u, err := st.CreateUserWithRole(ctx, role+"-"+suffix+"@e2e.test", hash, role)
		if err != nil {
			t.Fatal(err)
		}
		return u
	}
	admin, support, target := mkUser("admin"), mkUser("support"), mkUser("user")
	var planID, nodeID string
	if err := pool.QueryRow(ctx, `
		insert into plans (code, name, price_cents, price_minor, interval, duration_days, device_limit, traffic_limit_bytes, is_active)
		values ($1, 'E2E Starter', 900, 900, 'month', 30, 3, 107374182400, true) returning id::text`, "e2e-"+suffix).Scan(&planID); err != nil {
		t.Fatal(err)
	}
	if err := pool.QueryRow(ctx, `
		insert into nodes (code, region, status, last_heartbeat_at) values ($1, 'TR', 'online', now()) returning id::text`, "E2E-"+suffix).Scan(&nodeID); err != nil {
		t.Fatal(err)
	}

	token := func(u store.User) string {
		tok, err := srv.issueAccessToken(u.ID, u.Email, u.Role)
		if err != nil {
			t.Fatal(err)
		}
		return tok
	}
	call := func(method, path string, who *store.User, body any) (int, map[string]any) {
		var buf bytes.Buffer
		if body != nil {
			_ = json.NewEncoder(&buf).Encode(body)
		}
		req := httptest.NewRequest(method, path, &buf)
		req.Header.Set("X-Request-Id", "e2e-"+strings.ReplaceAll(path, "/", "-"))
		if who != nil {
			req.Header.Set("Authorization", "Bearer "+token(*who))
		}
		rec := httptest.NewRecorder()
		h.ServeHTTP(rec, req)
		out := map[string]any{}
		_ = json.Unmarshal(rec.Body.Bytes(), &out)
		return rec.Code, out
	}
	detailsPath := "/v1/admin/users/" + target.ID

	// 1. No subscription yet.
	code, d := call(http.MethodGet, detailsPath, &admin, nil)
	if code != 200 || d["subscription"] != nil || d["traffic"] != nil {
		t.Fatalf("details before issue: %d %v", code, d)
	}
	// 2. Plans come from Core.
	if code, _ := call(http.MethodGet, "/v1/admin/plans", &admin, nil); code != 200 {
		t.Fatalf("plans: %d", code)
	}
	// 3. RBAC: support reads, cannot issue or reset; users can do neither.
	if code, _ := call(http.MethodGet, detailsPath, &support, nil); code != 200 {
		t.Fatalf("support details: %d", code)
	}
	if code, _ := call(http.MethodPost, detailsPath+"/subscriptions", &support, map[string]string{"plan_id": planID}); code != 403 {
		t.Fatalf("support issue: %d", code)
	}
	if code, _ := call(http.MethodGet, detailsPath, &target, nil); code != 403 {
		t.Fatalf("user details: %d", code)
	}
	// 4. Issue.
	code, d = call(http.MethodPost, detailsPath+"/subscriptions", &admin, map[string]string{"plan_id": planID})
	if code != 201 {
		t.Fatalf("issue: %d %v", code, d)
	}
	sub := d["subscription"].(map[string]any)
	access := d["access"].(map[string]any)
	credential, _ := access["credential_id"].(string)
	if sub["status"] != "active" || credential == "" || access["subscription_url"] != "https://api.e2e.test/v1/sub/"+credential {
		t.Fatalf("issued state: %v", d)
	}
	traffic := d["traffic"].(map[string]any)
	devices := d["devices"].(map[string]any)
	if traffic["bytes_total"].(float64) != 0 || traffic["limit_bytes"].(float64) != 107374182400 || devices["registered"].(float64) != 0 || devices["limit"].(float64) != 3 {
		t.Fatalf("traffic/devices after issue: %v %v", traffic, devices)
	}
	// 5. Duplicate protection (admin endpoint and legacy user purchase).
	code, d = call(http.MethodPost, detailsPath+"/subscriptions", &admin, map[string]string{"plan_id": planID})
	if code != 409 || d["error"].(map[string]any)["code"] != accounts.CodeSubscriptionAlreadyActive || d["error"].(map[string]any)["request_id"] == "" {
		t.Fatalf("duplicate issue: %d %v", code, d)
	}
	if code, d := call(http.MethodPost, "/v1/subscriptions", &target, map[string]string{"plan_id": planID}); code != 409 {
		t.Fatalf("legacy duplicate purchase: %d %v", code, d)
	}
	// 5b. Extending the subscription moves its key's expiry too, otherwise
	// nodes would drop the key at the old date.
	newEnd := time.Now().UTC().Add(90 * 24 * time.Hour).Truncate(time.Second)
	if code, d := call(http.MethodPatch, "/v1/admin/subscriptions/"+sub["id"].(string), &admin, map[string]string{"expires_at": newEnd.Format(time.RFC3339)}); code != 200 {
		t.Fatalf("extend subscription: %d %v", code, d)
	}
	var grantExpiry time.Time
	var grantRevision, nodeRevision int
	_ = pool.QueryRow(ctx, `select g.expires_at, g.desired_revision, n.desired_revision from access_grants g join nodes n on n.id = g.node_id where g.id = $1`, credential).Scan(&grantExpiry, &grantRevision, &nodeRevision)
	if !grantExpiry.Equal(newEnd) || grantRevision != nodeRevision {
		t.Fatalf("grant not moved with the subscription: expiry=%v want %v, revision %d vs node %d", grantExpiry, newEnd, grantRevision, nodeRevision)
	}
	// 6. Node usage report shows up as traffic.
	// The node the credential was actually issued on (the freshest online
	// one — other tests sharing this database may have added nodes).
	var grantNodeID string
	if err := pool.QueryRow(ctx, `select node_id::text from access_grants where id = $1`, credential).Scan(&grantNodeID); err != nil {
		t.Fatal(err)
	}
	if err := st.RecordNodeUsageReport(ctx, grantNodeID, credential, 1<<30, 3<<30, time.Now()); err != nil {
		t.Fatalf("usage report: %v", err)
	}
	_, d = call(http.MethodGet, detailsPath, &admin, nil)
	traffic = d["traffic"].(map[string]any)
	if traffic["bytes_total"].(float64) != 4<<30 || traffic["bytes_up"].(float64) != 1<<30 {
		t.Fatalf("traffic after report: %v", traffic)
	}
	// 7. Device registration counts against the subscription.
	if code, d := call(http.MethodPost, "/v1/me/devices", &target, map[string]string{"name": "E2E Phone", "platform": "android"}); code != 201 && code != 200 {
		t.Fatalf("register device: %d %v", code, d)
	}
	_, d = call(http.MethodGet, detailsPath, &admin, nil)
	devices = d["devices"].(map[string]any)
	items := devices["items"].([]any)
	if devices["registered"].(float64) != 1 || len(items) != 1 || items[0].(map[string]any)["subscription_id"] != sub["id"] {
		t.Fatalf("devices after register: %v", devices)
	}
	// 7b. Issue access: idempotent while a credential exists; after it is
	// revoked (an app-bought subscription has none) a new one is issued.
	if code, _ := call(http.MethodPost, detailsPath+"/access", &support, nil); code != 403 {
		t.Fatalf("support issue access: %d", code)
	}
	code, d = call(http.MethodPost, detailsPath+"/access", &admin, nil)
	if code != 200 || d["access"].(map[string]any)["credential_id"] != credential {
		t.Fatalf("idempotent issue access: %d %v", code, d)
	}
	if _, err := st.RevokeAccessGrant(ctx, "", credential, "e2e"); err != nil {
		t.Fatal(err)
	}
	_, d = call(http.MethodGet, detailsPath, &admin, nil)
	if d["access"].(map[string]any)["credential_id"] != nil {
		t.Fatalf("credential should be gone after revoke: %v", d["access"])
	}
	code, d = call(http.MethodPost, detailsPath+"/access", &admin, nil)
	newCredential, _ := d["access"].(map[string]any)["credential_id"].(string)
	if code != 200 || newCredential == "" || newCredential == credential {
		t.Fatalf("issue access after revoke: %d %v", code, d)
	}
	// 8. Password reset: created, only hash stored, one-time, audited.
	code, d = call(http.MethodPost, detailsPath+"/password-reset", &admin, nil)
	if code != 202 || d["status"] != "reset_link_created" {
		t.Fatalf("reset request: %d %v", code, d)
	}
	u, _ := url.Parse(notifier.last)
	resetToken := u.Query().Get("token")
	var stored int
	_ = pool.QueryRow(ctx, `select count(*) from password_reset_tokens where user_id = $1 and token_hash = $2`, target.ID, security.TokenHash(resetToken)).Scan(&stored)
	var plain int
	_ = pool.QueryRow(ctx, `select count(*) from password_reset_tokens where token_hash = $1`, resetToken).Scan(&plain)
	if stored != 1 || plain != 0 {
		t.Fatalf("token storage: hashed=%d plaintext=%d", stored, plain)
	}
	if code, d := call(http.MethodPost, "/v1/auth/password-reset/confirm", nil, map[string]string{"token": resetToken, "password": "brand-new-password"}); code != 200 {
		t.Fatalf("confirm: %d %v", code, d)
	}
	if code, _ := call(http.MethodPost, "/v1/auth/password-reset/confirm", nil, map[string]string{"token": resetToken, "password": "brand-new-password"}); code != 400 {
		t.Fatalf("second confirm must fail: %d", code)
	}
	if code, _ := call(http.MethodPost, "/v1/auth/login", nil, map[string]string{"email": target.Email, "password": "brand-new-password"}); code != 200 {
		t.Fatalf("login with new password: %d", code)
	}
	// 9. Audit trail with actor, target and request id; no secrets.
	rows, err := pool.Query(ctx, `select action, coalesce(request_id, ''), metadata::text from audit_events where target_user_id = $1 order by created_at`, target.ID)
	if err != nil {
		t.Fatal(err)
	}
	defer rows.Close()
	seen := map[string]bool{}
	for rows.Next() {
		var action, reqID, meta string
		_ = rows.Scan(&action, &reqID, &meta)
		seen[action] = true
		if reqID == "" && action != accounts.AuditPasswordResetCompleted {
			t.Fatalf("audit %s without request id", action)
		}
		if strings.Contains(meta, resetToken) || strings.Contains(meta, "/v1/sub/") {
			t.Fatalf("audit %s leaks a secret: %s", action, meta)
		}
	}
	for _, want := range []string{accounts.AuditSubscriptionIssued, accounts.AuditAccessCreated, accounts.AuditPasswordResetRequested, accounts.AuditPasswordResetCompleted} {
		if !seen[want] {
			t.Fatalf("missing audit %s (have %v)", want, seen)
		}
	}
}
