package httpapi

import (
	"context"
	"database/sql"
	"errors"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/pressly/goose/v3"

	"wavebreak-core/internal/database"
	"wavebreak-core/internal/security"
	"wavebreak-core/internal/store"
)

// TestRefreshRetryKeepsOtherDevicesSignedIn: a refresh repeated because its
// answer got lost is let through; a token used twice for real ends only
// that device's chain of sessions — the account's other devices stay
// signed in (owner, 12.10: a phone's replay signed the PC and TV out).
func TestRefreshRetryKeepsOtherDevicesSignedIn(t *testing.T) {
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
	st := store.New(pool, openPIIPoolForTest(t))

	suffix := strings.ReplaceAll(time.Now().Format("150405.000000"), ".", "")
	hash, _ := security.HashPassword("refresh-password-1")
	u, err := st.CreateUser(ctx, "refresh-"+suffix+"@e2e.test", hash)
	if err != nil {
		t.Fatal(err)
	}
	exp := time.Now().Add(24 * time.Hour)
	token := func(name string) string { return name + "-" + suffix }
	for _, device := range []string{"phone-1", "pc-1"} {
		if err := st.CreateSession(ctx, u.ID, token(device), exp); err != nil {
			t.Fatal(err)
		}
	}
	rotate := func(old, next string) error {
		_, err := st.RotateRefreshToken(ctx, token(old), token(next), exp)
		return err
	}

	// The phone refreshes; its answer is lost, so it asks again with the
	// same token: allowed, and the PC is untouched.
	if err := rotate("phone-1", "phone-2"); err != nil {
		t.Fatal(err)
	}
	if err := rotate("phone-1", "phone-3"); err != nil {
		t.Fatalf("retry of a lost refresh: %v", err)
	}
	// The successor that never reached the phone is dead.
	if err := rotate("phone-2", "phone-x"); !errors.Is(err, store.ErrRefreshTokenReused) {
		t.Fatalf("unused successor: err=%v, want reuse", err)
	}
	// That reuse ended the phone's chain …
	if err := rotate("phone-3", "phone-4"); err == nil {
		t.Fatal("phone chain still alive after a real reuse")
	}
	// … and nothing else: the PC refreshes as usual.
	if err := rotate("pc-1", "pc-2"); err != nil {
		t.Fatalf("PC signed out by the phone's reuse: %v", err)
	}

	// A replay long after the rotation is a real reuse, not a retry.
	if _, err := pool.Exec(ctx, `update sessions set revoked_at = now() - interval '10 minutes' where refresh_token_hash = $1`, security.TokenHash(token("pc-1"))); err != nil {
		t.Fatal(err)
	}
	if err := rotate("pc-1", "pc-x"); !errors.Is(err, store.ErrRefreshTokenReused) {
		t.Fatalf("late replay: err=%v, want reuse", err)
	}
	if err := rotate("pc-2", "pc-3"); err == nil {
		t.Fatal("PC chain still alive after a late replay")
	}
}
