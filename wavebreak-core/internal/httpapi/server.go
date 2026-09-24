package httpapi

import (
	"encoding/json"
	"errors"
	"net/http"
	"strings"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
	"github.com/prometheus/client_golang/prometheus/promhttp"

	"wavebreak-core/internal/app"
	"wavebreak-core/internal/observability"
	"wavebreak-core/internal/security"
	"wavebreak-core/internal/store"
)

type Server struct {
	app *app.App
}

func New(app *app.App) http.Handler {
	s := &Server{app: app}
	r := chi.NewRouter()
	r.Use(middleware.RequestID)
	r.Use(middleware.RealIP)
	r.Use(middleware.Recoverer)
	r.Use(observability.MetricsMiddleware)

	r.Get("/healthz", s.health)
	r.Get("/readyz", s.ready)
	r.Handle("/metrics", promhttp.Handler())

	r.Route("/v1", func(r chi.Router) {
		r.Post("/auth/register", s.register)
		r.Post("/auth/login", s.login)
		r.Post("/auth/refresh", s.refresh)
		r.Post("/auth/logout", s.logout)
		r.Get("/plans", s.listPlans)
		r.Post("/node/enroll", s.nodeEnrollWithToken)
		r.Get("/sub/{grantID}", s.subscriptionByGrant)

		r.Group(func(r chi.Router) {
			r.Use(s.nodeAuthRequired)
			r.Post("/node/heartbeat", s.nodeSelfHeartbeat)
			r.Post("/node/usage", s.nodeUsageReport)
			r.Get("/node/state", s.nodeDesiredState)
			r.Post("/node/state/ack", s.nodeAckDesiredState)
			r.Post("/node/state/fail", s.nodeFailDesiredState)
		})

		r.Group(func(r chi.Router) {
			r.Use(s.authRequired)
			r.Get("/me", s.me)
			r.Get("/client/bootstrap", s.clientBootstrap)
			r.Get("/me/overview", s.meOverview)
			r.Get("/me/identities", s.meIdentities)
			r.Post("/me/identities/telegram/link", s.createTelegramLink)
			r.Delete("/me/identities/telegram", s.unlinkTelegram)
			r.Get("/me/usage", s.meUsage)
			r.Get("/me/usage/history", s.meUsageHistory)
			r.Get("/me/devices", s.listDevices)
			r.Post("/me/devices", s.createDevice)
			r.Patch("/me/devices/{deviceID}", s.updateDevice)
			r.Delete("/me/devices/{deviceID}", s.revokeDevice)
			r.Post("/subscriptions", s.createSubscription)
			r.Get("/subscriptions/current", s.currentSubscription)
			r.Get("/locations", s.listNodes)
			r.Get("/access/grants", s.listAccessGrants)
			r.Post("/access/grants", s.createAccessGrant)
			r.Get("/access/grants/{grantID}/config", s.accessGrantConfig)
			r.Post("/access/grants/{grantID}/revoke", s.revokeAccessGrant)
		})

		r.Group(func(r chi.Router) {
			r.Use(s.authRequired)
			r.Use(s.requireRole("support", "admin", "superadmin"))
			r.Get("/nodes", s.listNodes)
		})

		r.Group(func(r chi.Router) {
			r.Use(s.authRequired)
			r.Use(s.requireRole("admin", "superadmin"))
			r.Post("/nodes/enroll", s.enrollNode)
			r.Post("/nodes/{nodeID}/desired-state", s.createNodeDesiredState)
			r.Get("/admin/dashboard", s.adminDashboard)
			r.Get("/admin/users", s.adminUsers)
			r.Patch("/admin/users/{userID}/role", s.adminUpdateUserRole)
			r.Post("/admin/users/{userID}/disable", s.adminDisableUser)
			r.Post("/admin/users/{userID}/enable", s.adminEnableUser)
			r.With(s.requireRole("superadmin")).Delete("/admin/users/{userID}", s.adminDeleteUser)
			r.Get("/admin/plans", s.adminPlans)
			r.Post("/admin/plans", s.adminCreatePlan)
			r.Put("/admin/plans/{planID}", s.adminUpdatePlan)
			r.Delete("/admin/plans/{planID}", s.adminDeletePlan)
			r.Get("/admin/subscriptions", s.adminSubscriptions)
			r.Post("/admin/subscriptions", s.adminCreateSubscription)
			r.Post("/admin/subscriptions/manual", s.adminCreateManualSubscription)
			r.Patch("/admin/subscriptions/{subscriptionID}", s.adminEditSubscription)
			r.Patch("/admin/subscriptions/{subscriptionID}/status", s.adminUpdateSubscriptionStatus)
			r.Post("/admin/subscriptions/{subscriptionID}/reset-usage", s.adminResetSubscriptionUsage)
			r.Post("/admin/subscriptions/{subscriptionID}/reissue", s.adminReissueSubscription)
			r.Post("/admin/subscriptions/{subscriptionID}/delete", s.adminDeleteSubscription)
			r.Get("/admin/devices", s.adminDevices)
			r.Post("/admin/devices/{deviceID}/revoke", s.adminRevokeDevice)
			r.Get("/admin/traffic", s.adminTraffic)
			r.Get("/admin/traffic/history", s.adminTrafficHistory)
			r.Get("/admin/traffic/health", s.adminTrafficHealth)
			r.Get("/admin/audit", s.adminAudit)
			r.Get("/admin/access/grants", s.adminAccessGrants)
			r.Post("/admin/access/grants/{grantID}/revoke", s.adminRevokeAccessGrant)
		})

		r.Group(func(r chi.Router) {
			r.Use(s.botAuthRequired)
			r.Post("/bot/telegram/identify", s.botTelegramIdentify)
			r.Get("/bot/users/{userID}/overview", s.botUserOverview)
		})
	})

	return r
}

