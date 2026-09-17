package httpapi

import (
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"

	"github.com/go-chi/chi/v5"

	"wavebreak-core/internal/config"
	"wavebreak-core/internal/security"
	"wavebreak-core/internal/store"
)

func (s *Server) meOverview(w http.ResponseWriter, r *http.Request) {
	overview, err := s.app.Store.UserOverview(r.Context(), currentUser(r.Context()).ID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "could not load overview")
		return
	}
	writeJSON(w, http.StatusOK, overview)
}

func (s *Server) clientBootstrap(w http.ResponseWriter, r *http.Request) {
	bootstrap, err := s.app.Store.ClientBootstrap(r.Context(), currentUser(r.Context()).ID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "could not load client bootstrap")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"user":      bootstrap.User,
		"overview":  bootstrap.Overview,
		"plans":     bootstrap.Plans,
		"nodes":     bootstrap.Nodes,
		"locations": s.locationPayloads(bootstrap.Nodes),
	})
}

func (s *Server) meIdentities(w http.ResponseWriter, r *http.Request) {
	identities, err := s.app.Store.ListUserIdentities(r.Context(), currentUser(r.Context()).ID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "could not list identities")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"identities": identities})
}

func (s *Server) createTelegramLink(w http.ResponseWriter, r *http.Request) {
	token, err := security.RandomToken(24)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "could not issue link token")
		return
	}
	link, err := s.app.Store.CreateAccountLinkToken(r.Context(), currentUser(r.Context()).ID, "telegram", token, time.Now().UTC().Add(15*time.Minute))
	if err != nil {
		writeError(w, http.StatusInternalServerError, "could not create link token")
		return
	}
	writeJSON(w, http.StatusCreated, link)
}

func (s *Server) unlinkTelegram(w http.ResponseWriter, r *http.Request) {
	err := s.app.Store.UnlinkUserIdentity(r.Context(), currentUser(r.Context()).ID, "telegram")
	if errors.Is(err, store.ErrNotFound) {
		writeError(w, http.StatusNotFound, "telegram identity not found")
		return
	}
	if err != nil {
		writeError(w, http.StatusInternalServerError, "could not unlink telegram")
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

func (s *Server) meUsage(w http.ResponseWriter, r *http.Request) {
	usage, err := s.app.Store.UsageSummary(r.Context(), currentUser(r.Context()).ID)
	if errors.Is(err, store.ErrNotFound) {
		writeError(w, http.StatusNotFound, "active subscription not found")
		return
	}
	if err != nil {
		writeError(w, http.StatusInternalServerError, "could not load usage")
		return
	}
	writeJSON(w, http.StatusOK, usage)
}

func (s *Server) meUsageHistory(w http.ResponseWriter, r *http.Request) {
	days := 7
	switch r.URL.Query().Get("period") {
	case "30d":
		days = 30
	case "current", "7d", "":
		days = 7
	default:
		writeError(w, http.StatusBadRequest, "period must be 7d, 30d or current")
		return
	}
	history, err := s.app.Store.UsageHistory(r.Context(), currentUser(r.Context()).ID, days)
	if errors.Is(err, store.ErrNotFound) {
		writeError(w, http.StatusNotFound, "active subscription not found")
		return
	}
	if err != nil {
		writeError(w, http.StatusInternalServerError, "could not load usage history")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"history": history})
}

func (s *Server) listDevices(w http.ResponseWriter, r *http.Request) {
	devices, err := s.app.Store.ListDevices(r.Context(), currentUser(r.Context()).ID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "could not list devices")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"devices": devices})
}

func (s *Server) createDevice(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Name     string `json:"name"`
		Platform string `json:"platform"`
	}
	if !decodeJSON(w, r, &req) {
		return
	}
	req.Name = strings.TrimSpace(req.Name)
	if req.Name == "" {
		writeError(w, http.StatusBadRequest, "device name is required")
		return
	}
	device, err := s.app.Store.CreateDevice(r.Context(), currentUser(r.Context()).ID, req.Name, strings.TrimSpace(req.Platform))
	if errors.Is(err, store.ErrLimitReached) {
		writeError(w, http.StatusForbidden, "DEVICE_LIMIT_REACHED")
		return
	}
	if err != nil {
		writeError(w, http.StatusBadRequest, "could not create device")
		return
	}
	writeJSON(w, http.StatusCreated, device)
}

func (s *Server) updateDevice(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Name     string `json:"name"`
		Platform string `json:"platform"`
	}
	if !decodeJSON(w, r, &req) {
		return
	}
	device, err := s.app.Store.UpdateDevice(r.Context(), currentUser(r.Context()).ID, chi.URLParam(r, "deviceID"), strings.TrimSpace(req.Name), strings.TrimSpace(req.Platform))
	if errors.Is(err, store.ErrNotFound) {
		writeError(w, http.StatusNotFound, "device not found")
		return
	}
	if err != nil {
		writeError(w, http.StatusBadRequest, "could not update device")
		return
	}
	writeJSON(w, http.StatusOK, device)
}

