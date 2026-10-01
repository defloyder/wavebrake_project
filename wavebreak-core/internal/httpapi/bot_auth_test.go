package httpapi

import (
	"net/http"
	"net/http/httptest"
	"testing"

	"wavebreak-core/internal/app"
	"wavebreak-core/internal/config"
)

func newTestServerWithBotToken(token string) *Server {
	return &Server{app: &app.App{Config: config.Config{BotServiceToken: token}}}
}

func TestBotAuthRequiredAcceptsCorrectToken(t *testing.T) {
	s := newTestServerWithBotToken("correct-horse-battery-staple")
	called := false
	handler := s.botAuthRequired(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		called = true
		w.WriteHeader(http.StatusOK)
	}))

	req := httptest.NewRequest(http.MethodGet, "/v1/bot/users/123/overview", nil)
	req.Header.Set("Authorization", "Bearer correct-horse-battery-staple")
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 for the correct token, got %d", rec.Code)
	}
	if !called {
		t.Fatal("expected the wrapped handler to run for the correct token")
	}
}

func TestBotAuthRequiredRejectsWrongToken(t *testing.T) {
	s := newTestServerWithBotToken("correct-horse-battery-staple")
	called := false
	handler := s.botAuthRequired(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		called = true
	}))

	req := httptest.NewRequest(http.MethodGet, "/v1/bot/users/123/overview", nil)
	req.Header.Set("Authorization", "Bearer wrong-token-wrong-token")
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)

	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401 for a wrong token, got %d", rec.Code)
	}
	if called {
		t.Fatal("wrapped handler must not run for a wrong token")
	}
}

func TestBotAuthRequiredRejectsTokenThatDiffersOnlyInLength(t *testing.T) {
	s := newTestServerWithBotToken("correct-horse-battery-staple")
	req := httptest.NewRequest(http.MethodGet, "/v1/bot/users/123/overview", nil)
	req.Header.Set("Authorization", "Bearer correct-horse-battery-staple-extra")
	rec := httptest.NewRecorder()
	s.botAuthRequired(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {})).ServeHTTP(rec, req)
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", rec.Code)
	}
}

func TestBotAuthRequiredRejectsMissingHeader(t *testing.T) {
	s := newTestServerWithBotToken("correct-horse-battery-staple")
	req := httptest.NewRequest(http.MethodGet, "/v1/bot/users/123/overview", nil)
	rec := httptest.NewRecorder()
	s.botAuthRequired(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {})).ServeHTTP(rec, req)
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401 for a missing Authorization header, got %d", rec.Code)
	}
}

func TestBotAuthRequiredRejectsWhenConfigTokenEmpty(t *testing.T) {
	s := newTestServerWithBotToken("")
	req := httptest.NewRequest(http.MethodGet, "/v1/bot/users/123/overview", nil)
	req.Header.Set("Authorization", "Bearer anything")
	rec := httptest.NewRecorder()
	s.botAuthRequired(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {})).ServeHTTP(rec, req)
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401 when no bot service token is configured, got %d", rec.Code)
	}
}

func TestConstantTimeEqual(t *testing.T) {
	cases := []struct {
		a, b string
		want bool
	}{
		{"abc", "abc", true},
		{"abc", "abd", false},
		{"abc", "ab", false},
		{"", "", true},
	}
	for _, c := range cases {
		if got := constantTimeEqual(c.a, c.b); got != c.want {
			t.Fatalf("constantTimeEqual(%q, %q) = %v, want %v", c.a, c.b, got, c.want)
		}
	}
}
