package accounts

import (
	"context"
	"errors"
	"time"
)

// ErrNotFound is what repositories return for a missing row.
var ErrNotFound = errors.New("not found")

// ErrLiveSubscriptionExists is returned by SubscriptionRepository.Create
// when the one-live-subscription-per-user rule would be violated.
var ErrLiveSubscriptionExists = errors.New("live subscription exists")

// Actor is who performs an admin action (for audit and RBAC-visible data).
type Actor struct {
	UserID    string
	Role      string
	RequestID string
}

type UserRecord struct {
	ID          string
	Email       string
	Username    string
	Role        string
	Status      string
	CreatedAt   time.Time
	LastLoginAt *time.Time
	DisabledAt  *time.Time
}

type PlanRecord struct {
	ID                string
	Code              string
	Name              string
	PriceMinor        int64
	Currency          string
	Interval          string
	DurationDays      *int
	TrafficLimitBytes *int64
	DeviceLimit       int
	IsActive          bool
}

type SubscriptionRecord struct {
	ID                string
	UserID            string
	PlanID            string
	Status            string
	Source            string
	StartedAt         *time.Time
	CurrentPeriodEnd  time.Time
	TrafficLimitBytes *int64 // effective: override, else plan snapshot
	DeviceLimit       int    // effective: override, else snapshot, else 1
	PrimaryGrantID    *string
	CreatedAt         time.Time
}

type GrantRecord struct {
	ID        string
	NodeID    string
	NodeCode  string
	DeviceID  *string
	Protocol  string
	Status    string
	ExpiresAt time.Time
	CreatedAt time.Time
}

type DeviceRecord struct {
	ID             string
	DevicePublicID string
	Name           string
	Platform       *string
	SubscriptionID *string
	CreatedAt      time.Time
	LastSeenAt     *time.Time
	RevokedAt      *time.Time
}

type UsageTotals struct {
	BytesUp   int64
	BytesDown int64
}

// UserRepository reads users and updates credentials.
type UserRepository interface {
	UserByID(ctx context.Context, userID string) (UserRecord, error)
}

// PlanRepository reads tariff plans.
type PlanRepository interface {
	PlanByID(ctx context.Context, planID string) (PlanRecord, error)
}

// SubscriptionRepository owns subscriptions and their credentials.
type SubscriptionRepository interface {
	// LiveSubscription is the user's one non-terminal subscription
	// (pending/trialing/active/past_due/suspended), or ErrNotFound.
	LiveSubscription(ctx context.Context, userID string) (SubscriptionRecord, error)
	// Create activates a subscription snapshotting the plan's terms.
	Create(ctx context.Context, userID, planID, source, createdBy string) (SubscriptionRecord, error)
	SetPrimaryGrant(ctx context.Context, subscriptionID, grantID string) error
	Grants(ctx context.Context, subscriptionID string) ([]GrantRecord, error)
	Usage(ctx context.Context, subscriptionID string) (UsageTotals, error)
}

// AccessRepository issues access grants (the credential nodes accept).
type AccessRepository interface {
	// DefaultNodeID picks the node new subscription credentials go to.
	DefaultNodeID(ctx context.Context) (string, error)
	// CreateSubscriptionGrant issues a device-independent grant for the
	// user's active subscription.
	CreateSubscriptionGrant(ctx context.Context, userID, nodeID, protocol string, expiresAt time.Time) (GrantRecord, error)
}

// DeviceRepository lists registered devices.
type DeviceRepository interface {
	UserDevices(ctx context.Context, userID string) ([]DeviceRecord, error)
}

// PasswordResetRepository stores reset tokens by hash only.
type PasswordResetRepository interface {
	CreateResetToken(ctx context.Context, userID, tokenHash, channel, requestedBy string, expiresAt time.Time) error
	// ConsumeResetToken atomically marks an unexpired, unused token used,
	// sets the new password hash and revokes the user's sessions.
	// Returns the user id, or ErrNotFound if the token isn't usable.
	ConsumeResetToken(ctx context.Context, tokenHash, passwordHash, passwordAlgo string, now time.Time) (string, error)
}

// AuditEntry is one audited action. Metadata must never contain
// passwords, tokens, subscription URLs or key material.
type AuditEntry struct {
	Actor        Actor
	TargetUserID string
	Action       string
	ResourceType string
	ResourceID   string
	Metadata     map[string]any
}

type AuditLog interface {
	Record(ctx context.Context, entry AuditEntry) error
}

// ResetNotifier delivers a password reset link. Implementations must not
// log or persist the URL.
type ResetNotifier interface {
	// SendPasswordReset returns the delivery status ("sent",
	// "not_configured", ...).
	SendPasswordReset(ctx context.Context, email, resetURL string, expiresAt time.Time) (string, error)
}

// PasswordHasher hashes new passwords the same way login verifies them.
type PasswordHasher interface {
	Hash(password string) (hash, algo string, err error)
}