func (s *Server) revokeDevice(w http.ResponseWriter, r *http.Request) {
	err := s.app.Store.RevokeDevice(r.Context(), currentUser(r.Context()).ID, chi.URLParam(r, "deviceID"))
	if errors.Is(err, store.ErrNotFound) {
		writeError(w, http.StatusNotFound, "device not found")
		return
	}
	if err != nil {
		writeError(w, http.StatusInternalServerError, "could not revoke device")
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

func (s *Server) revokeAccessGrant(w http.ResponseWriter, r *http.Request) {
	grant, err := s.app.Store.RevokeAccessGrant(r.Context(), currentUser(r.Context()).ID, chi.URLParam(r, "grantID"), "user")
	if errors.Is(err, store.ErrNotFound) {
		writeError(w, http.StatusNotFound, "grant not found")
		return
	}
	if err != nil {
		writeError(w, http.StatusBadRequest, "could not revoke access grant")
		return
	}
	writeJSON(w, http.StatusOK, grant)
}

func (s *Server) accessGrantConfig(w http.ResponseWriter, r *http.Request) {
	config, err := s.app.Store.AccessGrantConfig(r.Context(), currentUser(r.Context()).ID, chi.URLParam(r, "grantID"))
	if errors.Is(err, store.ErrNotFound) {
		writeError(w, http.StatusNotFound, "grant not found")
		return
	}
	if err != nil {
		writeError(w, http.StatusInternalServerError, "could not load grant config")
		return
	}
	s.applyVLESSRuntimeConfig(&config)
	writeJSON(w, http.StatusOK, config)
}

var regionFlags = map[string]string{
	"NL": "🇳🇱",
	"TR": "🇹🇷",
	"DE": "🇩🇪",
	"US": "🇺🇸",
	"GB": "🇬🇧",
	"FR": "🇫🇷",
	"SG": "🇸🇬",
	"JP": "🇯🇵",
}

var regionNames = map[string]string{
	"NL": "Netherlands",
	"TR": "Turkey",
	"DE": "Germany",
	"US": "United States",
	"GB": "United Kingdom",
	"FR": "France",
	"SG": "Singapore",
	"JP": "Japan",
}

// nodeCities fills in a friendly city for specific known node codes; nodes
// without an entry here still get a clean "<flag> <country>" label.
var nodeCities = map[string]string{
	"NL-PILOT-01": "Amsterdam",
}

// locationLabel renders a human node code like "NL-PILOT-01" as something
// a person picks out of a server list at a glance, e.g. "🇳🇱 Netherlands, Amsterdam".
func locationLabel(node store.Node) string {
	region := strings.ToUpper(strings.TrimSpace(node.Region))
	flag := regionFlags[region]
	if flag == "" {
		flag = "🌐"
	}
	name := regionNames[region]
	if name == "" {
		name = region
	}
	if city, ok := nodeCities[strings.ToUpper(strings.TrimSpace(node.Code))]; ok {
		return fmt.Sprintf("%s %s, %s", flag, name, city)
	}
	return fmt.Sprintf("%s %s", flag, name)
}

func locationPayload(node store.Node) map[string]any {
	region := strings.ToUpper(strings.TrimSpace(node.Region))
	country := regionNames[region]
	if country == "" {
		country = region
	}
	city := nodeCities[strings.ToUpper(strings.TrimSpace(node.Code))]
	label := locationLabel(node)
	return map[string]any{
		"id":            node.ID,
		"node_id":       node.ID,
		"node_code":     node.Code,
		"region":        region,
		"country":       country,
		"city":          city,
		"label":         label,
		"display_name":  label,
		"status":        node.Status,
		"online":        node.Status == "online",
		"desired_rev":   node.DesiredRevision,
		"applied_rev":   node.AppliedRevision,
		"last_seen_at":  node.LastHeartbeatAt,
		"last_error":    node.LastSyncError,
		"is_available":  node.Status == "online" && node.LastSyncError == nil,
		"protocol_hint": "vless-reality",
	}
}

func (s *Server) locationPayloads(nodes []store.Node) []map[string]any {
	locations := make([]map[string]any, 0, len(nodes))
	for _, node := range nodes {
		location := locationPayload(node)
		if strings.TrimSpace(s.app.Config.VLESS.PublicHost) != "" {
			location["connection_test"] = s.connectionTestPayload(node)
		}
		locations = append(locations, location)
	}
	return locations
}

func (s *Server) connectionTestPayload(node store.Node) map[string]any {
	vless := s.app.Config.VLESS
	return map[string]any{
		"node_id":      node.ID,
		"node_code":    node.Code,
		"protocol":     "vless",
		"transport":    "tcp",
		"security":     "reality",
		"host":         vless.PublicHost,
		"port":         vless.PublicPort,
		"sni":          vless.RealityServerName,
		"timeout_ms":   8000,
		"test_targets": []string{"api.telegram.org:443", "telegram.org:443", "t.me:443"},
	}
}

// subscriptionByGrant is the URL a VPN client (Happ, v2rayNG, NekoBox, ...)
// is pointed at once and then refreshes on its own schedule, instead of the
// user re-pasting a raw vless:// link. It is intentionally unauthenticated
// (keyed by the grant's own unguessable UUID) since a subscription refresh
// has no short-lived JWT to present. The body bundles every transport the
// grant has. The production subscription publishes the primary VLESS+REALITY
// profile by default; optional fallback transports must be explicitly enabled
// so VPN clients do not auto-select a partially supported protocol.
func (s *Server) subscriptionByGrant(w http.ResponseWriter, r *http.Request) {
	cfg, err := s.app.Store.AccessGrantConfigPublic(r.Context(), chi.URLParam(r, "grantID"))
	if errors.Is(err, store.ErrNotFound) {
		writeError(w, http.StatusNotFound, "subscription not found")
		return
	}
	if err != nil {
		writeError(w, http.StatusInternalServerError, "could not load subscription")
		return
	}
	s.applyVLESSRuntimeConfig(&cfg)
	if len(cfg.Links) == 0 {
		writeError(w, http.StatusServiceUnavailable, "subscription is not ready yet: "+cfg.ConfigStatus)
		return
	}

	planName := cfg.PlanName
	if planName == "" {
		planName = "WaveBreak"
	} else {
		planName = "WaveBreak — " + planName
	}
	w.Header().Set("Profile-Title", "base64:"+base64.StdEncoding.EncodeToString([]byte(planName)))
	w.Header().Set("Profile-Update-Interval", "12")
	userinfo := fmt.Sprintf("upload=%d; download=%d", cfg.BytesUp, cfg.BytesDown)
	if cfg.TrafficLimitBytes != nil {
		userinfo += fmt.Sprintf("; total=%d", *cfg.TrafficLimitBytes)
	}
	if cfg.SubscriptionExpiresAt != nil {
		userinfo += fmt.Sprintf("; expire=%d", cfg.SubscriptionExpiresAt.Unix())
	}
	w.Header().Set("Subscription-Userinfo", userinfo)
	w.Header().Set("Content-Type", "text/plain; charset=utf-8")
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write([]byte(base64.StdEncoding.EncodeToString([]byte(strings.Join(cfg.Links, "\n")))))
}

func (s *Server) applyVLESSRuntimeConfig(config *store.AccessGrantConfig) {
	if config.Grant.Protocol != "vless" && config.Grant.Protocol != "vless-reality" {
		return
	}
	if config.Grant.Status == "revoked" {
		config.ConfigStatus = "revoked"
		return
	}
	vless := s.app.Config.VLESS
	if strings.TrimSpace(vless.PublicHost) == "" || strings.TrimSpace(vless.RealityPublicKey) == "" || strings.TrimSpace(vless.RealityShortID) == "" {
		config.ConfigStatus = "pending_runtime_config"
		config.Warnings = []string{"VLESS REALITY public endpoint is not configured on Core yet."}
		return
	}
	if config.Node.AppliedRevision < config.Grant.DesiredRevision {
		config.ConfigStatus = "pending_node_ack"
		config.Warnings = []string{"Node has not acknowledged the desired-state revision for this grant yet."}
	} else {
		config.ConfigStatus = "ready"
		config.Warnings = nil
	}

	location := locationLabel(config.Node)
	links := make([]string, 0, 2)
	cdnAvailable := strings.TrimSpace(vless.CDNHost) != "" && vless.CDNPort > 0 && vless.PublishCDNWS

	vlessLink := buildVLESSLink(vless, config.Grant.ID, location)
	config.Location = locationPayload(config.Node)
	config.ConnectionTest = s.connectionTestPayload(config.Node)
	config.RoutingPolicy = smartRoutingPolicy()
	// The direct REALITY link is only published when explicitly enabled —
	// on a network that's confirmed to actively disrupt REALITY, showing it
	// alongside a working CDN link just gives a client a broken option to
	// pick by mistake.
	if vless.PublishDirect {
		links = append(links, vlessLink)
		config.ConnectionURL = vlessLink
		config.ShareURL = vlessLink
	}
	config.VLESS = map[string]any{
		"client_id":          config.Grant.ID,
		"label":              location,
		"protocol":           "vless",
		"security":           "reality",
		"network":            "tcp",
		"server":             vless.PublicHost,
		"port":               vless.PublicPort,
		"sni":                vless.RealityServerName,
		"fingerprint":        vless.Fingerprint,
		"reality_public_key": vless.RealityPublicKey,
		"short_id":           vless.RealityShortID,
		"uri":                vlessLink,
		"location":           config.Location,
		"connection_test":    config.ConnectionTest,
	}
	if vlessFlowEnabled(vless.Flow) {
		config.VLESS["flow"] = vless.Flow
	}

	cdnXHTTPAvailable := strings.TrimSpace(vless.CDNHost) != "" && vless.CDNXHTTPPort > 0 && vless.PublishCDNXHTTP
	if cdnXHTTPAvailable {
		cdnXHTTPLink := buildVLESSCDNXHTTPLink(vless, config.Grant.ID, location)
		links = append(links, cdnXHTTPLink)
		if !vless.PublishDirect {
			config.ConnectionURL = cdnXHTTPLink
			config.ShareURL = cdnXHTTPLink
		}
		config.VLESSCDNXHTTP = map[string]any{
			"client_id": config.Grant.ID,
			"label":     location,
			"protocol":  "vless",
			"security":  "tls",
			"network":   "xhttp",
			"server":    vless.CDNHost,
			"port":      vless.CDNXHTTPPort,
			"path":      vless.CDNXHTTPPath,
			"sni":       vless.CDNHost,
			"uri":       cdnXHTTPLink,
			"note":      "Try this one first — same CDN path as the WS link below, but shares one connection across requests so loading media/chat history is much faster.",
		}
	}
	if cdnAvailable {
		cdnLink := buildVLESSCDNLink(vless, config.Grant.ID, location)
		links = append(links, cdnLink)
		if !vless.PublishDirect && !cdnXHTTPAvailable {
			config.ConnectionURL = cdnLink
			config.ShareURL = cdnLink
		}
		config.VLESSCDN = map[string]any{
			"client_id": config.Grant.ID,
			"label":     location,
			"protocol":  "vless",
			"security":  "tls",
			"network":   "ws",
			"server":    vless.CDNHost,
			"port":      vless.CDNPort,
			"path":      vless.CDNWSPath,
			"sni":       vless.CDNHost,
			"uri":       cdnLink,
			"note":      "Routes through a CDN so it looks like ordinary HTTPS to your network — use this if the XHTTP link above doesn't connect.",
		}
	}

	if strings.TrimSpace(vless.DirectTLSHost) != "" && vless.DirectTLSPort > 0 {
		directLink := buildVLESSDirectTLSLink(vless, config.Grant.ID, location)
		links = append(links, directLink)
		if config.ConnectionURL == "" {
			config.ConnectionURL = directLink
			config.ShareURL = directLink
		}
		config.VLESSDirectTLS = map[string]any{
			"client_id": config.Grant.ID,
			"label":     location,
			"protocol":  "vless",
			"security":  "tls",
			"network":   "ws",
			"server":    vless.DirectTLSHost,
			"port":      vless.DirectTLSPort,
			"path":      vless.DirectTLSPath,
			"sni":       vless.DirectTLSHost,
			"uri":       directLink,
			"note":      "Direct connection with a real certificate, no CDN — try this first in VLESS/Trojan-only clients (Happ included): as fast as the direct connection gets, and a real TLS handshake instead of REALITY's camouflage.",
		}
	}

	if strings.TrimSpace(vless.HysteriaHost) != "" && vless.HysteriaPort > 0 {
		hyLink := buildHysteriaLink(vless, config.Grant.ID, location)
		links = append(links, hyLink)
		if config.ConnectionURL == "" {
			config.ConnectionURL = hyLink
			config.ShareURL = hyLink
		}
		config.Hysteria = map[string]any{
			"client_id": config.Grant.ID,
			"label":     location,
			"protocol":  "hysteria2",
			"server":    vless.HysteriaHost,
			"port":      vless.HysteriaPort,
			"insecure":  vless.HysteriaInsecure,
			"uri":       hyLink,
			"note":      "Direct connection, no CDN — fastest and most reliable option, but only works in clients that support Hysteria2 (not Happ; Karing and others do).",
		}
	}

	if strings.TrimSpace(vless.CDNHost) != "" && vless.CDNGRPCPort > 0 {
		grpcLink := buildVLESSCDNGRPCLink(vless, config.Grant.ID, location)
		links = append(links, grpcLink)
		config.VLESSCDNGRPC = map[string]any{
			"client_id":    config.Grant.ID,
			"label":        location,
			"protocol":     "vless",
			"security":     "tls",
			"network":      "grpc",
			"server":       vless.CDNHost,
			"port":         vless.CDNGRPCPort,
			"service_name": vless.CDNGRPCService,
			"sni":          vless.CDNHost,
			"uri":          grpcLink,
			"note":         "Try this one first — multiplexes requests over one connection like the CDN-XHTTP option, but gRPC is much more widely supported by client apps.",
		}
	}

	if strings.TrimSpace(vless.CDNHost) != "" && vless.TrojanCDNPort > 0 && vless.PublishTrojanCDN {
		trojanLink := buildTrojanCDNLink(vless, config.Grant.ID, location)
		links = append(links, trojanLink)
		config.TrojanCDN = map[string]any{
			"client_id": config.Grant.ID,
			"label":     location,
			"protocol":  "trojan",
			"security":  "tls",
			"network":   "ws",
			"server":    vless.CDNHost,
			"port":      vless.TrojanCDNPort,
			"path":      vless.TrojanCDNWSPath,
			"sni":       vless.CDNHost,
			"uri":       trojanLink,
			"note":      "A different protocol (Trojan, not VLESS) behind the same CDN — try this if a network specifically blocks VLESS traffic patterns.",
		}
	}

	if vless.PublishShadowsocks && vless.ShadowsocksPort > 0 {
		ssLink := buildShadowsocksLink(vless, config.Grant.ID, location)
		links = append(links, ssLink)
		config.Shadowsocks = map[string]any{
			"client_id": config.Grant.ID,
			"label":     location,
			"protocol":  "shadowsocks",
			"method":    vless.ShadowsocksMethod,
			"server":    vless.PublicHost,
			"port":      vless.ShadowsocksPort,
			"uri":       ssLink,
		}
	}
	config.Links = links
}

func smartRoutingPolicy() map[string]any {
	return map[string]any{
		"version":          1,
		"mode":             "smart_split",
		"default_action":   "protected",
		"fallback_action":  "protected",
		"required_feature": "smart-routing-v1",
		"direct": map[string]any{
			"private_networks": true,
			"domain_suffixes":  []string{".ru", ".рф", ".su"},
			"geosite":          []string{"ru"},
			"geoip":            []string{"ru"},
		},
		"dns": map[string]any{
			"strategy":           "follow_route",
			"direct_resolver":    "system",
			"protected_resolver": "https://1.1.1.1/dns-query",
			"prevent_leaks":      true,
		},
		"network": map[string]any{
			"ipv4":                     true,
			"ipv6":                     true,
			"block_unrouted_webrtc":    true,
			"reconnect_on_path_change": true,
		},
	}
}

// buildVLESSLink renders the primary VLESS+REALITY connection URI. This is
// the highest-throughput transport (XTLS Vision splice) and should be tried
// first by any client that lets the user pick or auto-select.
func buildVLESSLink(vless config.VLESSConfig, grantID, location string) string {
	label := fmt.Sprintf("%s (VLESS)", location)
	endpoint := net.JoinHostPort(vless.PublicHost, strconv.Itoa(vless.PublicPort))
	query := url.Values{}
	query.Set("type", "tcp")
	query.Set("security", "reality")
	query.Set("encryption", "none")
	query.Set("pbk", vless.RealityPublicKey)
	query.Set("fp", vless.Fingerprint)
	query.Set("sni", vless.RealityServerName)
	query.Set("sid", vless.RealityShortID)
	query.Set("spx", "/")
	if vlessFlowEnabled(vless.Flow) {
		query.Set("flow", vless.Flow)
		query.Set("packetEncoding", "xudp")
	}
	return fmt.Sprintf("vless://%s@%s?%s#%s", grantID, endpoint, query.Encode(), url.PathEscape(label))
}

// buildVLESSCDNLink renders VLESS over WebSocket+TLS pointed at the CDN
// domain rather than the VPS's own IP — the CDN (Cloudflare) terminates the
// visible TLS handshake with a real certificate for that domain and proxies
// the WebSocket connection to the origin, so nothing about the outer session
// looks unusual to a network that specifically fingerprints REALITY/XTLS.
func buildVLESSCDNLink(vless config.VLESSConfig, grantID, location string) string {
	label := fmt.Sprintf("%s (CDN)", location)
	endpoint := net.JoinHostPort(vless.CDNHost, strconv.Itoa(vless.CDNPort))
	wsPath := vless.CDNWSPath
	if wsPath == "" {
		wsPath = "/wvb-ws"
	}
	query := url.Values{}
	query.Set("type", "ws")
	query.Set("security", "tls")
	query.Set("encryption", "none")
	query.Set("host", vless.CDNHost)
	query.Set("sni", vless.CDNHost)
	query.Set("path", wsPath)
	return fmt.Sprintf("vless://%s@%s?%s#%s", grantID, endpoint, query.Encode(), url.PathEscape(label))
}

// buildVLESSCDNXHTTPLink is the XHTTP sibling of buildVLESSCDNLink: same CDN
// domain and TLS, but the app requests share one H2 connection to the edge
// instead of each opening its own WebSocket, which is what actually costs
// time once a CDN hop adds real per-connection latency.
func buildVLESSCDNXHTTPLink(vless config.VLESSConfig, grantID, location string) string {
	label := fmt.Sprintf("%s (CDN-XHTTP)", location)
	endpoint := net.JoinHostPort(vless.CDNHost, strconv.Itoa(vless.CDNXHTTPPort))
	path := vless.CDNXHTTPPath
	if path == "" {
		path = "/wvb-xh"
	}
	query := url.Values{}
	query.Set("type", "xhttp")
	query.Set("mode", "auto")
	query.Set("security", "tls")
	query.Set("encryption", "none")
	query.Set("host", vless.CDNHost)
	query.Set("sni", vless.CDNHost)
	query.Set("path", path)
	return fmt.Sprintf("vless://%s@%s?%s#%s", grantID, endpoint, query.Encode(), url.PathEscape(label))
}

// buildTrojanCDNLink renders a Trojan+WebSocket+TLS link behind the same CDN
// domain as the VLESS CDN transport. Trojan is a different protocol
// implementation from VLESS entirely (distinct wire format, distinct
// open-source codebase) — offering it alongside VLESS means a DPI signature
// tuned to one doesn't automatically catch both, without needing a second
// CDN domain or server.
func buildTrojanCDNLink(vless config.VLESSConfig, grantID, location string) string {
	label := fmt.Sprintf("%s (Trojan)", location)
	endpoint := net.JoinHostPort(vless.CDNHost, strconv.Itoa(vless.TrojanCDNPort))
	path := vless.TrojanCDNWSPath
	if path == "" {
		path = "/wvb-tr"
	}
	query := url.Values{}
	query.Set("type", "ws")
	query.Set("security", "tls")
	query.Set("host", vless.CDNHost)
	query.Set("sni", vless.CDNHost)
	query.Set("path", path)
	return fmt.Sprintf("trojan://%s@%s?%s#%s", grantID, endpoint, query.Encode(), url.PathEscape(label))
}

// buildVLESSCDNGRPCLink is the gRPC sibling of buildVLESSCDNLink — same CDN
// domain and TLS, but requests share one H2 connection to the edge instead
// of each opening its own WebSocket. gRPC has been in Xray-core (and in
// client apps) far longer than XHTTP, so it's the safer multiplexing option.
func buildVLESSCDNGRPCLink(vless config.VLESSConfig, grantID, location string) string {
	label := fmt.Sprintf("%s (CDN-gRPC)", location)
	endpoint := net.JoinHostPort(vless.CDNHost, strconv.Itoa(vless.CDNGRPCPort))
	service := vless.CDNGRPCService
	if service == "" {
		service = "wvb-grpc"
	}
	query := url.Values{}
	query.Set("type", "grpc")
	query.Set("security", "tls")
	query.Set("encryption", "none")
	query.Set("serviceName", service)
	query.Set("sni", vless.CDNHost)
	return fmt.Sprintf("vless://%s@%s?%s#%s", grantID, endpoint, query.Encode(), url.PathEscape(label))
}

// buildVLESSDirectTLSLink renders VLESS+WS+TLS pointed straight at the VPS's
// own domain (not the CDN one) with a real Let's Encrypt certificate — no
// REALITY camouflage, no CDN hop, just an ordinary, valid TLS handshake.
func buildVLESSDirectTLSLink(vless config.VLESSConfig, grantID, location string) string {
	label := fmt.Sprintf("%s (Direct-TLS)", location)
	endpoint := net.JoinHostPort(vless.DirectTLSHost, strconv.Itoa(vless.DirectTLSPort))
	path := vless.DirectTLSPath
	if path == "" {
		path = "/wvb-dt"
	}
	query := url.Values{}
	query.Set("type", "ws")
	query.Set("security", "tls")
	query.Set("encryption", "none")
	query.Set("host", vless.DirectTLSHost)
	query.Set("sni", vless.DirectTLSHost)
	query.Set("path", path)
	return fmt.Sprintf("vless://%s@%s?%s#%s", grantID, endpoint, query.Encode(), url.PathEscape(label))
}

// buildHysteriaLink renders a Hysteria2 URI. Unlike the other transports,
// this connects directly to the VPS's own IP — Hysteria2 is QUIC/UDP-native
// and Cloudflare's free tier can't proxy raw UDP, so there's no CDN to hide
// behind here. auth is "grantID:grantID" (see wavebreak-node's userpass
// config) so the grant ID alone is both username and password.
func buildHysteriaLink(vless config.VLESSConfig, grantID, location string) string {
	label := fmt.Sprintf("%s (Hysteria2)", location)
	endpoint := net.JoinHostPort(vless.HysteriaHost, strconv.Itoa(vless.HysteriaPort))
	auth := fmt.Sprintf("%s:%s", grantID, grantID)
	query := url.Values{}
	sni := vless.HysteriaSNI
	if sni == "" {
		sni = vless.HysteriaHost
	}
	query.Set("sni", sni)
	query.Set("alpn", "h3")
	// insecure=1 (skip cert validation) was needed for the earlier
	// self-signed cert; a real Let's Encrypt cert on a proper domain
	// doesn't need it — and some clients (Happ included) apparently don't
	// handle that flag correctly, connecting to nothing instead of falling
	// back to a real handshake.
	if vless.HysteriaInsecure {
		query.Set("insecure", "1")
	}
	return fmt.Sprintf("hysteria2://%s@%s/?%s#%s", auth, endpoint, query.Encode(), url.PathEscape(label))
}

func vlessFlowEnabled(flow string) bool {
	switch strings.ToLower(strings.TrimSpace(flow)) {
	case "", "none", "off", "false", "0":
		return false
	default:
		return true
	}
}

// buildShadowsocksLink renders a second, structurally different transport
// (plain Shadowsocks AEAD, no TLS/REALITY fingerprint at all) so a client
// has a fallback to try when a network specifically targets REALITY/Vision
// traffic patterns rather than blocking everything indiscriminately.
func buildShadowsocksLink(vless config.VLESSConfig, grantID, location string) string {
	label := fmt.Sprintf("%s (Shadowsocks)", location)
	userinfo := base64.StdEncoding.EncodeToString([]byte(vless.ShadowsocksMethod + ":" + grantID))
	endpoint := net.JoinHostPort(vless.PublicHost, strconv.Itoa(vless.ShadowsocksPort))
	return fmt.Sprintf("ss://%s@%s#%s", userinfo, endpoint, url.PathEscape(label))
}

func (s *Server) nodeUsageReport(w http.ResponseWriter, r *http.Request) {
	var req struct {
		GrantID        string `json:"grant_id"`
		BytesUpTotal   int64  `json:"bytes_up_total"`
		BytesDownTotal int64  `json:"bytes_down_total"`
		Timestamp      string `json:"timestamp"`
	}
	if !decodeJSON(w, r, &req) {
		return
	}
	if strings.TrimSpace(req.GrantID) == "" || req.BytesUpTotal < 0 || req.BytesDownTotal < 0 {
		writeError(w, http.StatusBadRequest, "grant_id and non-negative counters are required")
		return
	}
	reportedAt := time.Now().UTC()
	if req.Timestamp != "" {
		parsed, err := time.Parse(time.RFC3339Nano, req.Timestamp)
		if err != nil {
			writeError(w, http.StatusBadRequest, "timestamp must be RFC3339")
			return
		}
		reportedAt = parsed.UTC()
	}
	if err := s.app.Store.RecordNodeUsageReport(r.Context(), currentNode(r.Context()).ID, req.GrantID, req.BytesUpTotal, req.BytesDownTotal, reportedAt); errors.Is(err, store.ErrNotFound) {
		writeError(w, http.StatusNotFound, "active grant not found")
		return
	} else if err != nil {
		writeError(w, http.StatusInternalServerError, "could not record usage")
		return
	}
	writeJSON(w, http.StatusAccepted, map[string]string{"status": "accepted"})
}

func (s *Server) adminDashboard(w http.ResponseWriter, r *http.Request) {
	dashboard, err := s.app.Store.AdminDashboard(r.Context())
	if err != nil {
		writeError(w, http.StatusInternalServerError, "could not load admin dashboard")
		return
	}
	writeJSON(w, http.StatusOK, dashboard)
}

func (s *Server) adminUsers(w http.ResponseWriter, r *http.Request) {
	users, err := s.app.Store.ListUsers(r.Context())
	if err != nil {
		writeError(w, http.StatusInternalServerError, "could not list users")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"users": users})
}

func (s *Server) adminUpdateUserRole(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Role string `json:"role"`
	}
	if !decodeJSON(w, r, &req) {
		return
	}
	switch req.Role {
	case "user", "support", "admin", "superadmin":
	default:
		writeError(w, http.StatusBadRequest, "invalid role")
		return
	}
	userID := chi.URLParam(r, "userID")
	user, err := s.app.Store.AdminUpdateUserRole(r.Context(), userID, req.Role)
	if errors.Is(err, store.ErrNotFound) {
		writeError(w, http.StatusNotFound, "user not found")
		return
	}
	if err != nil {
		writeError(w, http.StatusBadRequest, "could not update user role")
		return
	}
	actor := currentUser(r.Context()).ID
	_ = s.app.Store.WriteAuditEvent(r.Context(), &actor, "user.role_updated", "user", &userID, map[string]any{"role": req.Role})
	writeJSON(w, http.StatusOK, user)
}

