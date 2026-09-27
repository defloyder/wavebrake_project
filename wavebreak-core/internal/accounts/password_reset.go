package accounts

import (
	"context"
	"errors"
	"net/url"
	"strings"
	"time"
)

// ResetResult is what an admin sees after requesting a reset. It never
// contains the token or the link.
type ResetResult struct {
	Status    string    `json:"status"`
	Channel   string    `json:"channel"`
	Delivery  string    `json:"delivery"`
	ExpiresAt time.Time `json:"expires_at"`
}

// TokenSource generates a random token and its storable hash.
type TokenSource interface {
	New() (token, hash string, err error)
	Hash(token string) string
}

// PasswordResetService implements the reset flow: a one-time, short-lived
// token whose hash alone is stored; the link goes only to the notifier.
type PasswordResetService struct {
	users    UserRepository
	tokens   PasswordResetRepository
	source   TokenSource
	notifier ResetNotifier
	hasher   PasswordHasher
	audit    AuditLog
	urlBase  string
	ttl      time.Duration
	now      func() time.Time
}

const DefaultPasswordResetURLBase = "https://wavebreak.com.tr/reset-password"

func NewPasswordResetService(users UserRepository, tokens PasswordResetRepository, source TokenSource, notifier ResetNotifier, hasher PasswordHasher, audit AuditLog, urlBase string, ttl time.Duration) *PasswordResetService {
	if strings.TrimSpace(urlBase) == "" {
		urlBase = DefaultPasswordResetURLBase
	}
	if ttl <= 0 {
		ttl = time.Hour
	}
	return &PasswordResetService{users: users, tokens: tokens, source: source, notifier: notifier, hasher: hasher, audit: audit, urlBase: urlBase, ttl: ttl, now: time.Now}
}

// Request creates a reset token for the user and hands the link to the
// notifier. A user without an email has no channel to receive it.
func (s *PasswordResetService) Request(ctx context.Context, actor Actor, userID string) (ResetResult, error) {
	user, err := s.users.UserByID(ctx, userID)
	if errors.Is(err, ErrNotFound) {
		return ResetResult{}, errUserNotFound()
	} else if err != nil {
		return ResetResult{}, wrapInternal(CodeInternal, "Could not load user.", err)
	}
	if strings.TrimSpace(user.Email) == "" {
		return ResetResult{}, errResetChannel()
	}

	token, hash, err := s.source.New()
	if err != nil {
		return ResetResult{}, wrapInternal(CodePasswordResetFailed, "Reset link could not be created.", err)
	}
	expiresAt := s.now().UTC().Add(s.ttl)
	if err := s.tokens.CreateResetToken(ctx, user.ID, hash, "email", actor.UserID, expiresAt); err != nil {
		return ResetResult{}, wrapInternal(CodePasswordResetFailed, "Reset link could not be created.", err)
	}

	delivery, err := s.notifier.SendPasswordReset(ctx, user.Email, s.resetURL(token), expiresAt)
	if err != nil {
		delivery = "failed"
	}

	_ = s.audit.Record(ctx, AuditEntry{
		Actor: actor, TargetUserID: user.ID, Action: AuditPasswordResetRequested,
		ResourceType: "user", ResourceID: user.ID,
		Metadata: map[string]any{"channel": "email", "delivery": delivery, "expires_at": expiresAt.Format(time.RFC3339)},
	})
	return ResetResult{Status: "reset_link_created", Channel: "email", Delivery: delivery, ExpiresAt: expiresAt}, nil
}

// Confirm consumes a token (once, before expiry) and sets a new password.
func (s *PasswordResetService) Confirm(ctx context.Context, token, newPassword string) error {
	if len(newPassword) < 10 {
		return errWeakPassword()
	}
	if strings.TrimSpace(token) == "" {
		return errResetToken()
	}
	hash, algo, err := s.hasher.Hash(newPassword)
	if err != nil {
		return wrapInternal(CodePasswordResetFailed, "Password could not be updated.", err)
	}
	userID, err := s.tokens.ConsumeResetToken(ctx, s.source.Hash(token), hash, algo, s.now().UTC())
	if errors.Is(err, ErrNotFound) {
		return errResetToken()
	} else if err != nil {
		return wrapInternal(CodePasswordResetFailed, "Password could not be updated.", err)
	}
	_ = s.audit.Record(ctx, AuditEntry{
		Actor: Actor{UserID: userID}, TargetUserID: userID, Action: AuditPasswordResetCompleted,
		ResourceType: "user", ResourceID: userID,
	})
	return nil
}

func (s *PasswordResetService) resetURL(token string) string {
	sep := "?"
	if strings.Contains(s.urlBase, "?") {
		sep = "&"
	}
	return s.urlBase + sep + "token=" + url.QueryEscape(token)
}
