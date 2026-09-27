package httpapi

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
	"encoding/binary"
	"encoding/hex"
	"errors"
	"net/http"
	"strings"
	"time"

	"github.com/go-chi/chi/v5/middleware"

	"wavebreak-core/internal/accounts"
	"wavebreak-core/internal/store"
)

// Sharing a subscription: the owner's app shows a QR with a share URL
// (POST /v1/me/share). Its token is signed and short-lived and names only
// the owner — no credential — so the QR alone gives no VPN access. The
// recipient's app redeems it (POST /v1/share/redeem): Core takes one of
// the owner's device slots and only then hands out the owner's links, so
// the owner's device and traffic limits cover everyone sharing them.

const (
	shareTokenTTL     = 72 * time.Hour
	shareTokenPayload = 16 + 4 // owner uuid + expiry (unix seconds)
	shareTokenMAC     = 16
)

var (
	errShareTokenInvalid = errors.New("share token invalid")
	errShareTokenExpired = errors.New("share token expired")
)

func shareKey(secret string) []byte {
	mac := hmac.New(sha256.New, []byte(secret))
	mac.Write([]byte("wavebreak-share-v1"))
	return mac.Sum(nil)
}

func signShareToken(secret, ownerID string, expires time.Time) (string, error) {
	id, err := hex.DecodeString(strings.ReplaceAll(ownerID, "-", ""))
	if err != nil || len(id) != 16 {
		return "", errShareTokenInvalid
	}
	buf := make([]byte, 0, shareTokenPayload+shareTokenMAC)
	buf = append(buf, id...)
	buf = binary.BigEndian.AppendUint32(buf, uint32(expires.Unix()))
	mac := hmac.New(sha256.New, shareKey(secret))
	mac.Write(buf)
	buf = append(buf, mac.Sum(nil)[:shareTokenMAC]...)
	return base64.RawURLEncoding.EncodeToString(buf), nil
}

// parseShareToken returns the owner's user id.
func parseShareToken(secret, token string, now time.Time) (string, error) {
	raw, err := base64.RawURLEncoding.DecodeString(strings.TrimSpace(token))
	if err != nil || len(raw) != shareTokenPayload+shareTokenMAC {
		return "", errShareTokenInvalid
	}
	payload, sum := raw[:shareTokenPayload], raw[shareTokenPayload:]
	mac := hmac.New(sha256.New, shareKey(secret))
	mac.Write(payload)
	if !hmac.Equal(sum, mac.Sum(nil)[:shareTokenMAC]) {
		return "", errShareTokenInvalid
	}
	if now.Unix() >= int64(binary.BigEndian.Uint32(payload[16:])) {
		return "", errShareTokenExpired
	}
	h := hex.EncodeToString(payload[:16])
	return h[0:8] + "-" + h[8:12] + "-" + h[12:16] + "-" + h[16:20] + "-" + h[20:], nil
}

// shareURLBase: the subscription URL base with /sub/ swapped for /share/,
// so both live on the same public Core host.
func (s *Server) shareURLBase() string {
	base := strings.TrimSpace(s.app.Config.Accounts.SubscriptionURLBase)
	if base == "" {
		base = accounts.DefaultSubscriptionURLBase
	}
	base = strings.TrimSuffix(base, "/")
	base = strings.TrimSuffix(base, "/sub")
	return base + "/share/"
}

type shareLimits struct {
	DeviceLimit       *int   `json:"device_limit"`
	DevicesUsed       int    `json:"devices_used"`
	TrafficLimitBytes *int64 `json:"traffic_limit_bytes"`
	TrafficUsedBytes  int64  `json:"traffic_used_bytes"`
}

func shareLimitsOf(d accounts.UserDetails) shareLimits {
	l := shareLimits{DeviceLimit: d.Devices.Limit, DevicesUsed: d.Devices.Registered}
	if d.Traffic != nil {
		l.TrafficLimitBytes = d.Traffic.LimitBytes
		l.TrafficUsedBytes = d.Traffic.BytesTotal
	}
	return l
}

// POST /v1/me/share
//
// A fresh share URL for the caller's own subscription plus its limits.
// Same errors as /v1/me/access without an active subscription.
func (s *Server) meShare(w http.ResponseWriter, r *http.Request) {
	actor := actorFrom(r)
	details, err := s.accounts.assign.IssueAccess(r.Context(), actor, actor.UserID)
	if err != nil {
		writeDomainError(w, r, err)
		return
	}
	expires := time.Now().Add(shareTokenTTL).Truncate(time.Second)
	token, err := signShareToken(s.app.Config.JWTSecret, actor.UserID, expires)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "could not create share link")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"share_url":  s.shareURLBase() + token,
		"expires_at": expires,
		"limits":     shareLimitsOf(details),
	})
}

