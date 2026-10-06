package httpapi

import (
	"encoding/base64"
	"net/http/httptest"
	"strings"
	"testing"

	"wavebreak-core/internal/app"
	"wavebreak-core/internal/config"
)

func TestSubscriptionWithoutDeviceIDGetsANotice(t *testing.T) {
	s := &Server{app: &app.App{Config: config.Config{Accounts: config.AccountsConfig{SubRequireHWID: true}}}}
	r := httptest.NewRequest("GET", "/v1/sub/x", nil)
	r.Header.Set("User-Agent", "v2rayNG/1.9.0")
	if got := s.subscriptionDeviceGate(r, "user"); got != subNoDeviceID {
		t.Fatalf("gate = %v, want subNoDeviceID", got)
	}
	s.app.Config.Accounts.SubRequireHWID = false
	if got := s.subscriptionDeviceGate(r, "user"); got != subAllowed {
		t.Fatalf("with the requirement off: gate = %v, want subAllowed", got)
	}
}

func TestSubscriptionNoticeIsAnUnusableServerList(t *testing.T) {
	rec := httptest.NewRecorder()
	writeSubscriptionNotice(rec, subNoticeLimitTitle, subNoticeLimitHint)
	if rec.Code != 200 {
		t.Fatalf("status %d", rec.Code)
	}
	body, err := base64.StdEncoding.DecodeString(rec.Body.String())
	if err != nil {
		t.Fatal(err)
	}
	lines := strings.Split(string(body), "\n")
	if len(lines) != 2 {
		t.Fatalf("lines %q", lines)
	}
	for _, l := range lines {
		if !strings.Contains(l, "@0.0.0.0:1?") {
			t.Fatalf("placeholder must point nowhere: %q", l)
		}
	}
	if !strings.Contains(lines[0], "%D0%9F%D1%80%D0%B5%D0%B2%D1%8B%D1%88%D0%B5%D0%BD") { // "Превышен"
		t.Fatalf("title not in the entry name: %q", lines[0])
	}
	if !strings.HasPrefix(rec.Header().Get("Announce"), "base64:") {
		t.Fatal("announce banner missing")
	}
}

func TestSubscriptionDeviceName(t *testing.T) {
	r := httptest.NewRequest("GET", "/", nil)
	r.Header.Set("User-Agent", "Happ/1.6.2/Android")
	r.Header.Set("X-Device-Model", "Pixel 8")
	if got := subDeviceName(r); got != "Pixel 8 · Happ" {
		t.Fatalf("name %q", got)
	}
}
