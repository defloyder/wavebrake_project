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

// TestRegisterDeviceReusesInstallation: signing in again on the same
// installation (same install_id) returns the same device and takes no new
// slot; a revoked one is not brought back; another installation is a new
// device and hits the limit as before.
func TestRegisterDeviceReusesInstallation(t *testing.T) {
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

	suffix := strings.ReplaceAll(time.Now().Format("150405.000000"), ".", "")
	var planID string
	if err := pool.QueryRow(ctx, `
		insert into plans (code, name, price_cents, price_minor, interval, duration_days, device_limit, traffic_limit_bytes, is_active)
		values ($1, 'Install Id', 999, 999, 'month', 30, 2, 0, true)
		returning id::text`, "install-"+suffix).Scan(&planID); err != nil {
		t.Fatal(err)
	}
	hash, _ := security.HashPassword("install-password-1")
	u, err := st.CreateUser(ctx, "install-"+suffix+"@e2e.test", hash)
	if err != nil {
		t.Fatal(err)
	}
	end := time.Now().Add(30 * 24 * time.Hour)
	if _, err := st.CreateSubscriptionForOptions(ctx, u.ID, planID, "web", u.ID, "active", &end); err != nil {
		t.Fatal(err)
	}

	first, reused, err := st.RegisterDevice(ctx, u.ID, "Xiaomi 14", "android", "inst-a")
	if err != nil || reused {
		t.Fatalf("first registration: reused=%v err=%v", reused, err)
	}
	for i := 0; i < 3; i++ {
		again, reused, err := st.RegisterDevice(ctx, u.ID, "Xiaomi 14T", "android", "inst-a")
		if err != nil || !reused || again.ID != first.ID {
			t.Fatalf("sign-in %d: id=%s reused=%v err=%v, want %s", i, again.ID, reused, err, first.ID)
		}
		if again.Name != "Xiaomi 14T" {
			t.Fatalf("name not updated: %q", again.Name)
		}
	}
	active := func() int {
		var n int
		if err := pool.QueryRow(ctx, `select count(*) from devices where user_id = $1 and revoked_at is null`, u.ID).Scan(&n); err != nil {
			t.Fatal(err)
		}
		return n
	}
	if n := active(); n != 1 {
		t.Fatalf("active devices after repeated sign-ins = %d, want 1", n)
	}

	if _, _, err := st.RegisterDevice(ctx, u.ID, "PC", "windows", "inst-b"); err != nil {
		t.Fatalf("second installation: %v", err)
	}
	if _, _, err := st.RegisterDevice(ctx, u.ID, "Tablet", "android", "inst-c"); !errors.Is(err, store.ErrLimitReached) {
		t.Fatalf("third installation on limit 2: %v", err)
	}
	if _, _, err := st.RegisterDevice(ctx, u.ID, "Old app", "android", ""); !errors.Is(err, store.ErrLimitReached) {
		t.Fatalf("registration without install_id on a full limit: %v", err)
	}

	if err := st.RevokeDevice(ctx, u.ID, first.ID); err != nil {
		t.Fatal(err)
	}
	back, reused, err := st.RegisterDevice(ctx, u.ID, "Xiaomi 14T", "android", "inst-a")
	if err != nil || reused || back.ID == first.ID {
		t.Fatalf("after revoke: id=%s reused=%v err=%v — a revoked device must not come back", back.ID, reused, err)
	}
}
