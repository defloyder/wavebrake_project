package store

import (
	"testing"
	"time"
)

func TestNormalizePromoCode(t *testing.T) {
	for in, want := range map[string]string{
		"spring20":    "SPRING20",
		" Spring 20 ": "SPRING20",
		"wb-2026_x":   "WB-2026_X",
	} {
		if got := NormalizePromoCode(in); got != want {
			t.Errorf("NormalizePromoCode(%q) = %q, want %q", in, got, want)
		}
	}
}

func TestPromoUsable(t *testing.T) {
	now := time.Date(2026, 10, 6, 12, 0, 0, 0, time.UTC)
	past, future := now.Add(-time.Hour), now.Add(time.Hour)
	two := 2
	base := PromoCode{IsActive: true, DiscountType: "percent", DiscountValue: 20}
	cases := []struct {
		name string
		p    PromoCode
		used bool
		want string
	}{
		{"ok", base, false, ""},
		{"inactive", PromoCode{IsActive: false}, false, PromoInactive},
		{"not started", func() PromoCode { p := base; p.ValidFrom = &future; return p }(), false, PromoNotStarted},
		{"expired", func() PromoCode { p := base; p.ValidUntil = &past; return p }(), false, PromoExpired},
		{"ends exactly now", func() PromoCode { p := base; p.ValidUntil = &now; return p }(), false, PromoExpired},
		{"within window", func() PromoCode { p := base; p.ValidFrom = &past; p.ValidUntil = &future; return p }(), false, ""},
		{"exhausted", func() PromoCode { p := base; p.MaxActivations = &two; p.ActivationsCount = 2; return p }(), false, PromoExhausted},
		{"one left", func() PromoCode { p := base; p.MaxActivations = &two; p.ActivationsCount = 1; return p }(), false, ""},
		{"used by this user", base, true, PromoAlreadyUsed},
	}
	for _, c := range cases {
		if got := c.p.Usable(now, c.used); got != c.want {
			t.Errorf("%s: Usable = %q, want %q", c.name, got, c.want)
		}
	}
}

func TestPromoAppliesToAndPrice(t *testing.T) {
	plus := Plan{ID: "plus", PriceMinor: 49900, Currency: "RUB"}
	other := Plan{ID: "other", PriceMinor: 999, Currency: "USD"}
	rub := "RUB"
	plusID := "plus"

	percent := PromoCode{DiscountType: "percent", DiscountValue: 15}
	if why := percent.AppliesTo(other); why != "" {
		t.Fatalf("percent code for any plan: %q", why)
	}
	if got := percent.DiscountedPrice(plus); got != 42415 {
		t.Errorf("15%% off 499.00 = %d, want 42415", got)
	}
	if got := percent.DiscountedPrice(Plan{PriceMinor: 333}); got != 283 {
		// 333 * 15% = 49.95 -> 50 off.
		t.Errorf("rounding: got %d, want 283", got)
	}
	if got := (PromoCode{DiscountType: "percent", DiscountValue: 100}).DiscountedPrice(plus); got != 0 {
		t.Errorf("100%% off = %d, want 0", got)
	}

	fixed := PromoCode{DiscountType: "fixed", DiscountValue: 10000, Currency: &rub, PlanID: &plusID}
	if why := fixed.AppliesTo(plus); why != "" {
		t.Fatalf("fixed code for its plan: %q", why)
	}
	if why := fixed.AppliesTo(other); why != PromoNotForPlan {
		t.Errorf("fixed code for another plan: %q, want %q", why, PromoNotForPlan)
	}
	if got := fixed.DiscountedPrice(plus); got != 39900 {
		t.Errorf("100.00 off 499.00 = %d, want 39900", got)
	}
	big := PromoCode{DiscountType: "fixed", DiscountValue: 99999, Currency: &rub}
	if got := big.DiscountedPrice(plus); got != 0 {
		t.Errorf("discount above the price = %d, want 0", got)
	}
	if why := big.AppliesTo(other); why != PromoWrongCurrency {
		t.Errorf("RUB code on a USD plan: %q, want %q", why, PromoWrongCurrency)
	}
}
