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
	"wavebreak-core/internal/security"
	"wavebreak-core/internal/store"
)

func TestLinkVaultSealOpens(t *testing.T) {
	added := time.Date(2026, 10, 15, 12, 0, 0, 0, time.UTC)
	entries := []customLinkEntry{{Link: "vless://u@h:443#Germany", Added: added}}
	nonce, ct, err := sealLinks("secret-a", "user-1", entries)
	if err != nil {
		t.Fatal(err)
	}
	if bytes.Contains(ct, []byte("vless://")) {
		t.Fatal("the link is readable in the stored bytes")
	}
	got, err := openLinks("secret-a", "user-1", nonce, ct)
	if err != nil || len(got) != 1 || got[0].Link != entries[0].Link || !got[0].Added.Equal(added) {
		t.Fatalf("open: %v %+v", err, got)
	}
	// Another user's id or another secret: it doesn't open.
	if _, err := openLinks("secret-a", "user-2", nonce, ct); err == nil {
		t.Fatal("opened as another user")
	}
	if _, err := openLinks("secret-b", "user-1", nonce, ct); err == nil {
		t.Fatal("opened with another secret")
	}
}

func TestLinkDocValidate(t *testing.T) {
	now := time.Now()
	ok := customLinkDoc{Version: 2, Entries: []customLinkEntry{{Link: "https://sub.example/abc", Added: now}}}
	if err := ok.validate(); err != nil {
		t.Fatal(err)
	}
	bad := []customLinkDoc{
		{Version: -1},
		{Entries: []customLinkEntry{{Link: "not a link", Added: now}}},
		{Entries: []customLinkEntry{{Link: "vless://x", Added: time.Time{}}}},
		{Entries: []customLinkEntry{{Link: "vless://" + strings.Repeat("a", maxLinkLength), Added: now}}},
		{Entries: make([]customLinkEntry, maxLinkEntries+1)},
	}
	for i, d := range bad {
		if d.validate() == nil {
			t.Errorf("case %d accepted", i)
		}
	}
}

// Two devices of one account against a real database; set
// WAVEBREAK_TEST_DATABASE_URL to a throwaway database.
func TestCustomLinksSyncE2E(t *testing.T) {
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
	srv := newServer(&app.App{Config: config.Config{
		JWTSecret: "e2e-secret", AccessTokenTTL: time.Hour, RefreshTokenTTL: time.Hour,
	}, Store: st})
	h := srv.router()
	hash, _ := security.HashPassword("initial-password-1")
	mk := func(name string) string {
		u, err := st.CreateUserWithRole(ctx, "links-"+name+"-"+time.Now().Format("150405000000")+"@e2e.test", hash, "user")
		if err != nil {
			t.Fatal(err)
		}
		tok, err := srv.issueAccessToken(u.ID, u.Email, u.Role)
		if err != nil {
			t.Fatal(err)
		}
		return tok
	}
	alice, bob := mk("alice"), mk("bob")
	call := func(tok, method string, body any) (int, customLinkDoc) {
		var buf bytes.Buffer
		if body != nil {
			_ = json.NewEncoder(&buf).Encode(body)
		}
		req := httptest.NewRequest(method, "/v1/me/custom-links", &buf)
		req.Header.Set("Authorization", "Bearer "+tok)
		rec := httptest.NewRecorder()
		h.ServeHTTP(rec, req)
		var out customLinkDoc
		_ = json.Unmarshal(rec.Body.Bytes(), &out)
		return rec.Code, out
	}
	now := time.Now().UTC().Truncate(time.Second)
	link := customLinkEntry{Link: "vless://u@h:443#DE", Added: now}

	if code, d := call(alice, http.MethodGet, nil); code != 200 || d.Version != 0 || len(d.Entries) != 0 {
		t.Fatalf("empty vault: %d %+v", code, d)
	}
	if code, d := call(alice, http.MethodPut, customLinkDoc{Version: 0, Entries: []customLinkEntry{link}}); code != 200 || d.Version != 1 {
		t.Fatalf("first write: %d %+v", code, d)
	}
	// The second device read version 0 too: refused, given the current one.
	code, d := call(alice, http.MethodPut, customLinkDoc{Version: 0, Entries: nil})
	if code != 409 || d.Version != 1 || len(d.Entries) != 1 || d.Entries[0].Link != link.Link {
		t.Fatalf("stale write: %d %+v", code, d)
	}
	if code, d := call(alice, http.MethodGet, nil); code != 200 || d.Version != 1 || len(d.Entries) != 1 {
		t.Fatalf("read back: %d %+v", code, d)
	}
	// Another account sees nothing of it.
	if code, d := call(bob, http.MethodGet, nil); code != 200 || len(d.Entries) != 0 {
		t.Fatalf("other account: %d %+v", code, d)
	}
}
