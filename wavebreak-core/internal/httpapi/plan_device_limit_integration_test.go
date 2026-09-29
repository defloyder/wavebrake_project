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

// TestPlanDeviceLimitRaisesLiveSubscriptions: a subscription bought while
// the plan allowed 1 device gets the plan's new limit when an admin raises
// it, never loses devices when the limit is lowered, and keeps an override.
func TestPlanDeviceLimitRaisesLiveSubscriptions(t *testing.T) {
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
	var plan store.Plan
	if err := pool.QueryRow(ctx, `
		insert into plans (code, name, price_cents, price_minor, interval, duration_days, device_limit, traffic_limit_bytes, is_active)
		values ($1, 'Limit Flagship', 999, 999, 'month', 30, 1, 0, true)
		returning id::text, code, name, description, price_minor, currency, interval, duration_days, traffic_limit_bytes, concurrent_connection_limit, is_active, is_public, sort_order`,
		"limit-"+suffix).Scan(&plan.ID, &plan.Code, &plan.Name, &plan.Description, &plan.PriceMinor, &plan.Currency, &plan.Interval, &plan.DurationDays, &plan.TrafficLimitBytes, &plan.ConcurrentConnectionLimit, &plan.IsActive, &plan.IsPublic, &plan.SortOrder); err != nil {
		t.Fatal(err)
	}
	hash, _ := security.HashPassword("limit-password-1")
	end := time.Now().Add(30 * 24 * time.Hour)
	newSub := func(name string) (store.User, string) {
		u, err := st.CreateUser(ctx, name+"-"+suffix+"@e2e.test", hash)
		if err != nil {
			t.Fatal(err)
		}
		sub, err := st.CreateSubscriptionForOptions(ctx, u.ID, plan.ID, "web", u.ID, "active", &end)
		if err != nil {
			t.Fatal(err)
		}
		return u, sub.ID
	}
	buyer, buyerSub := newSub("limit-buyer")
	_, overSub := newSub("limit-override")
	if _, err := pool.Exec(ctx, `update subscriptions set device_limit_override = 2 where id = $1`, overSub); err != nil {
		t.Fatal(err)
	}
	snapshot := func(id string) int {
		var n int
		if err := pool.QueryRow(ctx, `select device_limit_snapshot from subscriptions where id = $1`, id).Scan(&n); err != nil {
			t.Fatal(err)
		}
		return n
	}
	if got := snapshot(buyerSub); got != 1 {
		t.Fatalf("snapshot at purchase = %d, want 1", got)
	}
	if _, err := st.CreateDevice(ctx, buyer.ID, "phone", "android"); err != nil {
		t.Fatal(err)
	}
	if _, err := st.CreateDevice(ctx, buyer.ID, "tablet", "android"); !errors.Is(err, store.ErrLimitReached) {
		t.Fatalf("second device on limit 1: %v", err)
	}

	plan.DeviceLimit = 10
	if _, err := st.UpdatePlan(ctx, plan); err != nil {
		t.Fatal(err)
	}
	if got := snapshot(buyerSub); got != 10 {
		t.Fatalf("snapshot after raise = %d, want 10", got)
	}
	if _, err := st.CreateDevice(ctx, buyer.ID, "tablet", "android"); err != nil {
		t.Fatalf("second device after raise: %v", err)
	}
	var override int
	if err := pool.QueryRow(ctx, `select device_limit_override from subscriptions where id = $1`, overSub).Scan(&override); err != nil || override != 2 {
		t.Fatalf("override = %d (%v), want 2", override, err)
	}

	plan.DeviceLimit = 3
	if _, err := st.UpdatePlan(ctx, plan); err != nil {
		t.Fatal(err)
	}
	if got := snapshot(buyerSub); got != 10 {
		t.Fatalf("snapshot after lowering the plan = %d, want 10 (never lowered)", got)
	}
}
