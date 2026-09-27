package httpapi

import (
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/go-chi/chi/v5/middleware"

	"wavebreak-core/internal/accounts"
	"wavebreak-core/internal/app"
	"wavebreak-core/internal/config"
)

func testServer(t *testing.T) (http.Handler, *Server) {
	t.Helper()
	a := &app.App{Config: config.Config{JWTSecret: "test-secret", AccessTokenTTL: time.Minute}}
	return New(a), &Server{app: a}
}

func tokenFor(t *testing.T, s *Server, role string) string {
	t.Helper()
	tok, err := s.issueAccessToken("11111111-1111-1111-1111-111111111111", role+"@example.test", role)
	if err != nil {
		t.Fatal(err)
	}
	return tok
}

func TestAdminAccountRoutesRBAC(t *testing.T) {
	h, s := testServer(t)
	cases := []struct {
		method, path, role string
		want               int
	}{
		{http.MethodPost, "/v1/admin/users/x/subscriptions", "", http.StatusUnauthorized},
		{http.MethodGet, "/v1/admin/users/x/devices", "", http.StatusUnauthorized},
	}
	for _, c := range cases {
		req := httptest.NewRequest(c.method, c.path, strings.NewReader(`{"plan_id":"p"}`))
		if c.role != "" {
			req.Header.Set("Authorization", "Bearer "+tokenFor(t, s, c.role))
		}
		rec := httptest.NewRecorder()
		h.ServeHTTP(rec, req)
		if rec.Code != c.want {
			t.Fatalf("%s %s as %q: status %d, want %d", c.method, c.path, c.role, rec.Code, c.want)
		}
	}
}

func TestWriteDomainErrorShape(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/", nil)
	var captured *http.Request
	middleware.RequestID(http.HandlerFunc(func(_ http.ResponseWriter, r *http.Request) { captured = r })).ServeHTTP(httptest.NewRecorder(), req)

	rec := httptest.NewRecorder()
	writeDomainError(rec, captured, &accounts.DomainError{Code: accounts.CodeSubscriptionAlreadyActive, Message: "busy", Status: http.StatusConflict})
	if rec.Code != http.StatusConflict {
		t.Fatalf("status %d", rec.Code)
	}
	var body map[string]map[string]string
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatal(err)
	}
	e := body["error"]
	if e["code"] != "SUBSCRIPTION_ALREADY_ACTIVE" || e["message"] != "busy" || e["request_id"] == "" {
		t.Fatalf("error body = %v", body)
	}

	rec = httptest.NewRecorder()
	writeDomainError(rec, captured, errors.New("db down"))
	if rec.Code != http.StatusInternalServerError || !strings.Contains(rec.Body.String(), `"INTERNAL_ERROR"`) || strings.Contains(rec.Body.String(), "db down") {
		t.Fatalf("internal errors must not leak causes: %d %s", rec.Code, rec.Body.String())
	}
}
