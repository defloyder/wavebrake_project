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
	"regexp"
	"strings"
	"testing"
	"time"

	"github.com/pressly/goose/v3"

	"wavebreak-core/internal/app"
	"wavebreak-core/internal/config"
	"wavebreak-core/internal/database"
	"wavebreak-core/internal/security"
	"wavebreak-core/internal/store"
)

var resetLink = regexp.MustCompile(`https://wavebreak\.com\.tr/reset-password\?token=[A-Za-z0-9%_\-.~]+`)

// TestPasswordResetE2E: "Forgot password?" -> email -> the reset page ->
// sign in with the new password; the link works once; the endpoint never
// reveals accounts and doesn't flood a mailbox.
func TestPasswordResetE2E(t *testing.T) {
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
		Accounts: config.AccountsConfig{PasswordResetURLBase: "https://wavebreak.com.tr/reset-password", PasswordResetTTL: time.Hour},
	}, Store: st}
	srv := newServer(a)
	mail := &capturedMail{}
	srv.mail = mail
	srv.accounts = newAccountServices(a, resetMailer{mail: mail, store: st})
	h := srv.router()

	post := func(path string, body any) int {
		t.Helper()
		var buf bytes.Buffer
		_ = json.NewEncoder(&buf).Encode(body)
		req := httptest.NewRequest("POST", path, &buf)
		req.Header.Set("Content-Type", "application/json")
		rec := httptest.NewRecorder()
		h.ServeHTTP(rec, req)
		return rec.Code
	}
	page := func(method, target string, form url.Values) (int, string, http.Header) {
		t.Helper()
		var req *http.Request
		if form != nil {
			req = httptest.NewRequest(method, target, strings.NewReader(form.Encode()))
			req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
		} else {
			req = httptest.NewRequest(method, target, nil)
		}
		rec := httptest.NewRecorder()
		h.ServeHTTP(rec, req)
		return rec.Code, rec.Body.String(), rec.Header()
	}

	suffix := time.Now().Format("150405.000000")
	email := "reset-" + suffix + "@e2e.test"
	hash, _ := security.HashPassword("old-password-123")
	user, err := st.CreateUser(ctx, email, hash)
	if err != nil {
		t.Fatal(err)
	}
	_ = st.SetEmailLanguage(ctx, user.ID, "ru")

	// Unknown address: the same answer, no mail.
	if code := post("/v1/auth/password-reset/request", map[string]any{"email": "nobody-" + suffix + "@e2e.test"}); code != http.StatusAccepted {
		t.Fatalf("unknown email: %d", code)
	}
	if len(mail.all()) != 0 {
		t.Fatal("mailed an unknown address")
	}

	// The real one: a link in Russian; a second request within a minute sends nothing.
	if code := post("/v1/auth/password-reset/request", map[string]any{"email": strings.ToUpper(email)}); code != http.StatusAccepted {
		t.Fatalf("request: %d", code)
	}
	if code := post("/v1/auth/password-reset/request", map[string]any{"email": email}); code != http.StatusAccepted {
		t.Fatalf("second request: %d", code)
	}
	msgs := mail.all()
	if len(msgs) != 1 || msgs[0].To != email || !strings.Contains(msgs[0].Subject, "Сброс пароля") {
		t.Fatalf("reset mail: %+v", msgs)
	}
	link := resetLink.FindString(msgs[0].Text)
	if link == "" {
		t.Fatalf("no link in:\n%s", msgs[0].Text)
	}
	u, _ := url.Parse(link)
	token := u.Query().Get("token")

	// The page: a form, no caching, no referrer.
	code, body, hdr := page("GET", "/reset-password?"+u.RawQuery, nil)
	if code != http.StatusOK || !strings.Contains(body, `name="password2"`) || !strings.Contains(body, "Новый пароль") {
		t.Fatalf("page: %d\n%s", code, body)
	}
	if hdr.Get("Cache-Control") != "no-store" || hdr.Get("Referrer-Policy") != "no-referrer" {
		t.Fatalf("headers: %v", hdr)
	}
	// Mismatch and too short are caught on the page.
	if _, body, _ = page("POST", "/reset-password?lang=ru", url.Values{"token": {token}, "password": {"new-password-123"}, "password2": {"other-password-1"}}); !strings.Contains(body, "не совпадают") {
		t.Fatalf("mismatch:\n%s", body)
	}
	if _, body, _ = page("POST", "/reset-password?lang=ru", url.Values{"token": {token}, "password": {"short"}, "password2": {"short"}}); !strings.Contains(body, "не короче 10") {
		t.Fatal("short password accepted")
	}
	// The real change.
	if _, body, _ = page("POST", "/reset-password?lang=ru", url.Values{"token": {token}, "password": {"new-password-123"}, "password2": {"new-password-123"}}); !strings.Contains(body, "Пароль изменён") {
		t.Fatalf("change:\n%s", body)
	}
	if code := post("/v1/auth/login", map[string]any{"email": email, "password": "new-password-123"}); code != http.StatusOK {
		t.Fatalf("login with new password: %d", code)
	}
	if code := post("/v1/auth/login", map[string]any{"email": email, "password": "old-password-123"}); code != http.StatusUnauthorized {
		t.Fatalf("old password still works: %d", code)
	}
	// The link works once.
	if _, body, _ = page("POST", "/reset-password?lang=en", url.Values{"token": {token}, "password": {"another-pass-123"}, "password2": {"another-pass-123"}}); !strings.Contains(body, "invalid or has expired") {
		t.Fatalf("reused link:\n%s", body)
	}
	// No token at all.
	if _, body, _ = page("GET", "/reset-password?lang=en", nil); !strings.Contains(body, "invalid or has expired") || strings.Contains(body, "<form") {
		t.Fatalf("no token:\n%s", body)
	}
	// HTML-escaped token (no injection through the query string).
	if _, body, _ = page("GET", "/reset-password?token=%22%3E%3Cscript%3E", nil); strings.Contains(body, "<script>") {
		t.Fatal("token not escaped")
	}
}
