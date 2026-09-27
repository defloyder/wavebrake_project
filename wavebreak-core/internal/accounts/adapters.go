package accounts

import (
	"context"
	"time"

	"wavebreak-core/internal/security"
)

// SecureTokenSource: 32 random bytes (base64url) and their SHA-256 hex —
// the same primitives refresh tokens use.
type SecureTokenSource struct{}

func (SecureTokenSource) New() (string, string, error) {
	token, err := security.RandomToken(32)
	if err != nil {
		return "", "", err
	}
	return token, security.TokenHash(token), nil
}

func (SecureTokenSource) Hash(token string) string { return security.TokenHash(token) }

// Argon2Hasher hashes passwords exactly like registration/login.
type Argon2Hasher struct{}

func (Argon2Hasher) Hash(password string) (string, string, error) {
	hash, err := security.HashPassword(password)
	return hash, "argon2id", err
}

// UnconfiguredEmailNotifier is used while Core has no email provider: the
// reset token is still created (and can be delivered once a provider is
// wired in), but nothing is sent and the link is dropped — never logged
// or stored.
type UnconfiguredEmailNotifier struct{}

func (UnconfiguredEmailNotifier) SendPasswordReset(context.Context, string, string, time.Time) (string, error) {
	return "not_configured", nil
}
