package store

import (
	"context"
	"errors"
	"os"
	"testing"

	"github.com/jackc/pgx/v5/pgxpool"
)

// Runs against two real databases when WAVEBREAK_TEST_DATABASE_URL and
// WAVEBREAK_TEST_PII_DATABASE_URL are set (both migrated). Skipped otherwise.
func openPIITestStores(t *testing.T) (*Store, *pgxpool.Pool, *pgxpool.Pool) {
	t.Helper()
	mainURL := os.Getenv("WAVEBREAK_TEST_DATABASE_URL")
	piiURL := os.Getenv("WAVEBREAK_TEST_PII_DATABASE_URL")
	if mainURL == "" || piiURL == "" {
		t.Skip("set WAVEBREAK_TEST_DATABASE_URL and WAVEBREAK_TEST_PII_DATABASE_URL to run")
	}
	ctx := context.Background()
	mainPool, err := pgxpool.New(ctx, mainURL)
	if err != nil {
		t.Fatalf("connect main: %v", err)
	}
	piiPool, err := pgxpool.New(ctx, piiURL)
	if err != nil {
		t.Fatalf("connect pii: %v", err)
	}
	if _, err := mainPool.Exec(ctx, "truncate users cascade"); err != nil {
		t.Fatalf("reset users: %v", err)
	}
	if _, err := piiPool.Exec(ctx, "truncate pii_users"); err != nil {
		t.Fatalf("reset pii_users: %v", err)
	}
	t.Cleanup(func() {
		mainPool.Close()
		piiPool.Close()
	})
	return New(mainPool, piiPool), mainPool, piiPool
}

func countRows(t *testing.T, pool *pgxpool.Pool, query string, args ...any) int {
	t.Helper()
	var n int
	if err := pool.QueryRow(context.Background(), query, args...).Scan(&n); err != nil {
		t.Fatalf("count %q: %v", query, err)
	}
	return n
}

func TestPIISplitAccountLifecycle(t *testing.T) {
	st, mainPool, piiPool := openPIITestStores(t)
	ctx := context.Background()

	created, err := st.CreateUserWithRole(ctx, "  Owner@Example.COM ", "hash-1", "user")
	if err != nil {
		t.Fatalf("create: %v", err)
	}
	if created.Email != "owner@example.com" {
		t.Fatalf("email not normalized: %q", created.Email)
	}
	if n := countRows(t, piiPool, "select count(*) from pii_users where user_id = $1", created.ID); n != 1 {
		t.Fatalf("pii row count = %d, want 1", n)
	}
	if n := countRows(t, mainPool, "select count(*) from users where email is not null or password_hash is not null"); n != 0 {
		t.Fatalf("main DB still holds credentials for %d user(s) created after the split", n)
	}

	byEmail, err := st.GetUserByEmail(ctx, "OWNER@example.com")
	if err != nil {
		t.Fatalf("get by email: %v", err)
	}
	if byEmail.ID != created.ID || byEmail.PasswordHash != "hash-1" {
		t.Fatalf("lookup by email returned %+v", byEmail)
	}

	if _, err := st.CreateUserWithRole(ctx, "owner@example.com", "hash-2", "user"); !errors.Is(err, ErrConflict) {
		t.Fatalf("duplicate email error = %v, want ErrConflict", err)
	}
	if n := countRows(t, mainPool, "select count(*) from users"); n != 1 {
		t.Fatalf("failed duplicate left %d main users, want 1 (compensation)", n)
	}

	if err := st.SetUserPassword(ctx, "owner@example.com", "hash-3"); err != nil {
		t.Fatalf("set password: %v", err)
	}
	reloaded, err := st.GetUserByID(ctx, created.ID)
	if err != nil {
		t.Fatalf("get by id: %v", err)
	}
	if reloaded.PasswordHash != "hash-3" || reloaded.Email != "owner@example.com" {
		t.Fatalf("after password reset: %+v", reloaded)
	}
	if err := st.SetUserPassword(ctx, "nobody@example.com", "x"); !errors.Is(err, ErrNotFound) {
		t.Fatalf("reset for unknown email = %v, want ErrNotFound", err)
	}

	users, err := st.ListUsers(ctx)
	if err != nil {
		t.Fatalf("list: %v", err)
	}
	if len(users) != 1 || users[0].Email != "owner@example.com" {
		t.Fatalf("list users = %+v", users)
	}

	if err := st.AdminDeleteUser(ctx, created.ID); err != nil {
		t.Fatalf("delete: %v", err)
	}
	if n := countRows(t, piiPool, "select count(*) from pii_users"); n != 0 {
		t.Fatalf("pii rows after account deletion = %d, want 0", n)
	}
	if _, err := st.GetUserByEmail(ctx, "owner@example.com"); !errors.Is(err, ErrNotFound) {
		t.Fatalf("lookup after delete = %v, want ErrNotFound", err)
	}
}

func TestImportLegacyPIIIsIdempotent(t *testing.T) {
	st, mainPool, piiPool := openPIITestStores(t)
	ctx := context.Background()

	if _, err := mainPool.Exec(ctx, `
		insert into users (email, username, password_hash, password_algo, role)
		values ('legacy@example.com', 'legacy', 'old-hash', 'argon2id', 'user')`); err != nil {
		t.Fatalf("seed legacy user: %v", err)
	}
	first, err := st.ImportLegacyPII(ctx)
	if err != nil {
		t.Fatalf("first import: %v", err)
	}
	second, err := st.ImportLegacyPII(ctx)
	if err != nil {
		t.Fatalf("second import: %v", err)
	}
	if first != 1 || second != 0 {
		t.Fatalf("import counts = %d then %d, want 1 then 0", first, second)
	}
	if n := countRows(t, piiPool, "select count(*) from pii_users where email = 'legacy@example.com' and password_hash = 'old-hash'"); n != 1 {
		t.Fatalf("legacy row not copied intact")
	}
}
