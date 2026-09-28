package httpapi

import (
	"bytes"
	"context"
	"database/sql"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"regexp"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/pressly/goose/v3"

	"wavebreak-core/internal/app"
	"wavebreak-core/internal/config"
	"wavebreak-core/internal/database"
	"wavebreak-core/internal/mailer"
	"wavebreak-core/internal/security"
	"wavebreak-core/internal/store"
)

type capturedMail struct {
	mu   sync.Mutex
	msgs []mailer.Message
}

func (c *capturedMail) Enabled() bool { return true }
func (c *capturedMail) Send(_ context.Context, m mailer.Message) error {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.msgs = append(c.msgs, m)
	return nil
}
func (c *capturedMail) all() []mailer.Message {
	c.mu.Lock()
	defer c.mu.Unlock()
	return append([]mailer.Message(nil), c.msgs...)
}

var sixDigits = regexp.MustCompile(`\b\d{6}\b`)

// lastCode: the code in the newest verification email to [to].
func (c *capturedMail) lastCode(t *testing.T, to string) string {
	t.Helper()
	msgs := c.all()
	for i := len(msgs) - 1; i >= 0; i-- {
		if msgs[i].To == to && strings.Contains(msgs[i].Subject, "WAVEBREAK") && sixDigits.MatchString(msgs[i].Subject) {
			return sixDigits.FindString(msgs[i].Subject)
		}
	}
	t.Fatalf("no code mailed to %s", to)
	return ""
}

