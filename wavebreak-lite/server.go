package main

import (
	"crypto/sha256"
	"crypto/subtle"
	_ "embed"
	"encoding/hex"
	"encoding/json"
	"errors"
	"net/http"
	"os"
	"sort"
	"strings"
	"sync"
	"time"
)

//go:embed ui.html
var uiHTML []byte

const uiPort = "47613"

// App is the local control page's backend. The page is served on
// 127.0.0.1 only; every API call must carry the per-run token (from the
// page's URL) in a header, and the Host header must be ours — so no web
// page the user visits can drive it (no CORS headers, custom header →
// preflight that never succeeds; DNS rebinding fails the Host check).
type App struct {
	token  string
	core   *Core
	state  *stateStore
	tunnel *Tunnel
	quit   chan struct{}

	mu      sync.Mutex
	servers []server
	loadErr string
	pending string // e-mail waiting for its verification code
	busy    bool
}

type server struct {
	ID       string `json:"id"`
	Country  string `json:"country"`
	Place    string `json:"place"`
	Protocol string `json:"protocol"`
	link     *ShareLink
}

func (a *App) routes() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("/ping", func(w http.ResponseWriter, r *http.Request) {
		_, _ = w.Write([]byte("wavebreak-lite"))
	})
	mux.HandleFunc("/", a.page)
	mux.HandleFunc("/api/state", a.api(a.handleState))
	mux.HandleFunc("/api/login", a.api(a.handleLogin))
	mux.HandleFunc("/api/verify", a.api(a.handleVerify))
	mux.HandleFunc("/api/resend", a.api(a.handleResend))
	mux.HandleFunc("/api/logout", a.api(a.handleLogout))
	mux.HandleFunc("/api/reload", a.api(a.handleReload))
	mux.HandleFunc("/api/select", a.api(a.handleSelect))
	mux.HandleFunc("/api/connect", a.api(a.handleConnect))
	mux.HandleFunc("/api/disconnect", a.api(a.handleDisconnect))
	mux.HandleFunc("/api/quit", a.api(a.handleQuit))
	return mux
}

func (a *App) hostOK(r *http.Request) bool {
	return r.Host == "127.0.0.1:"+uiPort || r.Host == "localhost:"+uiPort
}

func (a *App) page(w http.ResponseWriter, r *http.Request) {
	if !a.hostOK(r) || r.URL.Path != "/" {
		http.NotFound(w, r)
		return
	}
	if subtle.ConstantTimeCompare([]byte(r.URL.Query().Get("t")), []byte(a.token)) != 1 {
		http.Error(w, "Откройте WAVEBREAK Lite ярлыком.", http.StatusForbidden)
		return
	}
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.Header().Set("Cache-Control", "no-store")
	w.Header().Set("X-Frame-Options", "DENY")
	w.Header().Set("Content-Security-Policy", "default-src 'self'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; frame-ancestors 'none'")
	_, _ = w.Write(uiHTML)
}

func (a *App) api(h func(map[string]string) (any, error)) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if !a.hostOK(r) || r.Method != http.MethodPost ||
			subtle.ConstantTimeCompare([]byte(r.Header.Get("X-Lite-Token")), []byte(a.token)) != 1 {
			http.Error(w, "forbidden", http.StatusForbidden)
			return
		}
		body := map[string]string{}
		_ = json.NewDecoder(http.MaxBytesReader(w, r.Body, 64<<10)).Decode(&body)
		out, err := h(body)
		w.Header().Set("Content-Type", "application/json")
		w.Header().Set("Cache-Control", "no-store")
		if err != nil {
			w.WriteHeader(http.StatusBadRequest)
			_ = json.NewEncoder(w).Encode(map[string]string{"error": userMessage(err)})
			return
		}
		if out == nil {
			out = map[string]bool{"ok": true}
		}
		_ = json.NewEncoder(w).Encode(out)
	}
}

func userMessage(err error) string {
	switch {
	case errors.Is(err, errBadCredentials):
		return "Неверный email или пароль."
	case errors.Is(err, errSignedOut):
		return "Сессия закончилась — войдите снова."
	case errors.Is(err, errNoSubscription):
		return "Нет активной подписки. Обратитесь в поддержку WAVEBREAK."
	}
	var ae *apiError
	if errors.As(err, &ae) {
		switch ae.Code {
		case "invalid_code":
			return "Неверный код."
		case "code_expired":
			return "Код устарел — отправьте новый."
		case "too_many_attempts", "resend_too_soon":
			return "Слишком часто. Подождите минуту."
		}
		if ae.Status == 429 {
			return "Слишком много попыток. Подождите немного."
		}
		if ae.Status >= 500 {
			return "Сервер WAVEBREAK временно недоступен."
		}
		return "Ошибка: " + ae.Msg
	}
	if strings.Contains(err.Error(), "dial") || strings.Contains(err.Error(), "timeout") {
		return "Нет связи с сервером WAVEBREAK. Проверьте интернет."
	}
	return err.Error()
}

