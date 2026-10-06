package main

import (
	"crypto/rand"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"os"
	"path/filepath"
	"sync"
)

// State is what survives a restart, in %LOCALAPPDATA%\WAVEBREAK Lite.
// The refresh token is DPAPI-encrypted for the current Windows user.
type State struct {
	InstallID       string `json:"install_id"`
	Email           string `json:"email,omitempty"`
	RefreshTokenEnc string `json:"refresh_token_enc,omitempty"`
	Selected        string `json:"selected,omitempty"`
}

type stateStore struct {
	mu   sync.Mutex
	path string
	s    State
}

func dataDir() string {
	base := os.Getenv("LOCALAPPDATA")
	if base == "" {
		base = os.TempDir()
	}
	dir := filepath.Join(base, "WAVEBREAK Lite")
	_ = os.MkdirAll(dir, 0o700)
	return dir
}

func loadState() *stateStore {
	st := &stateStore{path: filepath.Join(dataDir(), "state.json")}
	if b, err := os.ReadFile(st.path); err == nil {
		_ = json.Unmarshal(b, &st.s)
	}
	if st.s.InstallID == "" {
		// Kept across sign-outs: Core gives this installation its device
		// back instead of taking another subscription slot.
		st.s.InstallID = randomHex(16)
		st.saveLocked()
	}
	return st
}

func (st *stateStore) get() State {
	st.mu.Lock()
	defer st.mu.Unlock()
	return st.s
}

func (st *stateStore) update(f func(*State)) {
	st.mu.Lock()
	defer st.mu.Unlock()
	f(&st.s)
	st.saveLocked()
}

func (st *stateStore) saveLocked() {
	b, _ := json.MarshalIndent(st.s, "", "  ")
	tmp := st.path + ".tmp"
	if os.WriteFile(tmp, b, 0o600) == nil {
		_ = os.Rename(tmp, st.path)
	}
}

func (st *stateStore) refreshToken() string {
	enc := st.get().RefreshTokenEnc
	if enc == "" {
		return ""
	}
	raw, err := base64.StdEncoding.DecodeString(enc)
	if err != nil {
		return ""
	}
	plain, err := unprotect(raw)
	if err != nil {
		return ""
	}
	return string(plain)
}

func (st *stateStore) setRefreshToken(token string) {
	enc := ""
	if token != "" {
		if b, err := protect([]byte(token)); err == nil {
			enc = base64.StdEncoding.EncodeToString(b)
		}
	}
	st.update(func(s *State) { s.RefreshTokenEnc = enc })
}

func randomHex(n int) string {
	b := make([]byte, n)
	_, _ = rand.Read(b)
	return hex.EncodeToString(b)
}
