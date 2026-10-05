package httpapi

import (
	"context"
	"crypto/rand"
	"encoding/json"
	"errors"
	"fmt"
	"math/big"
	"net/http"
	"strings"
	"time"

	"wavebreak-core/internal/mailer"
	"wavebreak-core/internal/observability"
	"wavebreak-core/internal/security"
	"wavebreak-core/internal/store"
)

// Email verification (apps from 1.2.0).
//
// An app that runs the verification step says so with the
// "email-verification" feature (X-Wavebreak-Features). Only then does a
// sign-up require it: the account is created, a 6-digit code is emailed,
// and no tokens are issued until POST /v1/auth/email/verify. Older apps
// and the website keep today's behaviour, and existing accounts are never
// locked out — they can confirm their address from the app's account
// screen (POST /v1/me/email/*). Everything is off while SMTP isn't
// configured.

const (
	featureEmailVerification = "email-verification"
	emailCodeTTL             = 15 * time.Minute
	emailCodeResendAfter     = 60 * time.Second
)

var errEmailCooldown = errors.New("a code was sent less than a minute ago")

// emailVerificationOn: this request comes from an app that can verify,
// and email can actually be sent.
func (s *Server) emailVerificationOn(r *http.Request) bool {
	return s.mail != nil && s.mail.Enabled() && clientFeatures(r)[featureEmailVerification]
}

func newEmailCode() (string, error) {
	n, err := rand.Int(rand.Reader, big.NewInt(1_000_000))
	if err != nil {
		return "", err
	}
	return fmt.Sprintf("%06d", n.Int64()), nil
}

// Bound to the user so a hash from one account is useless for another.
func emailCodeHash(userID, code string) string {
	return security.TokenHash("email-verify:" + userID + ":" + code)
}

// sendEmailCode creates a fresh code and emails it; within a minute of the
// previous one it does nothing and returns errEmailCooldown.
func (s *Server) sendEmailCode(ctx context.Context, userID, email, lang string) error {
	return s.sendCode(ctx, userID, func(code string) mailer.Message {
		return mailer.VerificationCode(lang, email, code, emailCodeTTL)
	})
}

func (s *Server) sendWelcome(userID, email, lang string) {
	// Detached from the request: the user already has their answer.
	go func() {
		ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
		defer cancel()
		if err := s.mail.Send(ctx, mailer.Welcome(lang, email)); err != nil {
			s.warn(ctx, "send welcome email", "user_id", userID, "error", err)
		}
	}()
}

func requestLanguage(r *http.Request, explicit string) string {
	if strings.TrimSpace(explicit) != "" {
		return mailer.Language(explicit)
	}
	return mailer.Language(r.Header.Get("Accept-Language"))
}

func writeEmailNotVerified(w http.ResponseWriter, email string) {
	writeJSON(w, http.StatusForbidden, map[string]any{
		"code":  "email_not_verified",
		"error": "email address is not verified",
		"email": email,
	})
}

// POST /v1/auth/email/verify {email, code} -> tokens.
func (s *Server) verifyEmail(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Email string `json:"email"`
		Code  string `json:"code"`
	}
	if !decodeJSON(w, r, &req) {
		return
	}
	user, err := s.app.Store.GetUserByEmail(r.Context(), req.Email)
	if err != nil || user.DisabledAt != nil || user.Status != "active" {
		writeError(w, http.StatusBadRequest, "invalid_code")
		return
	}
	state, err := s.app.Store.UserEmailState(r.Context(), user.ID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "email state lookup failed")
		return
	}
	// Tokens only ever follow a code that was just confirmed, and only for
	// an account that signed up through this flow. A verified account
	// signs in with its password; an old account confirms from the app.
	if !state.Required || state.Verified() {
		writeError(w, http.StatusBadRequest, "invalid_code")
		return
	}
	if !s.confirmCode(w, r, user.ID, req.Code) {
		return
	}
	s.sendWelcome(user.ID, user.Email, state.Language)
	observability.AuthLogin.Inc()
	_ = s.app.Store.RecordUserLogin(r.Context(), user.ID)
	tokens, err := s.issueTokens(r.Context(), user.ID, user.Email, user.Role)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "token issue failed")
		return
	}
	writeJSON(w, http.StatusOK, tokens)
}

