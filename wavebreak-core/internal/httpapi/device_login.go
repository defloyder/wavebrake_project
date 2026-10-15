package httpapi

import (
	"crypto/rand"
	"crypto/subtle"
	"encoding/hex"
	"net/http"
	"strings"
	"sync"
	"time"

	"github.com/go-chi/chi/v5"
)

// Sign-in on a TV (or any device without a comfortable keyboard) by QR:
//
//  1. The TV calls POST /v1/auth/device-login/start and shows the returned
//     code as a QR (https://<core>/v1/device-login/<code>) and as text.
//  2. The owner scans it with WAVEBREAK on a phone (or PC) where they are
//     signed in: GET /v1/me/device-login/{code} shows which device asks,
//     POST /v1/me/device-login/{code}/approve signs it in.
//  3. The TV polls POST /v1/auth/device-login/poll with its secret poll
//     token and gets its own session once approved.
//
// The TV gets a session of its own (issueTokens: a new sessions row) —
// the approving phone or PC keeps its session; nothing is signed out
// (owner, 06.10). Pending logins live in this process's memory for 10
// minutes: the pilot runs one API instance (with several, move them to
// Redis).

const (
	deviceLoginTTL      = 10 * time.Minute
	deviceLoginInterval = 3 // seconds between polls the client should keep
	deviceLoginAlphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
)

type deviceLogin struct {
	code       string
	pollToken  string
	deviceName string
	platform   string
	expiresAt  time.Time
	approvedBy string
	tokens     *tokenPair
	delivered  bool
}

type deviceLoginStore struct {
	mu     sync.Mutex
	byCode map[string]*deviceLogin
	now    func() time.Time
}

func newDeviceLoginStore() *deviceLoginStore {
	return &deviceLoginStore{byCode: map[string]*deviceLogin{}, now: time.Now}
}

func (st *deviceLoginStore) sweepLocked() {
	now := st.now()
	for code, l := range st.byCode {
		if now.After(l.expiresAt) || l.delivered {
			delete(st.byCode, code)
		}
	}
}

func (st *deviceLoginStore) start(deviceName, platform string) (*deviceLogin, error) {
	poll := make([]byte, 32)
	if _, err := rand.Read(poll); err != nil {
		return nil, err
	}
	st.mu.Lock()
	defer st.mu.Unlock()
	st.sweepLocked()
	if len(st.byCode) > 10000 {
		return nil, errTooManyPending
	}
	for {
		code, err := randomDeviceCode()
		if err != nil {
			return nil, err
		}
		if _, taken := st.byCode[code]; taken {
			continue
		}
		l := &deviceLogin{
			code:       code,
			pollToken:  hex.EncodeToString(poll),
			deviceName: deviceName,
			platform:   platform,
			expiresAt:  st.now().Add(deviceLoginTTL),
		}
		st.byCode[code] = l
		snapshot := *l
		return &snapshot, nil
	}
}

// pending returns the login waiting for [code], or nil.
func (st *deviceLoginStore) pending(code string) *deviceLogin {
	st.mu.Lock()
	defer st.mu.Unlock()
	st.sweepLocked()
	l := st.byCode[normalizeDeviceCode(code)]
	if l == nil || l.approvedBy != "" {
		return nil
	}
	snapshot := *l
	return &snapshot
}

// approve stores the session for the device; false when the code is
// unknown, expired or already used.
func (st *deviceLoginStore) approve(code, userID string, tokens tokenPair) bool {
	st.mu.Lock()
	defer st.mu.Unlock()
	st.sweepLocked()
	l := st.byCode[normalizeDeviceCode(code)]
	if l == nil || l.approvedBy != "" {
		return false
	}
	l.approvedBy = userID
	l.tokens = &tokens
	return true
}

type deviceLoginPoll int

const (
	deviceLoginPending deviceLoginPoll = iota
	deviceLoginApproved
	deviceLoginGone
)

// poll hands the session over once (then the login is gone).
func (st *deviceLoginStore) poll(pollToken string) (deviceLoginPoll, *tokenPair) {
	st.mu.Lock()
	defer st.mu.Unlock()
	st.sweepLocked()
	for _, l := range st.byCode {
		if subtle.ConstantTimeCompare([]byte(l.pollToken), []byte(pollToken)) != 1 {
			continue
		}
		if l.tokens == nil {
			return deviceLoginPending, nil
		}
		l.delivered = true
		return deviceLoginApproved, l.tokens
	}
	return deviceLoginGone, nil
}

type deviceLoginError string

func (e deviceLoginError) Error() string { return string(e) }