// POST /v1/share/redeem {"token", "device_name", "platform"}
//
// Takes a device slot of the owner's subscription for the caller and
// returns the owner's app links. 400 SHARE_INVALID, 410 SHARE_EXPIRED,
// 409 SHARE_OWN_SUBSCRIPTION, 403 DEVICE_LIMIT_REACHED, and the owner's
// 404 SUBSCRIPTION_NOT_FOUND / 422 SUBSCRIPTION_NOT_ACTIVE.
func (s *Server) redeemShare(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Token      string `json:"token"`
		DeviceName string `json:"device_name"`
		Platform   string `json:"platform"`
	}
	if !decodeJSON(w, r, &req) {
		return
	}
	ownerID, err := parseShareToken(s.app.Config.JWTSecret, req.Token, time.Now())
	switch {
	case errors.Is(err, errShareTokenExpired):
		writeShareError(w, r, http.StatusGone, "SHARE_EXPIRED", "This share code has expired.")
		return
	case err != nil:
		writeShareError(w, r, http.StatusBadRequest, "SHARE_INVALID", "This is not a valid share code.")
		return
	}
	actor := actorFrom(r)
	if ownerID == actor.UserID {
		writeShareError(w, r, http.StatusConflict, "SHARE_OWN_SUBSCRIPTION", "This is your own subscription.")
		return
	}
	details, err := s.accounts.assign.IssueAccess(r.Context(), actor, ownerID)
	if err != nil {
		writeDomainError(w, r, err)
		return
	}

	name := strings.TrimSpace(req.DeviceName)
	if name == "" {
		name = "WAVEBREAK device"
	}
	if len([]rune(name)) > 60 {
		name = string([]rune(name)[:60])
	}
	device, err := s.app.Store.ClaimSharedDevice(r.Context(), ownerID, actor.UserID, "QR · "+name, strings.TrimSpace(req.Platform))
	if errors.Is(err, store.ErrLimitReached) {
		writeShareError(w, r, http.StatusForbidden, accounts.CodeDeviceLimitReached, "The subscription's device limit is reached.")
		return
	}
	if err != nil {
		writeError(w, http.StatusInternalServerError, "could not register the device")
		return
	}

	cfg, err := s.app.Store.AccessGrantConfigPublic(r.Context(), details.Access.CredentialID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "could not load access")
		return
	}
	s.applyVLESSRuntimeConfig(&cfg)
	planName := ""
	if details.Subscription != nil && details.Subscription.Plan != nil {
		planName = details.Subscription.Plan.Name
	}
	var expiresAt *time.Time
	if details.Subscription != nil {
		at := details.Subscription.ExpiresAt
		expiresAt = &at
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"device_id":        device.ID,
		"plan_name":        planName,
		"subscription_url": details.Access.SubscriptionURL,
		"expires_at":       expiresAt,
		"links":            appLinks(cfg),
	})
}

type sharedSubscriptionView struct {
	DeviceID        string      `json:"device_id,omitempty"`
	PlanName        string      `json:"plan_name"`
	Status          string      `json:"status"`
	ExpiresAt       *time.Time  `json:"expires_at"`
	SubscriptionURL string      `json:"subscription_url,omitempty"`
	Limits          shareLimits `json:"limits"`
	Links           []string    `json:"links,omitempty"`
}

func sharedView(d accounts.UserDetails) sharedSubscriptionView {
	v := sharedSubscriptionView{Status: "none", Limits: shareLimitsOf(d), SubscriptionURL: d.Access.SubscriptionURL}
	if d.Subscription != nil {
		v.Status = d.Subscription.Status
		at := d.Subscription.ExpiresAt
		v.ExpiresAt = &at
		if d.Subscription.Plan != nil {
			v.PlanName = d.Subscription.Plan.Name
		}
	}
	return v
}

// GET /v1/me/sharing
//
// The caller's own subscription (plan, limits; null without one) and every
// subscription shared with the caller through a share code that still
// holds a slot: plan, owner's limits and, while it is active, the app
// links. A slot the owner revoked drops out of "received".
func (s *Server) meSharing(w http.ResponseWriter, r *http.Request) {
	actor := actorFrom(r)
	resp := map[string]any{"own": nil, "received": []sharedSubscriptionView{}}
	own, err := s.accounts.details.Get(r.Context(), actor.UserID)
	if err != nil {
		writeDomainError(w, r, err)
		return
	}
	if own.Subscription != nil {
		v := sharedView(own)
		v.SubscriptionURL = ""
		resp["own"] = v
	}

	slots, err := s.app.Store.SharedSlotsOf(r.Context(), actor.UserID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "could not load shared subscriptions")
		return
	}
	received := make([]sharedSubscriptionView, 0, len(slots))
	for _, slot := range slots {
		d, err := s.accounts.details.Get(r.Context(), slot.OwnerID)
		if err != nil {
			continue // owner deleted: nothing left to show
		}
		v := sharedView(d)
		v.DeviceID = slot.DeviceID
		active := d.Subscription != nil && d.Subscription.Status == "active" && d.Subscription.ExpiresAt.After(time.Now())
		if active && d.Access.CredentialID != "" {
			if cfg, err := s.app.Store.AccessGrantConfigPublic(r.Context(), d.Access.CredentialID); err == nil {
				s.applyVLESSRuntimeConfig(&cfg)
				v.Links = appLinks(cfg)
			}
		}
		received = append(received, v)
	}
	resp["received"] = received
	writeJSON(w, http.StatusOK, resp)
}

// GET /v1/share/{token}: what a plain camera app opens. The code is meant
// for the WAVEBREAK app; nothing about the subscription is revealed here.
func (s *Server) shareLanding(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "text/plain; charset=utf-8")
	w.Header().Set("Cache-Control", "no-store")
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write([]byte("WAVEBREAK: откройте приложение WAVEBREAK → «Добавить свою VPN-ссылку» → QR и отсканируйте этот код.\n" +
		"WAVEBREAK: open the WAVEBREAK app → \"Add your own VPN link\" → QR and scan this code.\n"))
}

func writeShareError(w http.ResponseWriter, r *http.Request, status int, code, message string) {
	writeJSON(w, status, map[string]any{
		"error": map[string]any{
			"code":       code,
			"message":    message,
			"request_id": middleware.GetReqID(r.Context()),
		},
	})
}