// confirmCode checks a code and writes the error response itself.
func (s *Server) confirmCode(w http.ResponseWriter, r *http.Request, userID, code string) bool {
	code = strings.TrimSpace(code)
	err := s.app.Store.ConfirmEmailCode(r.Context(), userID, emailCodeHash(userID, code))
	switch {
	case err == nil:
		return true
	case errors.Is(err, store.ErrEmailCodeMismatch):
		writeError(w, http.StatusBadRequest, "invalid_code")
	case errors.Is(err, store.ErrEmailCodeExpired), errors.Is(err, store.ErrEmailCodeMissing):
		writeError(w, http.StatusBadRequest, "code_expired")
	case errors.Is(err, store.ErrEmailCodeLocked):
		writeError(w, http.StatusTooManyRequests, "too_many_attempts")
	default:
		writeError(w, http.StatusInternalServerError, "code check failed")
	}
	return false
}

// POST /v1/auth/email/resend {email}. Always 202 for an unknown or
// already-verified address, so it can't be used to probe for accounts.
func (s *Server) resendEmailCode(w http.ResponseWriter, r *http.Request) {
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
	user, err := s.app.Store.GetUserByEmail(r.Context(), req.Email)
	if err != nil || user.DisabledAt != nil || user.Status != "active" {
		writeJSON(w, http.StatusAccepted, map[string]any{"status": "sent"})
		return
	}
	state, err := s.app.Store.UserEmailState(r.Context(), user.ID)
	if err != nil || state.Verified() || !state.Required {
		writeJSON(w, http.StatusAccepted, map[string]any{"status": "sent"})
		return
	}
	lang := state.Language
	if strings.TrimSpace(req.Language) != "" {
		lang = mailer.Language(req.Language)
	}
	s.respondToSend(w, s.sendEmailCode(r.Context(), user.ID, user.Email, lang))
}

func (s *Server) respondToSend(w http.ResponseWriter, err error) {
	switch {
	case err == nil:
		writeJSON(w, http.StatusAccepted, map[string]any{"status": "sent", "resend_after_seconds": int(emailCodeResendAfter.Seconds())})
	case errors.Is(err, errEmailCooldown):
		writeJSON(w, http.StatusTooManyRequests, map[string]any{"code": "resend_too_soon", "error": err.Error(), "resend_after_seconds": int(emailCodeResendAfter.Seconds())})
	default:
		writeError(w, http.StatusBadGateway, "email_send_failed")
	}
}

// POST /v1/me/email/send-code — an existing account confirms its address.
func (s *Server) meSendEmailCode(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Language string `json:"language"`
	}
	// The body is optional.
	if r.ContentLength != 0 {
		_ = json.NewDecoder(r.Body).Decode(&req)
	}
	if s.mail == nil || !s.mail.Enabled() {
		writeError(w, http.StatusServiceUnavailable, "email_unavailable")
		return
	}
	user := currentUser(r.Context())
	state, err := s.app.Store.UserEmailState(r.Context(), user.ID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "email state lookup failed")
		return
	}
	if state.Verified() {
		writeError(w, http.StatusConflict, "already_verified")
		return
	}
	lang := requestLanguage(r, req.Language)
	if lang != state.Language {
		_ = s.app.Store.SetEmailLanguage(r.Context(), user.ID, lang)
	}
	s.respondToSend(w, s.sendEmailCode(r.Context(), user.ID, user.Email, lang))
}

// POST /v1/me/email/verify {code}.
func (s *Server) meVerifyEmail(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Code string `json:"code"`
	}
	if !decodeJSON(w, r, &req) {
		return
	}
	user := currentUser(r.Context())
	state, err := s.app.Store.UserEmailState(r.Context(), user.ID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "email state lookup failed")
		return
	}
	if !state.Verified() {
		if !s.confirmCode(w, r, user.ID, req.Code) {
			return
		}
	}
	writeJSON(w, http.StatusOK, map[string]any{"email_verified": true})
}

func (s *Server) warn(ctx context.Context, msg string, args ...any) {
	if s.app.Log != nil {
		s.app.Log.WarnContext(ctx, msg, args...)
	}
}