func (s *Server) health(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok", "service": "wavebreak-core"})
}

func (s *Server) ready(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	if err := s.app.Store.Ping(ctx); err != nil {
		writeError(w, http.StatusServiceUnavailable, "database unavailable")
		return
	}
	if s.app.Redis != nil {
		if err := s.app.Redis.Ping(ctx); err != nil {
			observability.RedisErrors.Inc()
			writeError(w, http.StatusServiceUnavailable, "redis unavailable")
			return
		}
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "ready"})
}

func (s *Server) listPlans(w http.ResponseWriter, r *http.Request) {
	plans, err := s.app.Store.ListPlans(r.Context())
	if err != nil {
		writeError(w, http.StatusInternalServerError, "could not list plans")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"plans": plans})
}

func (s *Server) createSubscription(w http.ResponseWriter, r *http.Request) {
	var req struct {
		PlanID string `json:"plan_id"`
	}
	if !decodeJSON(w, r, &req) {
		return
	}
	sub, err := s.app.Store.CreateSubscription(r.Context(), currentUser(r.Context()).ID, req.PlanID)
	if err != nil {
		writeError(w, http.StatusBadRequest, "could not create subscription")
		return
	}
	writeJSON(w, http.StatusCreated, sub)
}

func (s *Server) currentSubscription(w http.ResponseWriter, r *http.Request) {
	sub, err := s.app.Store.GetActiveSubscription(r.Context(), currentUser(r.Context()).ID)
	if errors.Is(err, store.ErrNotFound) {
		writeError(w, http.StatusNotFound, "subscription not found")
		return
	}
	if err != nil {
		writeError(w, http.StatusInternalServerError, "could not load subscription")
		return
	}
	writeJSON(w, http.StatusOK, sub)
}

func (s *Server) enrollNode(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Code   string `json:"code"`
		Region string `json:"region"`
	}
	if !decodeJSON(w, r, &req) {
		return
	}
	node, err := s.app.Store.EnrollNode(r.Context(), req.Code, req.Region)
	if err != nil {
		writeError(w, http.StatusBadRequest, "could not enroll node")
		return
	}
	writeJSON(w, http.StatusCreated, node)
}

func (s *Server) nodeEnrollWithToken(w http.ResponseWriter, r *http.Request) {
	token, ok := bearerToken(r)
	if !ok {
		writeError(w, http.StatusUnauthorized, "missing enrollment bearer token")
		return
	}
	var req struct {
		Code string `json:"code"`
	}
	if !decodeJSON(w, r, &req) {
		return
	}
	nodeToken, err := security.RandomToken(32)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "node token issue failed")
		return
	}
	node, err := s.app.Store.EnrollNodeWithToken(r.Context(), req.Code, token, nodeToken)
	if errors.Is(err, store.ErrNotFound) {
		writeError(w, http.StatusUnauthorized, "invalid enrollment token")
		return
	}
	if err != nil {
		writeError(w, http.StatusBadRequest, "could not enroll node")
		return
	}
	writeJSON(w, http.StatusCreated, map[string]any{"node": node, "node_api_token": nodeToken})
}

func (s *Server) nodeHeartbeat(w http.ResponseWriter, r *http.Request) {
	nodeID := chi.URLParam(r, "nodeID")
	node, err := s.app.Store.RecordHeartbeat(r.Context(), nodeID)
	if errors.Is(err, store.ErrNotFound) {
		writeError(w, http.StatusNotFound, "node not found")
		return
	}
	if err != nil {
		writeError(w, http.StatusInternalServerError, "could not record heartbeat")
		return
	}
	if s.app.Redis != nil && node.LastHeartbeatAt != nil {
		if err := s.app.Redis.SaveNodeHeartbeat(r.Context(), node.ID, *node.LastHeartbeatAt); err != nil {
			observability.RedisErrors.Inc()
		}
	}
	writeJSON(w, http.StatusOK, node)
}

