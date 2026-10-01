package httpapi

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"strings"
	"time"

	"github.com/golang-jwt/jwt/v5"

	"wavebreak-core/internal/observability"
	"wavebreak-core/internal/security"
	"wavebreak-core/internal/store"
)

type contextKey string

const userContextKey contextKey = "wavebreak_user"
const nodeContextKey contextKey = "wavebreak_node"

type authUser struct {
	ID    string `json:"id"`
	Email string `json:"email"`
	Role  string `json:"role"`
}

type tokenPair struct {
	AccessToken  string `json:"access_token"`
	RefreshToken string `json:"refresh_token"`
	TokenType    string `json:"token_type"`
	ExpiresIn    int64  `json:"expires_in"`
}

func bearerToken(r *http.Request) (string, bool) {
	header := r.Header.Get("Authorization")
	raw, ok := strings.CutPrefix(header, "Bearer ")
	raw = strings.TrimSpace(raw)
	return raw, ok && raw != ""
}

func (s *Server) register(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Email    string `json:"email"`
		Password string `json:"password"`
		// Language of the emails ("ru", "en", ...; app language).
		Language string `json:"language"`
	}
	if !decodeJSON(w, r, &req) {
		return
	}
	req.Email = store.NormalizeEmail(req.Email)
	if req.Email == "" || len(req.Password) < 10 {
		writeError(w, http.StatusBadRequest, "email and password with at least 10 characters are required")
		return
	}
	hash, err := security.HashPassword(req.Password)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "password hashing failed")
		return
	}
	user, err := s.app.Store.CreateUser(r.Context(), req.Email, string(hash))
	if err != nil {
		writeError(w, http.StatusConflict, "user already exists")
		return
	}
	// An app with the verification step: no tokens until the emailed code
	// is confirmed (see email_verification.go).
	if s.emailVerificationOn(r) {
		lang := requestLanguage(r, req.Language)
		if err := s.app.Store.RequireEmailVerification(r.Context(), user.ID, lang); err != nil {
			writeError(w, http.StatusInternalServerError, "account setup failed")
			return
		}
		sendErr := s.sendEmailCode(r.Context(), user.ID, user.Email, lang)
		writeJSON(w, http.StatusCreated, map[string]any{
			"user":                  user,
			"verification_required": true,
			// false: the account exists but the email didn't go out; the
			// app offers "send again".
			"code_sent":            sendErr == nil,
			"resend_after_seconds": int(emailCodeResendAfter.Seconds()),
		})
		return
	}
	tokens, err := s.issueTokens(r.Context(), user.ID, user.Email, user.Role)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "token issue failed")
		return
	}
	writeJSON(w, http.StatusCreated, map[string]any{"user": user, "tokens": tokens})
}

func (s *Server) login(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Email    string `json:"email"`
		Password string `json:"password"`
	}
	if !decodeJSON(w, r, &req) {
		return
	}
	user, err := s.app.Store.GetUserByEmail(r.Context(), req.Email)
	if err != nil || user.DisabledAt != nil || user.Status != "active" || user.PasswordHash == "" {
		observability.AuthLoginFailed.Inc()
		writeError(w, http.StatusUnauthorized, "invalid credentials")
		return
	}
	ok, err := security.VerifyPassword(req.Password, user.PasswordHash)
	if err != nil || !ok {
		observability.AuthLoginFailed.Inc()
		writeError(w, http.StatusUnauthorized, "invalid credentials")
		return
	}
	// Signed up through the verification step but never confirmed: a
	// fresh code (unless one just went out) and no tokens yet. Only after
	// the password matched, so this doesn't reveal which emails exist.
	// Fail closed: if the state can't be read, no tokens (an unconfirmed
	// account must never slip through on a database error).
	state, err := s.app.Store.UserEmailState(r.Context(), user.ID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "login failed")
		return
	}
	if state.Required && !state.Verified() {
		if s.mail != nil && s.mail.Enabled() {
			_ = s.sendEmailCode(r.Context(), user.ID, user.Email, state.Language)
		}
		writeEmailNotVerified(w, user.Email)
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

func (s *Server) refresh(w http.ResponseWriter, r *http.Request) {
	var req struct {
		RefreshToken string `json:"refresh_token"`
	}
	if !decodeJSON(w, r, &req) {
		return
	}
	newRefresh, err := security.RandomToken(32)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "token issue failed")
		return
	}
	user, err := s.app.Store.RotateRefreshToken(r.Context(), req.RefreshToken, newRefresh, time.Now().UTC().Add(s.app.Config.RefreshTokenTTL))
	if errors.Is(err, store.ErrRefreshTokenReused) {
		writeError(w, http.StatusUnauthorized, "refresh token reuse detected")
		return
	}
	if err != nil {
		writeError(w, http.StatusUnauthorized, "invalid refresh token")
		return
	}
	access, err := s.issueAccessToken(user.ID, user.Email, user.Role)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "token issue failed")
		return
	}
	writeJSON(w, http.StatusOK, tokenPair{AccessToken: access, RefreshToken: newRefresh, TokenType: "Bearer", ExpiresIn: int64(s.app.Config.AccessTokenTTL.Seconds())})
}

