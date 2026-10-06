package main

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func testApp() *App {
	return &App{token: "secret-token", state: &stateStore{}, core: &Core{state: &stateStore{}}, tunnel: &Tunnel{state: stIdle}, quit: make(chan struct{})}
}

func TestControlPageNeedsTokenAndOurHost(t *testing.T) {
	h := testApp().routes()
	cases := []struct {
		name, method, url, host, token string
		want                           int
	}{
		{"page without token", "GET", "/", "127.0.0.1:" + uiPort, "", 403},
		{"page with token", "GET", "/?t=secret-token", "127.0.0.1:" + uiPort, "", 200},
		{"page, foreign host (DNS rebinding)", "GET", "/?t=secret-token", "evil.example:" + uiPort, "", 404},
		{"api without header", "POST", "/api/state", "127.0.0.1:" + uiPort, "", 403},
		{"api wrong header", "POST", "/api/state", "127.0.0.1:" + uiPort, "nope", 403},
		{"api GET refused", "GET", "/api/state", "127.0.0.1:" + uiPort, "secret-token", 403},
		{"api foreign host", "POST", "/api/state", "evil.example", "secret-token", 403},
		{"api ok", "POST", "/api/state", "127.0.0.1:" + uiPort, "secret-token", 200},
	}
	for _, c := range cases {
		req := httptest.NewRequest(c.method, c.url, strings.NewReader("{}"))
		req.Host = c.host
		if c.token != "" {
			req.Header.Set("X-Lite-Token", c.token)
		}
		rec := httptest.NewRecorder()
		h.ServeHTTP(rec, req)
		if rec.Code != c.want {
			t.Errorf("%s: got %d, want %d", c.name, rec.Code, c.want)
		}
		if rec.Header().Get("Access-Control-Allow-Origin") != "" {
			t.Errorf("%s: must not send CORS headers", c.name)
		}
	}
}

func TestPingIsOpen(t *testing.T) {
	rec := httptest.NewRecorder()
	testApp().routes().ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/ping", nil))
	if rec.Body.String() != "wavebreak-lite" {
		t.Fatalf("ping: %q", rec.Body.String())
	}
}