func (s *Server) adminDisableUser(w http.ResponseWriter, r *http.Request) {
	userID := chi.URLParam(r, "userID")
	user, err := s.app.Store.AdminSetUserDisabled(r.Context(), userID, true)
	if errors.Is(err, store.ErrNotFound) {
		writeError(w, http.StatusNotFound, "user not found")
		return
	}
	if err != nil {
		writeError(w, http.StatusInternalServerError, "could not disable user")
		return
	}
	actor := currentUser(r.Context()).ID
	_ = s.app.Store.WriteAuditEvent(r.Context(), &actor, "user.disabled", "user", &userID, nil)
	writeJSON(w, http.StatusOK, user)
}

func (s *Server) adminEnableUser(w http.ResponseWriter, r *http.Request) {
	userID := chi.URLParam(r, "userID")
	user, err := s.app.Store.AdminSetUserDisabled(r.Context(), userID, false)
	if errors.Is(err, store.ErrNotFound) {
		writeError(w, http.StatusNotFound, "user not found")
		return
	}
	if err != nil {
		writeError(w, http.StatusInternalServerError, "could not enable user")
		return
	}
	actor := currentUser(r.Context()).ID
	_ = s.app.Store.WriteAuditEvent(r.Context(), &actor, "user.enabled", "user", &userID, nil)
	writeJSON(w, http.StatusOK, user)
}

