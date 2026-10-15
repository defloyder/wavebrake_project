package httpapi

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"wavebreak-core/internal/app"
	"wavebreak-core/internal/config"
	"wavebreak-core/internal/store"
)

func TestBuildPromo(t *testing.T) {
	yes := true
	zero := 0
	from := time.Date(2026, 10, 1, 0, 0, 0, 0, time.UTC)
	until := from.Add(-time.Hour)

	p, problem := buildPromo(" spring 20 ", " Весна ", "Percent", 20, "", "", nil, nil, nil, nil)
	if problem != "" {
		t.Fatalf("valid percent code: %q", problem)
	}
	if p.Code != "SPRING20" || p.Description != "Весна" || p.DiscountType != "percent" || !p.IsActive || p.Currency != nil || p.PlanID != nil {
		t.Errorf("normalized: %+v", p)
	}

	p, problem = buildPromo("wb100", "", "fixed", 10000, "rub", "plan-1", nil, nil, nil, &yes)
	if problem != "" || p.Currency == nil || *p.Currency != "RUB" || p.PlanID == nil || *p.PlanID != "plan-1" {
		t.Errorf("fixed code: %+v, %q", p, problem)
	}

	for name, args := range map[string]func() string{
		"short code": func() string { _, w := buildPromo("ab", "", "percent", 5, "", "", nil, nil, nil, nil); return w },
		"cyrillic code": func() string {
			_, w := buildPromo("ВЕСНА", "", "percent", 5, "", "", nil, nil, nil, nil)
			return w
		},
		"percent over 100":  func() string { _, w := buildPromo("BIG", "", "percent", 101, "", "", nil, nil, nil, nil); return w },
		"fixed no currency": func() string { _, w := buildPromo("FIX", "", "fixed", 100, "", "", nil, nil, nil, nil); return w },
		"unknown type":      func() string { _, w := buildPromo("ODD", "", "bonus", 1, "", "", nil, nil, nil, nil); return w },
		"window backwards":  func() string { _, w := buildPromo("WIN", "", "percent", 5, "", "", &from, &until, nil, nil); return w },
		"zero activations":  func() string { _, w := buildPromo("LIM", "", "percent", 5, "", "", nil, nil, &zero, nil); return w },
	} {
		if args() == "" {
			t.Errorf("%s: accepted", name)
		}
	}
}

// Choosing a plan in an app doesn't grant it while there's no payment
// step: POST /v1/subscriptions answers 402 unless self-serve is on.
func TestSelfServeSubscriptionsOffByDefault(t *testing.T) {
	s := &Server{app: &app.App{Config: config.Config{}, Store: &store.Store{}}}
	req := httptest.NewRequest(http.MethodPost, "/v1/subscriptions", strings.NewReader(`{"plan_id":"p"}`))
	rec := httptest.NewRecorder()
	s.createSubscription(rec, req)
	if rec.Code != http.StatusPaymentRequired || !strings.Contains(rec.Body.String(), "PAYMENT_REQUIRED") {
		t.Fatalf("got %d %s, want 402 PAYMENT_REQUIRED", rec.Code, rec.Body.String())
	}
}
