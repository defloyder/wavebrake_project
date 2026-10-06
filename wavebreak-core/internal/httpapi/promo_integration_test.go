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
	"testing"
	"time"

	"github.com/pressly/goose/v3"

	"wavebreak-core/internal/app"
	"wavebreak-core/internal/config"
	"wavebreak-core/internal/database"
	"wavebreak-core/internal/security"
	"wavebreak-core/internal/store"
)

// TestPromoCodesE2E: an admin creates codes and a plan offer, a user
// checks them (prices with the discount, every refusal reason), a
// purchase redeems one (limit and once-per-user hold), and choosing a
// plan doesn't grant it without payment. Against a real PostgreSQL: set
// WAVEBREAK_TEST_DATABASE_URL to a throwaway database.
func TestPromoCodesE2E(t *testing.T) {
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

	suffix := time.Now().Format("150405000000")
	hash, _ := security.HashPassword("initial-password-1")
	mk := func(role string) (string, string) {
		u, err := st.CreateUserWithRole(ctx, "promo-"+role+"-"+suffix+"@e2e.test", hash, role)
		if err != nil {
			t.Fatal(err)
		}
		tok, err := srv.issueAccessToken(u.ID, u.Email, u.Role)
		if err != nil {
			t.Fatal(err)
		}
		return tok, u.ID
	}
	admin, _ := mk("admin")
	alice, aliceID := mk("user")
	bob, bobID := mk("user")
	call := func(tok, method, path string, body any) (int, map[string]any) {
		var buf bytes.Buffer
		if body != nil {
			_ = json.NewEncoder(&buf).Encode(body)
		}
		req := httptest.NewRequest(method, path, &buf)
		req.Header.Set("Authorization", "Bearer "+tok)
		req.RemoteAddr = "203.0.113.9:1234"
		rec := httptest.NewRecorder()
		h.ServeHTTP(rec, req)
		out := map[string]any{}
		_ = json.Unmarshal(rec.Body.Bytes(), &out)
		return rec.Code, out
	}

	// A public plan with an offer: 499.00 RUB, was 599.00, "-17%".
	code, d := call(admin, http.MethodPost, "/v1/admin/plans", map[string]any{
		"code": "promo-plus-" + suffix, "name": "Plus", "price_minor": 49900, "currency": "RUB",
		"interval": "month", "device_limit": 3, "original_price_minor": 59900, "badge": "-17%",
	})
	if code != 201 || d["original_price_minor"] != float64(59900) || d["badge"] != "-17%" {
		t.Fatalf("plan with offer: %d %v", code, d)
	}
	planID := d["id"].(string)
	var listed map[string]any
	_, plans := call(alice, http.MethodGet, "/v1/plans", nil)
	for _, p := range plans["plans"].([]any) {
		if p.(map[string]any)["id"] == planID {
			listed = p.(map[string]any)
		}
	}
	if listed == nil || listed["badge"] != "-17%" {
		t.Fatalf("public plan list lacks the offer: %v", listed)
	}

	// Choosing the plan doesn't grant it.
	if code, d := call(alice, http.MethodPost, "/v1/subscriptions", map[string]string{"plan_id": planID}); code != 402 || d["error"] != "PAYMENT_REQUIRED" {
		t.Fatalf("self-serve subscription: %d %v, want 402 PAYMENT_REQUIRED", code, d)
	}

	pct := "SPRING" + suffix[len(suffix)-6:]
	code, d = call(admin, http.MethodPost, "/v1/admin/promo-codes", map[string]any{
		"code": pct, "description": "Весна", "discount_type": "percent", "discount_value": 20,
		"plan_id": planID, "max_activations": 1,
	})
	if code != 201 || d["code"] != pct {
		t.Fatalf("create percent code: %d %v", code, d)
	}
	promoID := d["id"].(string)
	if code, _ := call(admin, http.MethodPost, "/v1/admin/promo-codes", map[string]any{
		"code": pct, "discount_type": "percent", "discount_value": 5,
	}); code != 409 {
		t.Fatalf("duplicate code: %d, want 409", code)
	}
	if code, _ := call(alice, http.MethodGet, "/v1/admin/promo-codes", nil); code != 403 {
		t.Fatalf("user lists promo codes: %d, want 403", code)
	}

	// Check (any case, spaces): 20% off 499.00 = 399.20.
	code, d = call(alice, http.MethodPost, "/v1/promo-codes/check", map[string]string{"code": " " + pct[:3] + " " + pct[3:] + " "})
	if code != 200 {
		t.Fatalf("check: %d %v", code, d)
	}
	prices := d["plans"].([]any)
	if len(prices) != 1 || prices[0].(map[string]any)["discounted_price_minor"] != float64(39920) {
		t.Fatalf("discounted prices: %v", prices)
	}
	if code, d := call(alice, http.MethodPost, "/v1/promo-codes/check", map[string]string{"code": "NOPE" + suffix}); code != 422 || d["error"] != store.PromoNotFound {
		t.Fatalf("unknown code: %d %v", code, d)
	}

	// A purchase redeems it; the limit (1) and once-per-user then hold.
	if err := st.RedeemPromoCode(ctx, promoID, aliceID, planID, nil); err != nil {
		t.Fatalf("redeem: %v", err)
	}
	if code, d := call(alice, http.MethodPost, "/v1/promo-codes/check", map[string]string{"code": pct}); code != 422 || d["error"] != store.PromoExhausted {
		t.Fatalf("after the only activation: %d %v", code, d)
	}
	if err := st.RedeemPromoCode(ctx, promoID, bobID, planID, nil); !errors.Is(err, store.ErrPromoRejected) {
		t.Fatalf("second redeem over the limit: %v", err)
	}

	// Expired and wrong-currency codes.
	past := time.Now().Add(-time.Hour)
	if code, _ := call(admin, http.MethodPost, "/v1/admin/promo-codes", map[string]any{
		"code": "OLD" + suffix[len(suffix)-6:], "discount_type": "percent", "discount_value": 10,
		"valid_from": past.Add(-time.Hour), "valid_until": past,
	}); code != 201 {
		t.Fatal("create expired code")
	}
	if code, d := call(bob, http.MethodPost, "/v1/promo-codes/check", map[string]string{"code": "old" + suffix[len(suffix)-6:]}); code != 422 || d["error"] != store.PromoExpired {
		t.Fatalf("expired: %d %v", code, d)
	}
	usd := "USD" + suffix[len(suffix)-6:]
	if code, _ := call(admin, http.MethodPost, "/v1/admin/promo-codes", map[string]any{
		"code": usd, "discount_type": "fixed", "discount_value": 500, "currency": "USD", "plan_id": planID,
	}); code != 201 {
		t.Fatal("create USD code")
	}
	if code, d := call(bob, http.MethodPost, "/v1/promo-codes/check", map[string]string{"code": usd, "plan_id": planID}); code != 422 || d["error"] != store.PromoWrongCurrency {
		t.Fatalf("USD code on a RUB plan: %d %v", code, d)
	}

	// Admin edits and deletes.
	code, d = call(admin, http.MethodPut, "/v1/admin/promo-codes/"+promoID, map[string]any{
		"code": pct, "discount_type": "percent", "discount_value": 30, "is_active": false,
	})
	if code != 200 || d["is_active"] != false || d["discount_value"] != float64(30) {
		t.Fatalf("update: %d %v", code, d)
	}
	if code, _ := call(admin, http.MethodDelete, "/v1/admin/promo-codes/"+promoID, nil); code != 200 {
		t.Fatalf("delete: %d", code)
	}
	if code, _ := call(admin, http.MethodDelete, "/v1/admin/promo-codes/"+promoID, nil); code != 404 {
		t.Fatalf("delete again: %d, want 404", code)
	}
}