// TestEmailVerificationE2E: sign-up with the verification step, the code
// gate on login, wrong/locked codes, the account-screen flow for an old
// account, and that older clients keep the old behaviour — against a real
// PostgreSQL (WAVEBREAK_TEST_DATABASE_URL).
func TestEmailVerificationE2E(t *testing.T) {
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
	a := &app.App{Config: config.Config{JWTSecret: "e2e-secret", AccessTokenTTL: time.Hour, RefreshTokenTTL: time.Hour}, Store: st}
	srv := newServer(a)
	mail := &capturedMail{}
	srv.mail = mail
	h := srv.router()

	call := func(method, path, token string, body any, features string) (int, map[string]any) {
		t.Helper()
		var buf bytes.Buffer
		if body != nil {
			_ = json.NewEncoder(&buf).Encode(body)
		}
		req := httptest.NewRequest(method, path, &buf)
		req.Header.Set("Content-Type", "application/json")
		if token != "" {
			req.Header.Set("Authorization", "Bearer "+token)
		}
		if features != "" {
			req.Header.Set("X-Wavebreak-Features", features)
		}
		rec := httptest.NewRecorder()
		h.ServeHTTP(rec, req)
		out := map[string]any{}
		_ = json.Unmarshal(rec.Body.Bytes(), &out)
		return rec.Code, out
	}
	const feat = "hysteria-obfs,email-verification"
	suffix := time.Now().Format("150405.000000")
	email := "verify-" + suffix + "@e2e.test"
	password := "a-long-password-1"

	// 1. Sign-up from a new app: no tokens, a code in the mail.
	code, out := call("POST", "/v1/auth/register", "", map[string]any{"email": email, "password": password, "language": "ru"}, feat)
	if code != http.StatusCreated || out["verification_required"] != true || out["code_sent"] != true || out["tokens"] != nil {
		t.Fatalf("register: %d %v", code, out)
	}
	first := mail.lastCode(t, email)
	if !strings.Contains(mail.all()[0].Subject, "Код подтверждения") {
		t.Fatalf("Russian email expected: %q", mail.all()[0].Subject)
	}

	// 2. The password alone doesn't get in; within the cooldown no new mail.
	code, out = call("POST", "/v1/auth/login", "", map[string]any{"email": email, "password": password}, feat)
	if code != http.StatusForbidden || out["code"] != "email_not_verified" {
		t.Fatalf("login before verify: %d %v", code, out)
	}
	if n := len(mail.all()); n != 1 {
		t.Fatalf("cooldown ignored: %d mails", n)
	}
	// A wrong password never reveals the verification state.
	if code, _ = call("POST", "/v1/auth/login", "", map[string]any{"email": email, "password": "wrong-password-xx"}, feat); code != http.StatusUnauthorized {
		t.Fatalf("wrong password: %d", code)
	}

	// 3. Wrong code, then the right one: tokens and a welcome email.
	wrong := "000000"
	if first == wrong {
		wrong = "111111"
	}
	if code, out = call("POST", "/v1/auth/email/verify", "", map[string]any{"email": email, "code": wrong}, feat); code != http.StatusBadRequest || out["code"] != "invalid_code" {
		t.Fatalf("wrong code: %d %v", code, out)
	}
	code, out = call("POST", "/v1/auth/email/verify", "", map[string]any{"email": email, "code": first}, feat)
	if code != http.StatusOK || out["access_token"] == nil {
		t.Fatalf("verify: %d %v", code, out)
	}
	token := out["access_token"].(string)
	deadline := time.Now().Add(3 * time.Second)
	for time.Now().Before(deadline) && len(mail.all()) < 2 {
		time.Sleep(20 * time.Millisecond)
	}
	if msgs := mail.all(); len(msgs) != 2 || !strings.Contains(msgs[1].Subject, "Добро пожаловать") {
		t.Fatalf("welcome mail missing: %+v", msgs)
	}

	// 4. The code is spent: no more tokens from /auth/email/verify, ever.
	if code, out = call("POST", "/v1/auth/email/verify", "", map[string]any{"email": email, "code": first}, feat); code != http.StatusBadRequest {
		t.Fatalf("second verify issued tokens: %d %v", code, out)
	}
	if code, out = call("GET", "/v1/me", token, nil, feat); code != http.StatusOK || out["email_verified"] != true {
		t.Fatalf("me after verify: %d %v", code, out)
	}
	if code, _ = call("POST", "/v1/auth/login", "", map[string]any{"email": email, "password": password}, feat); code != http.StatusOK {
		t.Fatalf("login after verify: %d", code)
	}

	// 5. Guessing: five wrong codes lock it.
	email2 := "lock-" + suffix + "@e2e.test"
	call("POST", "/v1/auth/register", "", map[string]any{"email": email2, "password": password}, feat)
	good := mail.lastCode(t, email2)
	var last int
	for i := 0; i < store.MaxEmailCodeAttempts; i++ {
		guess := "12345" + string(rune('0'+i))
		if guess == good {
			guess = "99999" + string(rune('0'+i))
		}
		last, _ = call("POST", "/v1/auth/email/verify", "", map[string]any{"email": email2, "code": guess}, feat)
	}
	if last != http.StatusTooManyRequests {
		t.Fatalf("fifth wrong code: %d", last)
	}
	if code, _ = call("POST", "/v1/auth/email/verify", "", map[string]any{"email": email2, "code": good}, feat); code != http.StatusTooManyRequests {
		t.Fatalf("locked code accepted: %d", code)
	}

	// 6. Older app (no feature) and the website: exactly as before.
	email3 := "old-" + suffix + "@e2e.test"
	code, out = call("POST", "/v1/auth/register", "", map[string]any{"email": email3, "password": password}, "hysteria-obfs")
	tokens, _ := out["tokens"].(map[string]any)
	if code != http.StatusCreated || tokens["access_token"] == nil {
		t.Fatalf("old-client register: %d %v", code, out)
	}
	if code, _ = call("POST", "/v1/auth/login", "", map[string]any{"email": email3, "password": password}, ""); code != http.StatusOK {
		t.Fatalf("old-client login: %d", code)
	}
	// Resend is silent for accounts outside the flow, and for unknown ones.
	before := len(mail.all())
	for _, e := range []string{email3, "nobody-" + suffix + "@e2e.test"} {
		if code, _ = call("POST", "/v1/auth/email/resend", "", map[string]any{"email": e}, feat); code != http.StatusAccepted {
			t.Fatalf("resend %s: %d", e, code)
		}
	}
	if len(mail.all()) != before {
		t.Fatal("resend mailed an account outside the flow")
	}

	// 7. An existing account confirms from the account screen.
	hash, _ := security.HashPassword(password)
	oldUser, err := st.CreateUser(ctx, "legacy-"+suffix+"@e2e.test", hash)
	if err != nil {
		t.Fatal(err)
	}
	legacyToken, err := srv.issueAccessToken(oldUser.ID, oldUser.Email, oldUser.Role)
	if err != nil {
		t.Fatal(err)
	}
	if code, out = call("GET", "/v1/me", legacyToken, nil, ""); out["email_verified"] != false || out["email_verification_available"] != true {
		t.Fatalf("legacy me: %d %v", code, out)
	}
	if code, _ = call("POST", "/v1/me/email/send-code", legacyToken, map[string]any{"language": "en"}, ""); code != http.StatusAccepted {
		t.Fatalf("legacy send-code: %d", code)
	}
	if code, _ = call("POST", "/v1/me/email/send-code", legacyToken, nil, ""); code != http.StatusTooManyRequests {
		t.Fatalf("legacy resend within a minute: %d", code)
	}
	legacyCode := mail.lastCode(t, oldUser.Email)
	if !strings.HasPrefix(mail.all()[len(mail.all())-1].Subject, "Your WAVEBREAK code") {
		t.Fatal("English email expected")
	}
	if code, out = call("POST", "/v1/me/email/verify", legacyToken, map[string]any{"code": legacyCode}, ""); code != http.StatusOK || out["email_verified"] != true {
		t.Fatalf("legacy verify: %d %v", code, out)
	}
	if code, _ = call("POST", "/v1/me/email/send-code", legacyToken, nil, ""); code != http.StatusConflict {
		t.Fatalf("send-code when verified: %d", code)
	}
	// An old account can't be signed into through the code endpoint.
	if code, _ = call("POST", "/v1/auth/email/verify", "", map[string]any{"email": oldUser.Email, "code": legacyCode}, feat); code != http.StatusBadRequest {
		t.Fatalf("legacy account got tokens via code: %d", code)
	}

	// 8. What the "subscription active" email reads.
	var planID string
	if err := pool.QueryRow(ctx, `
		insert into plans (code, name, price_cents, price_minor, interval, duration_days, device_limit, traffic_limit_bytes, is_active)
		values ($1, 'Mail Plus', 499, 499, 'month', 30, 3, 0, true) returning id::text`, "mail-"+suffix).Scan(&planID); err != nil {
		t.Fatal(err)
	}
	end := time.Now().Add(30 * 24 * time.Hour)
	sub, err := st.CreateSubscriptionForOptions(ctx, oldUser.ID, planID, "admin", oldUser.ID, "active", &end)
	if err != nil {
		t.Fatal(err)
	}
	notice, err := st.SubscriptionNoticeFor(ctx, sub.ID)
	if err != nil || !notice.Live() || notice.PlanName != "Mail Plus" || notice.Email != oldUser.Email || notice.Language != "en" || notice.PeriodEnd == nil {
		t.Fatalf("notice: %+v %v", notice, err)
	}
}