func (a *App) handleState(map[string]string) (any, error) {
	a.mu.Lock()
	defer a.mu.Unlock()
	st := a.state.get()
	return map[string]any{
		"version":   version,
		"signed_in": a.core.SignedIn(),
		"email":     st.Email,
		"pending":   a.pending,
		"servers":   a.servers,
		"selected":  st.Selected,
		"load_err":  a.loadErr,
		"busy":      a.busy,
		"tunnel":    a.tunnel.Status(),
	}, nil
}

func (a *App) handleLogin(b map[string]string) (any, error) {
	email := strings.ToLower(strings.TrimSpace(b["email"]))
	err := a.core.Login(email, b["password"])
	if errors.Is(err, errNotVerified) {
		a.mu.Lock()
		a.pending = email
		a.mu.Unlock()
		_ = a.core.ResendCode(email)
		return map[string]any{"verify": true}, nil
	}
	if err != nil {
		return nil, err
	}
	a.afterSignIn()
	return nil, nil
}

func (a *App) handleVerify(b map[string]string) (any, error) {
	a.mu.Lock()
	email := a.pending
	a.mu.Unlock()
	if err := a.core.VerifyEmail(email, strings.TrimSpace(b["code"])); err != nil {
		return nil, err
	}
	a.mu.Lock()
	a.pending = ""
	a.mu.Unlock()
	a.afterSignIn()
	return nil, nil
}

func (a *App) handleResend(map[string]string) (any, error) {
	a.mu.Lock()
	email := a.pending
	a.mu.Unlock()
	return nil, a.core.ResendCode(email)
}

func (a *App) afterSignIn() {
	go func() {
		a.core.RegisterDevice()
		a.loadServers()
	}()
}

func (a *App) handleLogout(map[string]string) (any, error) {
	a.tunnel.Stop()
	a.core.Logout()
	a.mu.Lock()
	a.servers, a.loadErr, a.pending = nil, "", ""
	a.mu.Unlock()
	return nil, nil
}

func (a *App) handleReload(map[string]string) (any, error) {
	a.loadServers()
	return nil, nil
}

// loadServers asks Core for the account's links and keeps the ones this
// build can run.
func (a *App) loadServers() {
	a.mu.Lock()
	a.busy = true
	a.mu.Unlock()
	links, err := a.core.Access()
	var list []server
	for _, raw := range links {
		l, perr := ParseShareLink(raw)
		if perr != nil {
			continue
		}
		country, place := l.Place()
		sum := sha256.Sum256([]byte(raw))
		list = append(list, server{ID: hex.EncodeToString(sum[:6]), Country: country, Place: place, Protocol: l.ProtocolName(), link: l})
	}
	sort.SliceStable(list, func(i, j int) bool { return list[i].Place < list[j].Place })
	a.mu.Lock()
	defer a.mu.Unlock()
	a.busy = false
	if err != nil {
		a.loadErr = userMessage(err)
		if errors.Is(err, errSignedOut) {
			a.servers = nil
		}
		return
	}
	a.loadErr = ""
	a.servers = list
	if len(list) == 0 {
		a.loadErr = "Для этой подписки нет серверов, которые поддерживает WAVEBREAK Lite."
	}
}

func (a *App) find(id string) *server {
	for i := range a.servers {
		if a.servers[i].ID == id {
			return &a.servers[i]
		}
	}
	return nil
}

func (a *App) handleSelect(b map[string]string) (any, error) {
	a.mu.Lock()
	s := a.find(b["id"])
	a.mu.Unlock()
	if s == nil {
		return nil, errors.New("сервер не найден — обновите список")
	}
	a.state.update(func(st *State) { st.Selected = s.ID })
	if st := a.tunnel.Status().State; st == stConnected || st == stConnecting {
		go func() { _ = a.tunnel.Connect(s.link) }()
	}
	return nil, nil
}

func (a *App) handleConnect(map[string]string) (any, error) {
	a.mu.Lock()
	if len(a.servers) == 0 {
		a.mu.Unlock()
		return nil, errors.New("список серверов пуст — нажмите «Обновить»")
	}
	s := a.find(a.state.get().Selected)
	if s == nil {
		s = &a.servers[0]
	}
	link := s.link
	id := s.ID
	a.mu.Unlock()
	a.state.update(func(st *State) { st.Selected = id })
	go func() { _ = a.tunnel.Connect(link) }()
	return nil, nil
}

func (a *App) handleDisconnect(map[string]string) (any, error) {
	a.tunnel.Stop()
	return nil, nil
}

func (a *App) handleQuit(map[string]string) (any, error) {
	go func() {
		time.Sleep(300 * time.Millisecond)
		a.tunnel.Stop()
		close(a.quit)
	}()
	return nil, nil
}

func tokenFile() string { return dataDir() + string(os.PathSeparator) + "ui-token" }