const errTooManyPending = deviceLoginError("too many pending device logins")

func randomDeviceCode() (string, error) {
	b := make([]byte, 8)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	out := make([]byte, 8)
	for i, v := range b {
		out[i] = deviceLoginAlphabet[int(v)%len(deviceLoginAlphabet)]
	}
	return string(out), nil
}

// normalizeDeviceCode: "abcd-efgh " → "ABCDEFGH".
func normalizeDeviceCode(code string) string {
	code = strings.ToUpper(strings.TrimSpace(code))
	return strings.NewReplacer("-", "", " ", "").Replace(code)
}

func (s *Server) deviceLoginURL(code string) string {
	base := strings.TrimSuffix(s.app.Config.Accounts.SubscriptionURLBase, "/")
	base = strings.TrimSuffix(base, "/v1/sub")
	if base == "" {
		base = "https://core.wavebreak.com.tr"
	}
	return base + "/v1/device-login/" + code
}

// POST /v1/auth/device-login/start {device_name, platform}
func (s *Server) startDeviceLogin(w http.ResponseWriter, r *http.Request) {
	var req struct {
		DeviceName string `json:"device_name"`
		Platform   string `json:"platform"`
	}
	if !decodeJSON(w, r, &req) {
		return
	}
	name := strings.TrimSpace(req.DeviceName)
	if name == "" {
		name = "TV"
	}
	if len(name) > 80 {
		name = name[:80]
	}
	platform := strings.ToLower(strings.TrimSpace(req.Platform))
	if len(platform) > 32 {
		platform = platform[:32]
	}
	l, err := s.deviceLogins.start(name, platform)
	if err != nil {
		writeError(w, http.StatusServiceUnavailable, "device login unavailable, try again later")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"code":       l.code,
		"poll_token": l.pollToken,
		"url":        s.deviceLoginURL(l.code),
		"expires_in": int(deviceLoginTTL.Seconds()),
		"interval":   deviceLoginInterval,
	})
}

// POST /v1/auth/device-login/poll {poll_token}
func (s *Server) pollDeviceLogin(w http.ResponseWriter, r *http.Request) {
	var req struct {
		PollToken string `json:"poll_token"`
	}
	if !decodeJSON(w, r, &req) {
		return
	}
	status, tokens := s.deviceLogins.poll(strings.TrimSpace(req.PollToken))
	switch status {
	case deviceLoginPending:
		writeJSON(w, http.StatusOK, map[string]string{"status": "pending"})
	case deviceLoginApproved:
		writeJSON(w, http.StatusOK, map[string]any{"status": "approved", "tokens": tokens})
	default:
		writeJSON(w, http.StatusGone, map[string]string{"code": "device_login_expired", "error": "the code expired, start again"})
	}
}

// GET /v1/me/device-login/{code}: which device asks to be signed in.
func (s *Server) inspectDeviceLogin(w http.ResponseWriter, r *http.Request) {
	l := s.deviceLogins.pending(chi.URLParam(r, "code"))
	if l == nil {
		writeJSON(w, http.StatusNotFound, map[string]string{"code": "device_login_not_found", "error": "the code is unknown or expired"})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"device_name": l.deviceName,
		"platform":    l.platform,
		"expires_in":  int(time.Until(l.expiresAt).Seconds()),
	})
}

// POST /v1/me/device-login/{code}/approve: signs the device in to the
// caller's account with a session of its own.
func (s *Server) approveDeviceLogin(w http.ResponseWriter, r *http.Request) {
	code := chi.URLParam(r, "code")
	if s.deviceLogins.pending(code) == nil {
		writeJSON(w, http.StatusNotFound, map[string]string{"code": "device_login_not_found", "error": "the code is unknown or expired"})
		return
	}
	user := currentUser(r.Context())
	tokens, err := s.issueTokens(r.Context(), user.ID, user.Email, user.Role)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "could not sign the device in")
		return
	}
	if !s.deviceLogins.approve(code, user.ID, tokens) {
		writeJSON(w, http.StatusNotFound, map[string]string{"code": "device_login_not_found", "error": "the code is unknown or expired"})
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

// GET /v1/device-login/{code}: the QR opened in a browser instead of the
// app.
func (s *Server) deviceLoginLanding(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "text/plain; charset=utf-8")
	_, _ = w.Write([]byte("Отсканируйте этот код в приложении WAVEBREAK: Настройки → Аккаунт → «Войти на другом устройстве».\n" +
		"Scan this code in the WAVEBREAK app: Settings → Account → \"Sign in on another device\".\n"))
}