func (s *Server) adminDeleteUser(w http.ResponseWriter, r *http.Request) {
	userID := chi.URLParam(r, "userID")
	actor := currentUser(r.Context()).ID
	if userID == actor {
		writeError(w, http.StatusBadRequest, "cannot delete current user")
		return
	}
	_ = s.app.Store.WriteAuditEvent(r.Context(), &actor, "user.delete_requested", "user", &userID, map[string]any{"hard_delete": true})
	if err := s.app.Store.AdminDeleteUser(r.Context(), userID); errors.Is(err, store.ErrNotFound) {
		writeError(w, http.StatusNotFound, "user not found")
		return
	} else if err != nil {
		writeError(w, http.StatusInternalServerError, "could not delete user")
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "deleted"})
}

func (s *Server) adminTrafficHistory(w http.ResponseWriter, r *http.Request) {
	days := 30
	if raw := r.URL.Query().Get("days"); raw != "" {
		if parsed, err := strconv.Atoi(raw); err == nil && parsed > 0 && parsed <= 180 {
			days = parsed
		}
	}
	history, err := s.app.Store.AdminTrafficHistory(r.Context(), days)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "could not load traffic history")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"history": history})
}

// adminTrafficHealth answers "is anything still reporting usage" — a
// silently-dead node agent (crashed, mis-configured, stats API
// unreachable) leaves no error anywhere else in the system, so the admin
// UI polls this to raise its own alert instead of relying on someone
// noticing the traffic chart has gone flat.
func (s *Server) adminTrafficHealth(w http.ResponseWriter, r *http.Request) {
	lastReportAt, err := s.app.Store.LatestUsageReportAt(r.Context())
	if err != nil {
		writeError(w, http.StatusInternalServerError, "could not check traffic health")
		return
	}
	const staleAfterSeconds = 300 // 5x the node's default 60s report interval
	stale := true
	var secondsSince *int64
	if lastReportAt != nil {
		elapsed := int64(time.Since(*lastReportAt).Seconds())
		secondsSince = &elapsed
		stale = elapsed > staleAfterSeconds
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"last_report_at":    lastReportAt,
		"seconds_since":     secondsSince,
		"stale":             stale,
		"threshold_seconds": staleAfterSeconds,
	})
}

