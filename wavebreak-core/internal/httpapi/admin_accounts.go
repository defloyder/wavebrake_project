package httpapi

import (
	"encoding/json"
	"log/slog"
	"net/http"
	"strings"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"

	"wavebreak-core/internal/accounts"
	"wavebreak-core/internal/app"
)

// accountServices bundles the admin account-management use cases; the
// handlers below only translate HTTP <-> use case.
type accountServices struct {
	details   *accounts.UserDetailsService
	assign    *accounts.SubscriptionAssignmentService
	reset     *accounts.PasswordResetService
	urls      accounts.SubscriptionURLBuilder
	auditLog  accounts.AuditLog
	lifecycle *accounts.SubscriptionLifecycleService
}

func newAccountServices(a *app.App, notifier accounts.ResetNotifier) *accountServices {
	repo := a.Store.Accounts()
	cfg := a.Config.Accounts
	urls := accounts.NewSubscriptionURLBuilder(cfg.SubscriptionURLBase)
	details := accounts.NewUserDetailsService(repo, repo, repo, repo, urls)
	return &accountServices{
		details:   details,
		assign:    accounts.NewSubscriptionAssignmentService(repo, repo, repo, repo, repo, details, cfg.AccessProtocol),
		reset:     accounts.NewPasswordResetService(repo, repo, accounts.SecureTokenSource{}, notifier, accounts.Argon2Hasher{}, repo, cfg.PasswordResetURLBase, cfg.PasswordResetTTL),
		urls:      urls,
		auditLog:  repo,
		lifecycle: accounts.NewSubscriptionLifecycleService(repo, repo, cfg.SubscriptionGrace),
	}
}

// writeDomainError renders the admin domain error model:
// {"error": {"code", "message", "request_id"}}. Used by the account
// management endpoints only; older endpoints keep {"code","error"} because
// shipped mobile/desktop clients parse that shape.
func writeDomainError(w http.ResponseWriter, r *http.Request, err error) {
	de := accounts.AsDomainError(err)
	if de.Status >= 500 {
		slog.ErrorContext(r.Context(), "account management failure", "code", de.Code, "error", err, "request_id", middleware.GetReqID(r.Context()))
	}
	writeJSON(w, de.Status, map[string]any{
		"error": map[string]any{
			"code":       de.Code,
			"message":    de.Message,
			"request_id": middleware.GetReqID(r.Context()),
		},
	})
}

func actorFrom(r *http.Request) accounts.Actor {
	user := currentUser(r.Context())
	return accounts.Actor{UserID: user.ID, Role: user.Role, RequestID: middleware.GetReqID(r.Context())}
}

// GET /v1/admin/users/{userID}
func (s *Server) adminUserDetails(w http.ResponseWriter, r *http.Request) {
	details, err := s.accounts.details.Get(r.Context(), chi.URLParam(r, "userID"))
	if err != nil {
		writeDomainError(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, details)
}

// GET /v1/admin/users/{userID}/devices
func (s *Server) adminUserDevices(w http.ResponseWriter, r *http.Request) {
	details, err := s.accounts.details.Get(r.Context(), chi.URLParam(r, "userID"))
	if err != nil {
		writeDomainError(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, details.Devices)
}

// POST /v1/admin/users/{userID}/subscriptions {"plan_id": "..."}
func (s *Server) adminIssueUserSubscription(w http.ResponseWriter, r *http.Request) {
	var req struct {
		PlanID string `json:"plan_id"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || strings.TrimSpace(req.PlanID) == "" {
		writeJSON(w, http.StatusBadRequest, map[string]any{"error": map[string]any{
			"code": "VALIDATION_FAILED", "message": "plan_id is required.", "request_id": middleware.GetReqID(r.Context()),
		}})
		return
	}
	details, err := s.accounts.assign.Issue(r.Context(), actorFrom(r), chi.URLParam(r, "userID"), strings.TrimSpace(req.PlanID))
	if err != nil {
		writeDomainError(w, r, err)
		return
	}
	writeJSON(w, http.StatusCreated, details)
}

// POST /v1/admin/users/{userID}/access
// Issues the missing credential of the user's live subscription.
func (s *Server) adminIssueUserAccess(w http.ResponseWriter, r *http.Request) {
	details, err := s.accounts.assign.IssueAccess(r.Context(), actorFrom(r), chi.URLParam(r, "userID"))
	if err != nil {
		writeDomainError(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, details)
}

// POST /v1/admin/users/{userID}/password-reset
func (s *Server) adminRequestPasswordReset(w http.ResponseWriter, r *http.Request) {
	result, err := s.accounts.reset.Request(r.Context(), actorFrom(r), chi.URLParam(r, "userID"))
	if err != nil {
		writeDomainError(w, r, err)
		return
	}
	writeJSON(w, http.StatusAccepted, result)
}

// POST /v1/auth/password-reset/confirm {"token": "...", "password": "..."}
// Public: the token itself is the credential.
func (s *Server) confirmPasswordReset(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Token    string `json:"token"`
		Password string `json:"password"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]any{"error": map[string]any{
			"code": "VALIDATION_FAILED", "message": "Invalid request body.", "request_id": middleware.GetReqID(r.Context()),
		}})
		return
	}
	if err := s.accounts.reset.Confirm(r.Context(), req.Token, req.Password); err != nil {
		writeDomainError(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "password_updated"})
}
