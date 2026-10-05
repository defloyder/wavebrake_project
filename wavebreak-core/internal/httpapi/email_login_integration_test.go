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

	"wavebreak-core/internal/app"
	"wavebreak-core/internal/config"
	"wavebreak-core/internal/database"
	"wavebreak-core/internal/store"
)

// TestEmailLoginCodeE2E: sign-in with a code mailed to an existing
// account; unknown addresses look the same; wrong and spent codes don't
// get in — against a real PostgreSQL (WAVEBREAK_TEST_DATABASE_URL).
func TestEmailLoginCodeE2E(t *testing.T) {
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
	a := &app.App{Config: config.Config{JWTSecret: "e2e-secret", AccessTokenTTL: time.Hour, RefreshTokenTTL: time.Hour}, Store: store.New(pool)}
	srv := newServer(a)
	mail := &capturedMail{}
	srv.mail = mail
	h := srv.router()

	call := func(path string, body any) (int, map[string]any) {
		t.Helper()
		var buf bytes.Buffer
		_ = json.NewEncoder(&buf).Encode(body)
		req := httptest.NewRequest("POST", path, &buf)
		req.Header.Set("Content-Type", "application/json")
		rec := httptest.NewRecorder()
		h.ServeHTTP(rec, req)
		out := map[string]any{}
		_ = json.Unmarshal(rec.Body.Bytes(), &out)
		return rec.Code, out
	}

	email := "login-code-" + time.Now().Format("150405.000000") + "@e2e.test"
	if code, out := call("/v1/auth/register", map[string]any{"email": email, "password": "a-long-password-1"}); code != http.StatusCreated {
		t.Fatalf("register: %d %v", code, out)
	}

	// Unknown address: the same 202, and nothing is mailed.
	before := len(mail.all())
	if code, _ := call("/v1/auth/email/login-code/request", map[string]any{"email": "nobody-" + email}); code != http.StatusAccepted {
		t.Fatalf("unknown request: %d", code)
	}
	if len(mail.all()) != before {
		t.Fatal("mail sent to an unknown address")
	}

	// Existing account: a sign-in code in Russian.
	if code, out := call("/v1/auth/email/login-code/request", map[string]any{"email": email, "language": "ru"}); code != http.StatusAccepted {
		t.Fatalf("request: %d %v", code, out)
	}
	msgs := mail.all()
	if !strings.Contains(msgs[len(msgs)-1].Subject, "Код для входа") {
		t.Fatalf("login-code email expected: %q", msgs[len(msgs)-1].Subject)
	}
	good := mail.lastCode(t, email)

	// Within the cooldown a second request mails nothing.
	if code, _ := call("/v1/auth/email/login-code/request", map[string]any{"email": email}); code != http.StatusTooManyRequests {
		t.Fatalf("cooldown: %d", code)
	}

	wrong := "000000"
	if good == wrong {
		wrong = "111111"
	}
	if code, out := call("/v1/auth/email/login-code/confirm", map[string]any{"email": email, "code": wrong}); code != http.StatusBadRequest || out["code"] != "invalid_code" {
		t.Fatalf("wrong code: %d %v", code, out)
	}
	code, out := call("/v1/auth/email/login-code/confirm", map[string]any{"email": email, "code": good})
	if code != http.StatusOK || out["access_token"] == nil {
		t.Fatalf("confirm: %d %v", code, out)
	}
	// Spent.
	if code, _ := call("/v1/auth/email/login-code/confirm", map[string]any{"email": email, "code": good}); code == http.StatusOK {
		t.Fatal("a spent code signed in again")
	}
}