func (s *Server) adminPlans(w http.ResponseWriter, r *http.Request) {
	plans, err := s.app.Store.ListAllPlans(r.Context())
	if err != nil {
		writeError(w, http.StatusInternalServerError, "could not list plans")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"plans": plans})
}

func (s *Server) adminCreatePlan(w http.ResponseWriter, r *http.Request) {
	plan, ok := decodePlanRequest(w, r)
	if !ok {
		return
	}
	created, err := s.app.Store.CreatePlan(r.Context(), plan)
	if err != nil {
		writeError(w, http.StatusBadRequest, "could not create plan")
		return
	}
	actor := currentUser(r.Context()).ID
	_ = s.app.Store.WriteAuditEvent(r.Context(), &actor, "plan.created", "plan", &created.ID, map[string]any{"code": created.Code})
	writeJSON(w, http.StatusCreated, created)
}

func (s *Server) adminUpdatePlan(w http.ResponseWriter, r *http.Request) {
	plan, ok := decodePlanRequest(w, r)
	if !ok {
		return
	}
	plan.ID = chi.URLParam(r, "planID")
	updated, err := s.app.Store.UpdatePlan(r.Context(), plan)
	if errors.Is(err, store.ErrNotFound) {
		writeError(w, http.StatusNotFound, "plan not found")
		return
	}
	if err != nil {
		writeError(w, http.StatusBadRequest, "could not update plan")
		return
	}
	actor := currentUser(r.Context()).ID
	_ = s.app.Store.WriteAuditEvent(r.Context(), &actor, "plan.updated", "plan", &updated.ID, map[string]any{"code": updated.Code})
	writeJSON(w, http.StatusOK, updated)
}

