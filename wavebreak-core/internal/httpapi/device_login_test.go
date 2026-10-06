package httpapi

import (
	"encoding/json"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"wavebreak-core/internal/app"
	"wavebreak-core/internal/config"
)

func TestDeviceLoginFlow(t *testing.T) {
	st := newDeviceLoginStore()
	l, err := st.start("Living room TV", "android-tv")
	if err != nil {
		t.Fatal(err)
	}
	if len(l.code) != 8 || len(l.pollToken) != 64 {
		t.Fatalf("code %q token %d", l.code, len(l.pollToken))
	}
	if s, _ := st.poll(l.pollToken); s != deviceLoginPending {
		t.Fatalf("before approval: %v", s)
	}
	if st.pending(strings.ToLower(l.code[:4])+"-"+strings.ToLower(l.code[4:])) == nil {
		t.Fatal("code typed as abcd-efgh must be found")
	}
	if st.approve("WRONGCOD", "u1", tokenPair{}) {
		t.Fatal("unknown code approved")
	}
	if !st.approve(l.code, "u1", tokenPair{AccessToken: "a", RefreshToken: "r"}) {
		t.Fatal("approve failed")
	}
	if st.approve(l.code, "u2", tokenPair{}) {
		t.Fatal("a code is approved once")
	}
	if st.pending(l.code) != nil {
		t.Fatal("approved code still pending")
	}
	s, tokens := st.poll(l.pollToken)
	if s != deviceLoginApproved || tokens == nil || tokens.RefreshToken != "r" {
		t.Fatalf("after approval: %v %+v", s, tokens)
	}
	if s, _ := st.poll(l.pollToken); s != deviceLoginGone {
		t.Fatalf("the session is handed over once: %v", s)
	}
}

func TestDeviceLoginExpires(t *testing.T) {
	st := newDeviceLoginStore()
	now := time.Now()
	st.now = func() time.Time { return now }
	l, _ := st.start("TV", "")
	now = now.Add(deviceLoginTTL + time.Second)
	if st.pending(l.code) != nil {
		t.Fatal("expired code still pending")
	}
	if st.approve(l.code, "u", tokenPair{}) {
		t.Fatal("expired code approved")
	}
	if s, _ := st.poll(l.pollToken); s != deviceLoginGone {
		t.Fatalf("expired: %v", s)
	}
}

func TestDeviceLoginStartAndPollHandlers(t *testing.T) {
	s := &Server{app: &app.App{Config: config.Config{}}, deviceLogins: newDeviceLoginStore()}
	rec := httptest.NewRecorder()
	s.startDeviceLogin(rec, httptest.NewRequest("POST", "/v1/auth/device-login/start",
		strings.NewReader(`{"device_name":"Sony Bravia","platform":"android-tv"}`)))
	if rec.Code != 200 {
		t.Fatalf("start %d %s", rec.Code, rec.Body)
	}
	var out struct {
		Code      string `json:"code"`
		PollToken string `json:"poll_token"`
		URL       string `json:"url"`
	}
	_ = json.Unmarshal(rec.Body.Bytes(), &out)
	if !strings.HasSuffix(out.URL, "/v1/device-login/"+out.Code) || !strings.HasPrefix(out.URL, "https://") {
		t.Fatalf("url %q", out.URL)
	}
	rec = httptest.NewRecorder()
	s.pollDeviceLogin(rec, httptest.NewRequest("POST", "/v1/auth/device-login/poll",
		strings.NewReader(`{"poll_token":"`+out.PollToken+`"}`)))
	if rec.Code != 200 || !strings.Contains(rec.Body.String(), `"pending"`) {
		t.Fatalf("poll %d %s", rec.Code, rec.Body)
	}
	rec = httptest.NewRecorder()
	s.pollDeviceLogin(rec, httptest.NewRequest("POST", "/v1/auth/device-login/poll",
		strings.NewReader(`{"poll_token":"nope"}`)))
	if rec.Code != 410 {
		t.Fatalf("unknown token: %d", rec.Code)
	}
}
