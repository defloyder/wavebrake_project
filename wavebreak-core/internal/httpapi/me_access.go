package httpapi

import (
	"errors"
	"net/http"
	"net/url"
	"strings"
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
	// Links, most preferred first: XHTTP+REALITY through each healthy
	// domestic relay, VLESS REALITY (when published),
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
		Links:           appLinks(cfg, clientFeatures(r)),
	}
	// Second locations serving the same account (e.g. Moscow) follow.
	for _, mirror := range s.mirrorConfigs(r.Context(), cfg) {
		resp.Links = append(resp.Links, appLinks(mirror, clientFeatures(r))...)
	}
	if details.Subscription != nil {
		expires := details.Subscription.ExpiresAt
		resp.ExpiresAt = &expires
	}
	writeJSON(w, http.StatusOK, resp)
}

// appLinks picks the transports the WAVEBREAK apps support, in order of
// preference. The direct REALITY link only when Core publishes it.
func appLinks(cfg store.AccessGrantConfig, features map[string]bool) []string {
	links := make([]string, 0, 4+len(cfg.VLESSRelays))
	// Domestic relays first: on whitelisted mobile networks they're the
	// only TCP path that works; everywhere else the direct ones follow.
	for _, relay := range cfg.VLESSRelays {
		if uri := uriOf(relay); uri != "" {
			links = append(links, uri)
		}
	}
	if cfg.ShareURL != "" && cfg.VLESS != nil && cfg.ShareURL == uriOf(cfg.VLESS) {
		links = append(links, cfg.ShareURL)
	}
	hysteria := cfg.Hysteria
	// Apps that verify Hysteria2 by certificate pin get the neutral-SNI
	// variant instead (carriers drop the handshake by the usual SNI).
	if features[featureHysteriaPin] && uriOf(cfg.HysteriaPinned) != "" {
		hysteria = cfg.HysteriaPinned
	}
	// Behind a cloak relay only apps that wrap their packets in cloak
	// connect; to the others the location would just never pass traffic.
	if linkNeedsCloak(uriOf(hysteria)) && !features[featureHysteriaCloak] {
		hysteria = nil
	}
	for _, transport := range []map[string]any{cfg.VLESSRealityXHTTP, cfg.VLESSDirectTLS, hysteria} {
		if uri := uriOf(transport); uri != "" {
			links = append(links, uri)
		}
	}
	// Only to apps that say they can run it: older ones ignore the
	// obfuscation parameters and would list a location that never connects.
	if features[featureHysteriaObfs] {
		if uri := uriOf(cfg.HysteriaObfs); uri != "" {
			links = append(links, uri)
		}
	}
	return links
}

const featureHysteriaObfs = "hysteria-obfs"

// featureHysteriaCloak: the app runs cloak=1 Hysteria2 links (Android
// 1.2.4+, through the bridge's apernet client with the cloak layer).
const featureHysteriaCloak = "hysteria-cloak"

// linkNeedsCloak: a Hysteria2 link served through a cloak relay.
func linkNeedsCloak(uri string) bool {
	u, err := url.Parse(uri)
	return err == nil && u.Query().Get("cloak") == "1"
}

// clientFeatures: what the calling WAVEBREAK app can run, from its
// comma-separated X-Wavebreak-Features header (absent in older versions).
func clientFeatures(r *http.Request) map[string]bool {
	features := map[string]bool{}
	for _, f := range strings.Split(r.Header.Get("X-Wavebreak-Features"), ",") {
		if f = strings.TrimSpace(strings.ToLower(f)); f != "" {
			features[f] = true
		}
	}
	return features
}

func uriOf(transport map[string]any) string {
	if transport == nil {
		return ""
	}
	uri, _ := transport["uri"].(string)
	return uri
}