func (s *Server) nodeSelfHeartbeat(w http.ResponseWriter, r *http.Request) {
	node := currentNode(r.Context())
	updated, err := s.app.Store.RecordHeartbeat(r.Context(), node.ID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "could not record heartbeat")
		return
	}
	if s.app.Redis != nil && updated.LastHeartbeatAt != nil {
		if err := s.app.Redis.SaveNodeHeartbeat(r.Context(), updated.ID, *updated.LastHeartbeatAt); err != nil {
			observability.RedisErrors.Inc()
		}
	}
	writeJSON(w, http.StatusOK, updated)
}

func (s *Server) createNodeDesiredState(w http.ResponseWriter, r *http.Request) {
	nodeID := chi.URLParam(r, "nodeID")
	var req struct {
		State json.RawMessage `json:"state"`
	}
	if !decodeJSON(w, r, &req) {
		return
	}
	if len(req.State) == 0 {
		req.State = json.RawMessage(`{}`)
	}
	state, err := s.app.Store.CreateDesiredState(r.Context(), nodeID, req.State)
	if err != nil {
		writeError(w, http.StatusBadRequest, "could not create desired state")
		return
	}
	writeJSON(w, http.StatusCreated, state)
}

func (s *Server) nodeDesiredState(w http.ResponseWriter, r *http.Request) {
	node := currentNode(r.Context())
	state, err := s.app.Store.LatestDesiredState(r.Context(), node.ID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "could not load desired state")
		return
	}
	writeJSON(w, http.StatusOK, state)
}

func (s *Server) nodeAckDesiredState(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Revision int `json:"revision"`
	}
	if !decodeJSON(w, r, &req) {
		return
	}
	if req.Revision < 0 {
		writeError(w, http.StatusBadRequest, "revision must be non-negative")
		return
	}
	node := currentNode(r.Context())
	if err := s.app.Store.AckDesiredState(r.Context(), node.ID, req.Revision); err != nil {
		writeError(w, http.StatusBadRequest, "could not ack desired state")
		return
	}
	observability.NodeSync.WithLabelValues("ack").Inc()
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

func (s *Server) nodeFailDesiredState(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Revision int    `json:"revision"`
		Error    string `json:"error"`
	}
	if !decodeJSON(w, r, &req) {
		return
	}
	if req.Revision < 0 || strings.TrimSpace(req.Error) == "" {
		writeError(w, http.StatusBadRequest, "revision and error are required")
		return
	}
	node := currentNode(r.Context())
	if err := s.app.Store.FailDesiredState(r.Context(), node.ID, req.Revision, req.Error); err != nil {
		writeError(w, http.StatusBadRequest, "could not report desired state failure")
		return
	}
	observability.NodeSyncFailures.Inc()
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

func (s *Server) listNodes(w http.ResponseWriter, r *http.Request) {
	nodes, err := s.app.Store.ListNodes(r.Context())
	if err != nil {
		writeError(w, http.StatusInternalServerError, "could not list nodes")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"nodes": nodes, "locations": s.locationPayloads(nodes)})
}

func (s *Server) createAccessGrant(w http.ResponseWriter, r *http.Request) {
	var req struct {
		NodeID   string `json:"node_id"`
		Protocol string `json:"protocol"`
		DeviceID string `json:"device_id"`
	}
	if !decodeJSON(w, r, &req) {
		return
	}
	if req.Protocol == "" {
		req.Protocol = "wireguard"
	}
	userID := currentUser(r.Context()).ID
	if _, err := s.app.Store.GetActiveSubscription(r.Context(), userID); err != nil {
		writeError(w, http.StatusForbidden, "active subscription is required")
		return
	}
	grant, err := s.app.Store.CreateAccessGrant(r.Context(), userID, req.NodeID, req.Protocol, req.DeviceID, time.Now().UTC().Add(30*24*time.Hour))
	if errors.Is(err, store.ErrLimitReached) {
		writeError(w, http.StatusForbidden, "TRAFFIC_LIMIT_REACHED")
		return
	}
	if err != nil {
		writeError(w, http.StatusBadRequest, "could not create access grant")
		return
	}
	writeJSON(w, http.StatusCreated, grant)
}

func (s *Server) listAccessGrants(w http.ResponseWriter, r *http.Request) {
	grants, err := s.app.Store.ListAccessGrants(r.Context(), currentUser(r.Context()).ID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "could not list access grants")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"grants": grants})
}

func writeJSON(w http.ResponseWriter, status int, payload any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(payload)
}

func writeError(w http.ResponseWriter, status int, message string) {
	writeJSON(w, status, map[string]any{"error": message, "code": message})
}
