package httpapi

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"crypto/sha256"
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"strings"
	"time"

	"golang.org/x/crypto/hkdf"

	"wavebreak-core/internal/store"
)

// The user's own VPN links, synced between the devices of one account
// (owner, 15.10). The apps turn it on per device ("Sync my links", off by
// default) and merge: each entry is a link with when it was added and,
// once removed on some device, when — so a removal reaches the others
// instead of the link coming back from them.
//
//	GET /v1/me/custom-links → {"version": 3, "entries": [...]}
//	PUT /v1/me/custom-links   {"version": 3, "entries": [...]}
//	    → 200 {"version": 4}, or 409 {"version": 5, "entries": [...]}
//	      when another device wrote first (merge and send again).
//
// Sealed with AES-256-GCM under a key derived from the server secret,
// the user id as associated data: a database dump alone doesn't reveal
// the links, and one user's vault can't be passed off as another's.

const (
	maxLinkEntries  = 300
	maxLinkLength   = 8 << 10
	maxLinkBodySize = 1 << 20
)

type customLinkEntry struct {
	Link    string     `json:"link"`
	Added   time.Time  `json:"added"`
	Removed *time.Time `json:"removed,omitempty"`
}

type customLinkDoc struct {
	Version int64             `json:"version"`
	Entries []customLinkEntry `json:"entries"`
}

func (d customLinkDoc) validate() error {
	if d.Version < 0 {
		return errors.New("bad version")
	}
	if len(d.Entries) > maxLinkEntries {
		return errors.New("too many links")
	}
	for _, e := range d.Entries {
		link := strings.TrimSpace(e.Link)
		if link == "" || len(link) > maxLinkLength || !strings.Contains(link, "://") {
			return errors.New("bad link")
		}
		if e.Added.IsZero() {
			return errors.New("missing added time")
		}
	}
	return nil
}

func linkVaultKey(secret string) ([]byte, error) {
	key := make([]byte, 32)
	r := hkdf.New(sha256.New, []byte(secret), nil, []byte("wavebreak custom-link vault v1"))
	if _, err := io.ReadFull(r, key); err != nil {
		return nil, err
	}
	return key, nil
}

func sealLinks(secret, userID string, entries []customLinkEntry) (nonce, ciphertext []byte, err error) {
	plain, err := json.Marshal(entries)
	if err != nil {
		return nil, nil, err
	}
	key, err := linkVaultKey(secret)
	if err != nil {
		return nil, nil, err
	}
	block, err := aes.NewCipher(key)
	if err != nil {
		return nil, nil, err
	}
	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return nil, nil, err
	}
	nonce = make([]byte, gcm.NonceSize())
	if _, err := rand.Read(nonce); err != nil {
		return nil, nil, err
	}
	return nonce, gcm.Seal(nil, nonce, plain, []byte(userID)), nil
}

func openLinks(secret, userID string, nonce, ciphertext []byte) ([]customLinkEntry, error) {
	key, err := linkVaultKey(secret)
	if err != nil {
		return nil, err
	}
	block, err := aes.NewCipher(key)
	if err != nil {
		return nil, err
	}
	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return nil, err
	}
	plain, err := gcm.Open(nil, nonce, ciphertext, []byte(userID))
	if err != nil {
		return nil, err
	}
	var entries []customLinkEntry
	if err := json.Unmarshal(plain, &entries); err != nil {
		return nil, err
	}
	return entries, nil
}

// vaultDoc opens a stored vault; one that no longer opens (the server
// secret changed) reads as empty rather than failing every sync.
func (s *Server) vaultDoc(userID string, v store.LinkVault) customLinkDoc {
	entries, err := openLinks(s.app.Config.JWTSecret, userID, v.Nonce, v.Ciphertext)
	if err != nil {
		slog.Warn("custom-link vault does not open", "user", userID, "err", err)
		entries = nil
	}
	if entries == nil {
		entries = []customLinkEntry{}
	}
	return customLinkDoc{Version: v.Version, Entries: entries}
}

// GET /v1/me/custom-links
func (s *Server) getCustomLinks(w http.ResponseWriter, r *http.Request) {
	userID := actorFrom(r).UserID
	v, found, err := s.app.Store.LinkVaultOf(r.Context(), userID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "could not load links")
		return
	}
	if !found {
		writeJSON(w, http.StatusOK, customLinkDoc{Version: 0, Entries: []customLinkEntry{}})
		return
	}
	writeJSON(w, http.StatusOK, s.vaultDoc(userID, v))
}

// PUT /v1/me/custom-links
func (s *Server) putCustomLinks(w http.ResponseWriter, r *http.Request) {
	userID := actorFrom(r).UserID
	r.Body = http.MaxBytesReader(w, r.Body, maxLinkBodySize)
	var doc customLinkDoc
	if !decodeJSON(w, r, &doc) {
		return
	}
	if err := doc.validate(); err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	nonce, ct, err := sealLinks(s.app.Config.JWTSecret, userID, doc.Entries)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "could not seal links")
		return
	}
	next, current, err := s.app.Store.PutLinkVault(r.Context(), userID, doc.Version, nonce, ct)
	if errors.Is(err, store.ErrVersionConflict) {
		if current.Version == 0 {
			writeJSON(w, http.StatusConflict, customLinkDoc{Version: 0, Entries: []customLinkEntry{}})
			return
		}
		writeJSON(w, http.StatusConflict, s.vaultDoc(userID, current))
		return
	}
	if err != nil {
		writeError(w, http.StatusInternalServerError, "could not save links")
		return
	}
	writeJSON(w, http.StatusOK, map[string]int64{"version": next})
}
