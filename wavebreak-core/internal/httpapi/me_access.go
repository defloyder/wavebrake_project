package httpapi

import (
	"errors"
	"net/http"
	"time"

	"wavebreak-core/internal/store"
)

// meAccessResponse is the caller's own VPN access: the stable credential
// of their subscription and the links the WAVEBREAK apps connect with.
type meAccessResponse struct {
	CredentialID    string     `json:"credential_id"`
	SubscriptionURL string     `json:"subscription_url"`
	ConfigStatus    string     `json:"config_status"`
	ExpiresAt       *time.Time `json:"expires_at,omitempty"`
	// Links, most preferred first: VLESS REALITY (when published),
	// VLESS XHTTP+REALITY (when configured),
	// VLESS Direct-TLS, Hysteria2. Each is a standard share link.
	Links []string `json:"links"`
}

// POST /v1/me/access
//
// Returns the caller's subscription credential, issuing it first when the
// subscription has none (bought in the app, created before
// primary_grant_id). Every device of the account uses the same credential,
// so traffic is counted on the account's one subscription. Without an
// active subscription there is no access: 404 SUBSCRIPTION_NOT_FOUND or
// 422 SUBSCRIPTION_NOT_ACTIVE (past_due, suspended, period over).
func (s *Server) meAccess(w http.ResponseWriter, r *http.Request) {
	actor := actorFrom(r)
	details, err := s.accounts.assign.IssueAccess(r.Context(), actor, actor.UserID)
	if err != nil {
		writeDomainError(w, r, err)
		return
	}
	cfg, err := s.app.Store.AccessGrantConfigPublic(r.Context(), details.Access.CredentialID)
	if errors.Is(err, store.ErrNotFound) {
		writeError(w, http.StatusNotFound, "access not found")
		return
	}
	if err != nil {
		writeError(w, http.StatusInternalServerError, "could not load access")
		return
	}
	s.applyVLESSRuntimeConfig(&cfg)
	resp := meAccessResponse{
		CredentialID:    details.Access.CredentialID,
		SubscriptionURL: details.Access.SubscriptionURL,
		ConfigStatus:    cfg.ConfigStatus,
		Links:           appLinks(cfg),
	}
	if details.Subscription != nil {
		expires := details.Subscription.ExpiresAt
		resp.ExpiresAt = &expires
	}
	writeJSON(w, http.StatusOK, resp)
}

// appLinks picks the transports the WAVEBREAK apps support, in order of
// preference. The direct REALITY link only when Core publishes it.
func appLinks(cfg store.AccessGrantConfig) []string {
	links := make([]string, 0, 3)
	if cfg.ShareURL != "" && cfg.VLESS != nil && cfg.ShareURL == uriOf(cfg.VLESS) {
		links = append(links, cfg.ShareURL)
	}
	for _, transport := range []map[string]any{cfg.VLESSRealityXHTTP, cfg.VLESSDirectTLS, cfg.Hysteria} {
		if uri := uriOf(transport); uri != "" {
			links = append(links, uri)
		}
	}
	return links
}

func uriOf(transport map[string]any) string {
	if transport == nil {
		return ""
	}
	uri, _ := transport["uri"].(string)
	return uri
}