func (s *Server) me(w http.ResponseWriter, r *http.Request) {
	user := currentUser(r.Context())
	// The user's fields as before, plus whether the address is confirmed
	// and whether it can be confirmed now (email is configured) — the app
	// shows its "confirm email" row from these.
	verified := false
	if state, err := s.app.Store.UserEmailState(r.Context(), user.ID); err == nil {
		verified = state.Verified()
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"id":                           user.ID,
		"email":                        user.Email,
		"role":                         user.Role,
		"email_verified":               verified,
		"email_verification_available": s.mail != nil && s.mail.Enabled(),
	})
}

func (s *Server) logout(w http.ResponseWriter, r *http.Request) {
	var req struct {
		RefreshToken string `json:"refresh_token"`
	}
	if !decodeJSON(w, r, &req) {
		return
	}
	if strings.TrimSpace(req.RefreshToken) == "" {
		writeError(w, http.StatusBadRequest, "refresh_token is required")
		return
	}
	if err := s.app.Store.RevokeRefreshToken(r.Context(), req.RefreshToken, "logout"); err != nil {
		writeError(w, http.StatusInternalServerError, "logout failed")
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

func (s *Server) issueTokens(ctx context.Context, userID, email, role string) (tokenPair, error) {
	access, err := s.issueAccessToken(userID, email, role)
	if err != nil {
		return tokenPair{}, err
	}
	refresh, err := security.RandomToken(32)
	if err != nil {
		return tokenPair{}, err
	}
	if err := s.app.Store.CreateSession(ctx, userID, refresh, time.Now().UTC().Add(s.app.Config.RefreshTokenTTL)); err != nil {
		return tokenPair{}, err
	}
	return tokenPair{AccessToken: access, RefreshToken: refresh, TokenType: "Bearer", ExpiresIn: int64(s.app.Config.AccessTokenTTL.Seconds())}, nil
}

func (s *Server) issueAccessToken(userID, email, role string) (string, error) {
	now := time.Now().UTC()
	claims := jwt.MapClaims{
		"sub":   userID,
		"email": email,
		"role":  role,
		"iat":   now.Unix(),
		"exp":   now.Add(s.app.Config.AccessTokenTTL).Unix(),
		"iss":   "wavebreak-core",
	}
	return jwt.NewWithClaims(jwt.SigningMethodHS256, claims).SignedString([]byte(s.app.Config.JWTSecret))
}

func (s *Server) authRequired(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		raw, ok := bearerToken(r)
		if !ok {
			writeError(w, http.StatusUnauthorized, "missing bearer token")
			return
		}
		token, err := jwt.Parse(raw, func(token *jwt.Token) (any, error) {
			if token.Method != jwt.SigningMethodHS256 {
				return nil, errors.New("unexpected signing method")
			}
			return []byte(s.app.Config.JWTSecret), nil
		})
		if err != nil || !token.Valid {
			writeError(w, http.StatusUnauthorized, "invalid bearer token")
			return
		}
		claims, ok := token.Claims.(jwt.MapClaims)
		if !ok {
			writeError(w, http.StatusUnauthorized, "invalid bearer claims")
			return
		}
		user := authUser{
			ID:    stringClaim(claims, "sub"),
			Email: stringClaim(claims, "email"),
			Role:  stringClaim(claims, "role"),
		}
		if user.ID == "" {
			writeError(w, http.StatusUnauthorized, "invalid bearer subject")
			return
		}
		dbUser, err := s.app.Store.GetUserByID(r.Context(), user.ID)
		if err != nil || dbUser.DisabledAt != nil || dbUser.Status != "active" {
			writeError(w, http.StatusUnauthorized, "user is disabled")
			return
		}
		user.Role = dbUser.Role
		ctx := context.WithValue(r.Context(), userContextKey, user)
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}

func (s *Server) nodeAuthRequired(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		raw, ok := bearerToken(r)
		if !ok {
			writeError(w, http.StatusUnauthorized, "missing node bearer token")
			return
		}
		node, err := s.app.Store.GetNodeByAPIToken(r.Context(), raw)
		if err != nil {
			writeError(w, http.StatusUnauthorized, "invalid node token")
			return
		}
		ctx := context.WithValue(r.Context(), nodeContextKey, node)
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}

func (s *Server) requireRole(roles ...string) func(http.Handler) http.Handler {
	allowed := map[string]struct{}{}
	for _, role := range roles {
		allowed[role] = struct{}{}
	}
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			user := currentUser(r.Context())
			if _, ok := allowed[user.Role]; !ok {
				writeError(w, http.StatusForbidden, "insufficient permissions")
				return
			}
			next.ServeHTTP(w, r)
		})
	}
}

func currentUser(ctx context.Context) authUser {
	user, _ := ctx.Value(userContextKey).(authUser)
	return user
}

func currentNode(ctx context.Context) store.Node {
	node, _ := ctx.Value(nodeContextKey).(store.Node)
	return node
}

func stringClaim(claims jwt.MapClaims, key string) string {
	value, _ := claims[key].(string)
	return value
}

func decodeJSON(w http.ResponseWriter, r *http.Request, dst any) bool {
	defer r.Body.Close()
	decoder := json.NewDecoder(r.Body)
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(dst); err != nil {
		writeError(w, http.StatusBadRequest, "invalid json body")
		return false
	}
	return true
}
