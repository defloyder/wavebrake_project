package main

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"strings"
	"sync"
	"time"
)

const coreBaseURL = "https://core.wavebreak.com.tr/v1"

// What this build can run. No hysteria-cloak / hysteria-pin: those need
// the bridge the full Windows app ships; Core then sends plain links.
const clientFeatures = "hysteria-obfs,email-verification"

var (
	errNotVerified    = errors.New("email_not_verified")
	errBadCredentials = errors.New("invalid_credentials")
	errSignedOut      = errors.New("signed_out")
	errNoSubscription = errors.New("no_subscription")
)

type apiError struct {
	Status int
	Code   string
	Msg    string
}

func (e *apiError) Error() string { return fmt.Sprintf("HTTP %d: %s", e.Status, e.Msg) }

// Core talks to WAVEBREAK Core with one session: the access token in
// memory, the refresh token DPAPI-encrypted in the state file.
type Core struct {
	http  *http.Client
	state *stateStore

	mu          sync.Mutex
	accessToken string
}

func newCore(state *stateStore) *Core {
	return &Core{http: &http.Client{Timeout: 20 * time.Second}, state: state}
}

func (c *Core) do(method, path string, body any, auth bool, out any) error {
	var rd io.Reader
	if body != nil {
		b, _ := json.Marshal(body)
		rd = bytes.NewReader(b)
	}
	req, err := http.NewRequest(method, coreBaseURL+path, rd)
	if err != nil {
		return err
	}
	req.Header.Set("Accept", "application/json")
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Accept-Language", "ru")
	req.Header.Set("X-Wavebreak-Features", clientFeatures)
	req.Header.Set("User-Agent", "WAVEBREAK-Lite/"+version+" (Windows x86)")
	if auth {
		c.mu.Lock()
		token := c.accessToken
		c.mu.Unlock()
		if token == "" {
			return errSignedOut
		}
		req.Header.Set("Authorization", "Bearer "+token)
	}
	resp, err := c.http.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	data, _ := io.ReadAll(io.LimitReader(resp.Body, 4<<20))
	if resp.StatusCode >= 300 {
		var e struct {
			Code  string `json:"code"`
			Error string `json:"error"`
		}
		_ = json.Unmarshal(data, &e)
		return &apiError{Status: resp.StatusCode, Code: strings.ToLower(e.Code), Msg: e.Error}
	}
	if out != nil {
		return json.Unmarshal(data, out)
	}
	return nil
}

// authed retries once with a refreshed access token on 401.
func (c *Core) authed(method, path string, body, out any) error {
	err := c.do(method, path, body, true, out)
	var ae *apiError
	if errors.Is(err, errSignedOut) || (errors.As(err, &ae) && ae.Status == 401) {
		if rerr := c.refresh(); rerr != nil {
			return rerr
		}
		err = c.do(method, path, body, true, out)
	}
	return err
}

type tokenPair struct {
	AccessToken  string `json:"access_token"`
	RefreshToken string `json:"refresh_token"`
	Tokens       *struct {
		AccessToken  string `json:"access_token"`
		RefreshToken string `json:"refresh_token"`
	} `json:"tokens"`
	VerificationRequired bool `json:"verification_required"`
}

func (c *Core) keep(t tokenPair) {
	access, refresh := t.AccessToken, t.RefreshToken
	if t.Tokens != nil {
		access, refresh = t.Tokens.AccessToken, t.Tokens.RefreshToken
	}
	c.mu.Lock()
	c.accessToken = access
	c.mu.Unlock()
	c.state.setRefreshToken(refresh)
}

func (c *Core) Login(email, password string) error {
	var t tokenPair
	err := c.do("POST", "/auth/login", map[string]string{"email": email, "password": password}, false, &t)
	var ae *apiError
	if errors.As(err, &ae) {
		switch {
		case ae.Code == "email_not_verified":
			return errNotVerified
		case ae.Status == 401 || ae.Status == 400:
			return errBadCredentials
		}
	}
	if err != nil {
		return err
	}
	c.keep(t)
	c.state.update(func(s *State) { s.Email = email })
	return nil
}

func (c *Core) VerifyEmail(email, code string) error {
	var t tokenPair
	if err := c.do("POST", "/auth/email/verify", map[string]string{"email": email, "code": code}, false, &t); err != nil {
		return err
	}
	c.keep(t)
	c.state.update(func(s *State) { s.Email = email })
	return nil
}

func (c *Core) ResendCode(email string) error {
	return c.do("POST", "/auth/email/resend", map[string]string{"email": email}, false, nil)
}

func (c *Core) refresh() error {
	rt := c.state.refreshToken()
	if rt == "" {
		return errSignedOut
	}
	var t tokenPair
	err := c.do("POST", "/auth/refresh", map[string]string{"refresh_token": rt}, false, &t)
	var ae *apiError
	if errors.As(err, &ae) && (ae.Status == 401 || ae.Status == 400) {
		c.forget()
		return errSignedOut
	}
	if err != nil {
		return err
	}
	c.keep(t)
	return nil
}

func (c *Core) SignedIn() bool { return c.state.refreshToken() != "" }

func (c *Core) Logout() {
	if rt := c.state.refreshToken(); rt != "" {
		_ = c.do("POST", "/auth/logout", map[string]string{"refresh_token": rt}, true, nil)
	}
	c.forget()
}

func (c *Core) forget() {
	c.mu.Lock()
	c.accessToken = ""
	c.mu.Unlock()
	c.state.setRefreshToken("")
}

// RegisterDevice registers this computer (best effort). With install_id
// Core returns the existing device instead of taking a new slot; a Core
// that doesn't know the field refuses the body (400) — then without it.
func (c *Core) RegisterDevice() {
	name, _ := os.Hostname()
	if name == "" {
		name = "Windows PC"
	}
	body := map[string]string{"name": name, "platform": "windows", "install_id": c.state.get().InstallID}
	err := c.authed("POST", "/me/devices", body, nil)
	var ae *apiError
	if errors.As(err, &ae) && ae.Status == 400 {
		delete(body, "install_id")
		err = c.authed("POST", "/me/devices", body, nil)
	}
	if err != nil {
		logf("device registration: %v", err)
	}
}

// Access is the account's VPN access: its share links (POST /me/access).
func (c *Core) Access() ([]string, error) {
	var out struct {
		Links []string `json:"links"`
	}
	err := c.authed("POST", "/me/access", map[string]any{}, &out)
	var ae *apiError
	if errors.As(err, &ae) && (ae.Status == 402 || ae.Status == 404 || ae.Status == 422) {
		return nil, errNoSubscription
	}
	return out.Links, err
}
