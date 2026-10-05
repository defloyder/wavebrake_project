package httpapi

import (
	"context"
	"net/http"
	"strings"
	"time"

	"wavebreak-core/internal/mailer"
	"wavebreak-core/internal/observability"
	"wavebreak-core/internal/store"
)

// Sign-in with a one-time code sent to the email (apps from the V5
// redesign, the "Почта" button). Only for existing accounts — a new
// account still signs up with a password. Uses the same one-pending-code
// table, cooldown and attempt limit as email verification, so a code
// proves the mailbox either way; a successful sign-in also marks the
// address as confirmed.

// POST /v1/auth/email/login-code/request {email, language}. Always 202
// for an unknown or disabled address, so it can't probe for accounts.
func (s *Server) requestLoginCode(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Email    string `json:"email"`
		Language string `json:"language"`
	}
	if !decodeJSON(w, r, &req) {
		return
	}
	if s.mail == nil || !s.mail.Enabled() {
		writeError(w, http.StatusServiceUnavailable, "email_unavailable")
		return
	}
	normalized := store.NormalizeEmail(req.Email)
	if !checkEmailRateLimit(r.Context(), s.limiter, "login", normalized, s.app.Config.RateLimit.LoginEmailLimit, s.app.Config.RateLimit.LoginEmailWindow) {
		writeError(w, http.StatusTooManyRequests, "too many login attempts for this account, please try again later")
		return
	}
	user, err := s.app.Store.GetUserByEmail(r.Context(), req.Email)
	if err != nil || user.DisabledAt != nil || user.Status != "active" {
		writeJSON(w, http.StatusAccepted, map[string]any{"status": "sent", "resend_after_seconds": int(emailCodeResendAfter.Seconds())})
		return
	}
	lang := requestLanguage(r, req.Language)
	if state, err := s.app.Store.UserEmailState(r.Context(), user.ID); err == nil && strings.TrimSpace(req.Language) == "" {
		lang = state.Language
	}
	s.respondToSend(w, s.sendCode(r.Context(), user.ID, func(code string) mailer.Message {
		return mailer.LoginCode(lang, user.Email, code, emailCodeTTL)
	}))
}

// POST /v1/auth/email/login-code/confirm {email, code} -> tokens.
func (s *Server) confirmLoginCode(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Email string `json:"email"`
		Code  string `json:"code"`
	}
	if !decodeJSON(w, r, &req) {
		return
	}
	normalized := store.NormalizeEmail(req.Email)
	if !checkEmailRateLimit(r.Context(), s.limiter, "login", normalized, s.app.Config.RateLimit.LoginEmailLimit, s.app.Config.RateLimit.LoginEmailWindow) {
		writeError(w, http.StatusTooManyRequests, "too many login attempts for this account, please try again later")
		return
	}
	user, err := s.app.Store.GetUserByEmail(r.Context(), req.Email)
	if err != nil || user.DisabledAt != nil || user.Status != "active" {
		observability.AuthLoginFailed.Inc()
		writeError(w, http.StatusBadRequest, "invalid_code")
		return
	}
	if !s.confirmCode(w, r, user.ID, req.Code) {
		observability.AuthLoginFailed.Inc()
		return
	}
	observability.AuthLogin.Inc()
	_ = s.app.Store.RecordUserLogin(r.Context(), user.ID)
	tokens, err := s.issueTokens(r.Context(), user.ID, user.Email, user.Role)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "token issue failed")
		return
	}
	writeJSON(w, http.StatusOK, tokens)
}

// sendCode creates a fresh code and mails what [compose] builds from it;
// within a minute of the previous code it does nothing and returns
// errEmailCooldown.
func (s *Server) sendCode(ctx context.Context, userID string, compose func(code string) mailer.Message) error {
	sentAt, err := s.app.Store.EmailCodeSentAt(ctx, userID)
	if err != nil {
		return err
	}
	if !sentAt.IsZero() && time.Since(sentAt) < emailCodeResendAfter {
		return errEmailCooldown
	}
	code, err := newEmailCode()
	if err != nil {
		return err
	}
	if err := s.app.Store.SaveEmailCode(ctx, userID, emailCodeHash(userID, code), time.Now().Add(emailCodeTTL)); err != nil {
		return err
	}
	if err := s.mail.Send(ctx, compose(code)); err != nil {
		s.warn(ctx, "send code email", "error", err)
		return err
	}
	return nil
}
