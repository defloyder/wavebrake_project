package httpapi

import (
	"encoding/base64"
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
	userinfo := "upload=0; download=0"
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

	vlessLink := buildVLESSLink(vless, config.Grant.ID, location)
	config.Location = locationPayload(config.Node)
	config.ConnectionTest = s.connectionTestPayload(config.Node)
	links = append(links, vlessLink)
	config.ConnectionURL = vlessLink
	config.ShareURL = vlessLink
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
