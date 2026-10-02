package httpapi

import (
	"context"
	"net/http"
	"net/http/httptest"
	"sync"
	"testing"
	"time"
)

// fakeLimiter is an in-memory stand-in for *redisstore.Store's Allow method,
// with a swappable clock so tests can simulate a window elapsing without
// real sleeps.
type fakeLimiter struct {
	mu      sync.Mutex
	counts  map[string]int64
	resetAt map[string]time.Time
	now     func() time.Time
}

func newFakeLimiter() *fakeLimiter {
	return &fakeLimiter{
		counts:  map[string]int64{},
		resetAt: map[string]time.Time{},
		now:     time.Now,
	}
}

func (f *fakeLimiter) Allow(_ context.Context, key string, limit int64, window time.Duration) (bool, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	now := f.now()
	if reset, ok := f.resetAt[key]; !ok || now.After(reset) {
		f.counts[key] = 0
		f.resetAt[key] = now.Add(window)
	}
	f.counts[key]++
	return f.counts[key] <= limit, nil
}

func TestIPRateLimitMiddlewareAllowsUnderLimitAndBlocksOver(t *testing.T) {
	limiter := newFakeLimiter()
	handlerCalls := 0
	final := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		handlerCalls++
		w.WriteHeader(http.StatusOK)
	})
	mw := ipRateLimitMiddleware(limiter, "login", 3, time.Minute)(final)

	newReq := func() *http.Request {
		req := httptest.NewRequest(http.MethodPost, "/v1/auth/login", nil)
		req.RemoteAddr = "203.0.113.5:54321"
		return req
	}

	for i := 1; i <= 3; i++ {
		rec := httptest.NewRecorder()
		mw.ServeHTTP(rec, newReq())
		if rec.Code != http.StatusOK {
			t.Fatalf("request %d: expected 200, got %d", i, rec.Code)
		}
	}
	if handlerCalls != 3 {
		t.Fatalf("expected handler called 3 times, got %d", handlerCalls)
	}

	rec := httptest.NewRecorder()
	mw.ServeHTTP(rec, newReq())
	if rec.Code != http.StatusTooManyRequests {
		t.Fatalf("4th request: expected 429, got %d", rec.Code)
	}
	if handlerCalls != 3 {
		t.Fatalf("blocked request must not reach the handler, got %d calls", handlerCalls)
	}
}

func TestIPRateLimitMiddlewareResetsAfterWindow(t *testing.T) {
	limiter := newFakeLimiter()
	start := time.Now()
	limiter.now = func() time.Time { return start }
	final := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { w.WriteHeader(http.StatusOK) })
	mw := ipRateLimitMiddleware(limiter, "register", 1, time.Minute)(final)

	req := httptest.NewRequest(http.MethodPost, "/v1/auth/register", nil)
	req.RemoteAddr = "198.51.100.9:1111"

	rec := httptest.NewRecorder()
	mw.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("first request should pass, got %d", rec.Code)
	}

	rec = httptest.NewRecorder()
	mw.ServeHTTP(rec, req)
	if rec.Code != http.StatusTooManyRequests {
		t.Fatalf("second request within window should be blocked, got %d", rec.Code)
	}

	// Simulate the window elapsing.
	limiter.now = func() time.Time { return start.Add(2 * time.Minute) }

	rec = httptest.NewRecorder()
	mw.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("request after window reset should pass, got %d", rec.Code)
	}
}

func TestIPRateLimitMiddlewareDistinguishesIPs(t *testing.T) {
	limiter := newFakeLimiter()
	final := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { w.WriteHeader(http.StatusOK) })
	mw := ipRateLimitMiddleware(limiter, "login", 1, time.Minute)(final)

	req1 := httptest.NewRequest(http.MethodPost, "/v1/auth/login", nil)
	req1.RemoteAddr = "10.0.0.1:1"
	req2 := httptest.NewRequest(http.MethodPost, "/v1/auth/login", nil)
	req2.RemoteAddr = "10.0.0.2:1"

	rec1 := httptest.NewRecorder()
	mw.ServeHTTP(rec1, req1)
	rec2 := httptest.NewRecorder()
	mw.ServeHTTP(rec2, req2)
	if rec1.Code != http.StatusOK || rec2.Code != http.StatusOK {
		t.Fatalf("different IPs must not share a bucket: got %d and %d", rec1.Code, rec2.Code)
	}
}

func TestIPRateLimitMiddlewareFailsOpenWithoutLimiter(t *testing.T) {
	final := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { w.WriteHeader(http.StatusOK) })
	mw := ipRateLimitMiddleware(nil, "login", 1, time.Minute)(final)

	req := httptest.NewRequest(http.MethodPost, "/v1/auth/login", nil)
	req.RemoteAddr = "10.0.0.1:1"

	for i := 0; i < 5; i++ {
		rec := httptest.NewRecorder()
		mw.ServeHTTP(rec, req)
		if rec.Code != http.StatusOK {
			t.Fatalf("request %d without a configured limiter should pass, got %d", i, rec.Code)
		}
	}
}

func TestCheckEmailRateLimitAllowsUnderLimitBlocksOverAndResets(t *testing.T) {
	limiter := newFakeLimiter()
	start := time.Now()
	limiter.now = func() time.Time { return start }
	ctx := context.Background()

	for i := 1; i <= 5; i++ {
		if !checkEmailRateLimit(ctx, limiter, "login", "user@example.com", 5, time.Minute) {
			t.Fatalf("attempt %d should be allowed", i)
		}
	}
	if checkEmailRateLimit(ctx, limiter, "login", "user@example.com", 5, time.Minute) {
		t.Fatal("6th attempt within the window should be blocked")
	}

	// A different account must not be affected by the first account's count.
	if !checkEmailRateLimit(ctx, limiter, "login", "other@example.com", 5, time.Minute) {
		t.Fatal("a different account should not share the rate limit bucket")
	}

	limiter.now = func() time.Time { return start.Add(2 * time.Minute) }
	if !checkEmailRateLimit(ctx, limiter, "login", "user@example.com", 5, time.Minute) {
		t.Fatal("attempt after the window elapsed should be allowed again")
	}
}

func TestCheckEmailRateLimitFailsOpenWithoutLimiterOrEmail(t *testing.T) {
	ctx := context.Background()
	if !checkEmailRateLimit(ctx, nil, "login", "user@example.com", 1, time.Minute) {
		t.Fatal("without a configured limiter, the check must allow the request")
	}
	if !checkEmailRateLimit(ctx, newFakeLimiter(), "login", "", 1, time.Minute) {
		t.Fatal("an empty email must not be rate limited")
	}
}