func (s *Server) adminDeletePlan(w http.ResponseWriter, r *http.Request) {
	planID := chi.URLParam(r, "planID")
	err := s.app.Store.SoftDeletePlan(r.Context(), planID)
	if errors.Is(err, store.ErrNotFound) {
		writeError(w, http.StatusNotFound, "plan not found")
		return
	}
	if err != nil {
		writeError(w, http.StatusInternalServerError, "could not delete plan")
		return
	}
	actor := currentUser(r.Context()).ID
	_ = s.app.Store.WriteAuditEvent(r.Context(), &actor, "plan.deleted", "plan", &planID, map[string]any{"soft_delete": true})
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

func (s *Server) adminSubscriptions(w http.ResponseWriter, r *http.Request) {
	subscriptions, err := s.app.Store.ListAllSubscriptions(r.Context())
	if err != nil {
		writeError(w, http.StatusInternalServerError, "could not list subscriptions")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"subscriptions": subscriptions})
}

func (s *Server) adminCreateSubscription(w http.ResponseWriter, r *http.Request) {
	var req struct {
		UserID string `json:"user_id"`
		PlanID string `json:"plan_id"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || strings.TrimSpace(req.UserID) == "" || strings.TrimSpace(req.PlanID) == "" {
		writeError(w, http.StatusBadRequest, "user_id and plan_id are required")
		return
	}
	actor := currentUser(r.Context()).ID
	subscription, err := s.app.Store.CreateSubscriptionFor(r.Context(), req.UserID, req.PlanID, "admin", actor)
	if err != nil {
		writeError(w, http.StatusBadRequest, "could not create subscription")
		return
	}
	_ = s.app.Store.WriteAuditEvent(r.Context(), &actor, "subscription.created", "subscription", &subscription.ID, map[string]any{
		"user_id": req.UserID,
		"plan_id": req.PlanID,
		"source":  "admin",
	})
	writeJSON(w, http.StatusCreated, subscription)
}

func (s *Server) adminUpdateSubscriptionStatus(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Status string `json:"status"`
	}
	if !decodeJSON(w, r, &req) {
		return
	}
	switch req.Status {
	case "pending", "active", "expired", "cancelled", "suspended":
	default:
		writeError(w, http.StatusBadRequest, "invalid subscription status")
		return
	}
	subscription, err := s.app.Store.UpdateSubscriptionStatus(r.Context(), chi.URLParam(r, "subscriptionID"), req.Status)
	if errors.Is(err, store.ErrNotFound) {
		writeError(w, http.StatusNotFound, "subscription not found")
		return
	}
	if err != nil {
		writeError(w, http.StatusBadRequest, "could not update subscription")
		return
	}
	actor := currentUser(r.Context()).ID
	_ = s.app.Store.WriteAuditEvent(r.Context(), &actor, "subscription.status_updated", "subscription", &subscription.ID, map[string]any{"status": req.Status})
	writeJSON(w, http.StatusOK, subscription)
}

func (s *Server) adminDevices(w http.ResponseWriter, r *http.Request) {
	devices, err := s.app.Store.ListAllDevices(r.Context())
	if err != nil {
		writeError(w, http.StatusInternalServerError, "could not list devices")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"devices": devices})
}

func (s *Server) adminRevokeDevice(w http.ResponseWriter, r *http.Request) {
	deviceID := chi.URLParam(r, "deviceID")
	err := s.app.Store.AdminRevokeDevice(r.Context(), deviceID)
	if errors.Is(err, store.ErrNotFound) {
		writeError(w, http.StatusNotFound, "device not found")
		return
	}
	if err != nil {
		writeError(w, http.StatusInternalServerError, "could not revoke device")
		return
	}
	actor := currentUser(r.Context()).ID
	_ = s.app.Store.WriteAuditEvent(r.Context(), &actor, "device.revoked", "device", &deviceID, map[string]any{"reason": "admin"})
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

func (s *Server) adminTraffic(w http.ResponseWriter, r *http.Request) {
	rows, err := s.app.Store.ListTrafficRows(r.Context())
	if err != nil {
		writeError(w, http.StatusInternalServerError, "could not list traffic")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"traffic": rows})
}

func (s *Server) adminAudit(w http.ResponseWriter, r *http.Request) {
	events, err := s.app.Store.ListAuditEvents(r.Context())
	if err != nil {
		writeError(w, http.StatusInternalServerError, "could not list audit")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"events": events})
}

func (s *Server) adminAccessGrants(w http.ResponseWriter, r *http.Request) {
	grants, err := s.app.Store.ListAllAccessGrants(r.Context())
	if err != nil {
		writeError(w, http.StatusInternalServerError, "could not list grants")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"grants": grants})
}

func (s *Server) adminRevokeAccessGrant(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Reason string `json:"reason"`
	}
	if !decodeJSON(w, r, &req) {
		return
	}
	grant, err := s.app.Store.RevokeAccessGrant(r.Context(), "", chi.URLParam(r, "grantID"), strings.TrimSpace(req.Reason))
	if errors.Is(err, store.ErrNotFound) {
		writeError(w, http.StatusNotFound, "grant not found")
		return
	}
	if err != nil {
		writeError(w, http.StatusBadRequest, "could not revoke grant")
		return
	}
	actor := currentUser(r.Context()).ID
	_ = s.app.Store.WriteAuditEvent(r.Context(), &actor, "access_grant.revoked", "access_grant", &grant.ID, map[string]any{"reason": req.Reason})
	writeJSON(w, http.StatusOK, grant)
}

func (s *Server) botTelegramIdentify(w http.ResponseWriter, r *http.Request) {
	var req struct {
		ProviderUserID string         `json:"provider_user_id"`
		DisplayName    string         `json:"display_name"`
		Username       string         `json:"username"`
		LinkToken      string         `json:"link_token"`
		Metadata       map[string]any `json:"metadata"`
	}
	if !decodeJSON(w, r, &req) {
		return
	}
	if strings.TrimSpace(req.ProviderUserID) == "" {
		writeError(w, http.StatusBadRequest, "provider_user_id is required")
		return
	}
	var (
		user store.User
		err  error
	)
	if strings.TrimSpace(req.LinkToken) != "" {
		user, err = s.app.Store.LinkTelegramWithToken(r.Context(), strings.TrimSpace(req.LinkToken), strings.TrimSpace(req.ProviderUserID), strings.TrimSpace(req.DisplayName), strings.TrimSpace(req.Username), req.Metadata)
	} else {
		user, err = s.app.Store.UpsertTelegramIdentity(r.Context(), strings.TrimSpace(req.ProviderUserID), strings.TrimSpace(req.DisplayName), strings.TrimSpace(req.Username), req.Metadata)
	}
	if errors.Is(err, store.ErrNotFound) {
		writeError(w, http.StatusNotFound, "link token not found")
		return
	}
	if err != nil {
		writeError(w, http.StatusBadRequest, "could not identify telegram user")
		return
	}
	writeJSON(w, http.StatusOK, user)
}

func (s *Server) botUserOverview(w http.ResponseWriter, r *http.Request) {
	overview, err := s.app.Store.UserOverview(r.Context(), chi.URLParam(r, "userID"))
	if errors.Is(err, store.ErrNotFound) {
		writeError(w, http.StatusNotFound, "user not found")
		return
	}
	if err != nil {
		writeError(w, http.StatusInternalServerError, "could not load overview")
		return
	}
	writeJSON(w, http.StatusOK, overview)
}

func (s *Server) botAuthRequired(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		raw, ok := bearerToken(r)
		if !ok || s.app.Config.BotServiceToken == "" || raw != s.app.Config.BotServiceToken {
			writeError(w, http.StatusUnauthorized, "invalid bot service token")
			return
		}
		next.ServeHTTP(w, r)
	})
}

func parseIntQuery(r *http.Request, name string, fallback int) int {
	raw := r.URL.Query().Get(name)
	if raw == "" {
		return fallback
	}
	value, err := strconv.Atoi(raw)
	if err != nil || value <= 0 {
		return fallback
	}
	return value
}

func decodePlanRequest(w http.ResponseWriter, r *http.Request) (store.Plan, bool) {
	var req struct {
		Code                      string `json:"code"`
		Name                      string `json:"name"`
		Description               string `json:"description"`
		PriceMinor                int64  `json:"price_minor"`
		Currency                  string `json:"currency"`
		Interval                  string `json:"interval"`
		DurationDays              *int   `json:"duration_days"`
		DeviceLimit               int    `json:"device_limit"`
		TrafficLimitBytes         *int64 `json:"traffic_limit_bytes"`
		ConcurrentConnectionLimit *int   `json:"concurrent_connection_limit"`
		IsActive                  *bool  `json:"is_active"`
		IsPublic                  *bool  `json:"is_public"`
		SortOrder                 int    `json:"sort_order"`
	}
	if !decodeJSON(w, r, &req) {
		return store.Plan{}, false
	}
	req.Code = strings.ToLower(strings.TrimSpace(req.Code))
	req.Name = strings.TrimSpace(req.Name)
	req.Currency = strings.ToUpper(strings.TrimSpace(req.Currency))
	req.Interval = strings.TrimSpace(req.Interval)
	if req.Code == "" || req.Name == "" || req.PriceMinor < 0 || req.DeviceLimit < 1 {
		writeError(w, http.StatusBadRequest, "code, name, price_minor and device_limit are required")
		return store.Plan{}, false
	}
	if req.Currency == "" {
		req.Currency = "USD"
	}
	if req.Interval == "" {
		req.Interval = "month"
	}
	if req.Interval != "month" && req.Interval != "year" {
		writeError(w, http.StatusBadRequest, "interval must be month or year")
		return store.Plan{}, false
	}
	isActive := true
	if req.IsActive != nil {
		isActive = *req.IsActive
	}
	isPublic := true
	if req.IsPublic != nil {
		isPublic = *req.IsPublic
	}
	return store.Plan{
		Code:                      req.Code,
		Name:                      req.Name,
		Description:               req.Description,
		PriceMinor:                req.PriceMinor,
		Currency:                  req.Currency,
		Interval:                  req.Interval,
		DurationDays:              req.DurationDays,
		DeviceLimit:               req.DeviceLimit,
		TrafficLimitBytes:         req.TrafficLimitBytes,
		ConcurrentConnectionLimit: req.ConcurrentConnectionLimit,
		IsActive:                  isActive,
		IsPublic:                  isPublic,
		SortOrder:                 req.SortOrder,
	}, true
}
