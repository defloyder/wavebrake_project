package accounts

import (
	"context"
	"errors"
	"time"
)

// Subscription lifecycle (project rule, 2026-09-27): a user has exactly
// one subscription. When its period ends or its traffic runs out it goes
// past_due for a grace period, during which VPN access is blocked but the
// same subscription can be renewed (same credential, same link). If the
// grace period passes unpaid it expires and the account is reset: its
// access keys are revoked and the devices bound to it are revoked, except
// the most recently active one, which stays registered without a
// subscription. The account and its login are kept.

// DefaultGracePeriod is how long a past_due subscription waits for renewal.
const DefaultGracePeriod = 7 * 24 * time.Hour

// Audit actions written by the lifecycle.
const (
	AuditSubscriptionPastDue = "subscription_past_due"
	AuditSubscriptionExpired = "subscription_expired"
	AuditSubscriptionRenewed = "subscription_renewed"
)

// Why a subscription left the active state.
const (
	LifecycleReasonPeriodEnded      = "period_ended"
	LifecycleReasonTrafficExhausted = "traffic_exhausted"
	LifecycleReasonGraceEnded       = "grace_ended"
)

// LifecycleCandidate is a subscription due for a lifecycle transition.
type LifecycleCandidate struct {
	SubscriptionID string
	UserID         string
	Reason         string
}

// ResetOutcome is what an expiry reset removed.
type ResetOutcome struct {
	RevokedGrants  int
	RevokedDevices int
	KeptDeviceID   string
}

// LifecycleRepository performs the lifecycle transitions atomically.
type LifecycleRepository interface {
	// DueForGrace lists active/trialing subscriptions whose period ended at
	// or before now, or whose used traffic reached the effective limit.
	DueForGrace(ctx context.Context, now time.Time) ([]LifecycleCandidate, error)
	// EnterGrace moves the subscription to past_due, ends its period at now
	// if it was still running, and stops its keys being served to nodes.
	// ErrNotFound when it is no longer active (changed concurrently).
	EnterGrace(ctx context.Context, subscriptionID string, now time.Time) error
	// DueForExpiry lists past_due subscriptions whose period ended at or
	// before cutoff (now minus the grace period).
	DueForExpiry(ctx context.Context, cutoff time.Time) ([]LifecycleCandidate, error)
	// ExpireAndReset expires the subscription and resets the account (see
	// the package rule above). ErrNotFound when it is no longer past_due.
	ExpireAndReset(ctx context.Context, subscriptionID string) (ResetOutcome, error)
}

// LifecycleReport counts the transitions of one run.
type LifecycleReport struct {
	PastDue int
	Expired int
}

// SubscriptionLifecycleService applies the lifecycle; the worker runs it
// periodically. Each transition is independent: one failure is reported
// and the rest still run.
type SubscriptionLifecycleService struct {
	repo  LifecycleRepository
	audit AuditLog
	grace time.Duration
	now   func() time.Time
}

func NewSubscriptionLifecycleService(repo LifecycleRepository, audit AuditLog, grace time.Duration) *SubscriptionLifecycleService {
	if grace <= 0 {
		grace = DefaultGracePeriod
	}
	return &SubscriptionLifecycleService{repo: repo, audit: audit, grace: grace, now: time.Now}
}

// GraceEndsAt is when a past_due subscription whose period ended at
// periodEnd is reset.
func (s *SubscriptionLifecycleService) GraceEndsAt(periodEnd time.Time) time.Time {
	return periodEnd.Add(s.grace)
}

func (s *SubscriptionLifecycleService) Run(ctx context.Context) (LifecycleReport, error) {
	now := s.now().UTC()
	var report LifecycleReport
	var errs []error

	due, err := s.repo.DueForGrace(ctx, now)
	if err != nil {
		return report, err
	}
	for _, c := range due {
		if err := s.repo.EnterGrace(ctx, c.SubscriptionID, now); errors.Is(err, ErrNotFound) {
			continue
		} else if err != nil {
			errs = append(errs, err)
			continue
		}
		report.PastDue++
		s.record(ctx, c, AuditSubscriptionPastDue, map[string]any{
			"reason": c.Reason, "grace_ends_at": now.Add(s.grace).Format(time.RFC3339),
		})
	}

	expiring, err := s.repo.DueForExpiry(ctx, now.Add(-s.grace))
	if err != nil {
		return report, errors.Join(append(errs, err)...)
	}
	for _, c := range expiring {
		outcome, err := s.repo.ExpireAndReset(ctx, c.SubscriptionID)
		if errors.Is(err, ErrNotFound) {
			continue
		} else if err != nil {
			errs = append(errs, err)
			continue
		}
		report.Expired++
		s.record(ctx, c, AuditSubscriptionExpired, map[string]any{
			"reason": LifecycleReasonGraceEnded, "revoked_grants": outcome.RevokedGrants,
			"revoked_devices": outcome.RevokedDevices, "kept_device_id": outcome.KeptDeviceID,
		})
	}
	return report, errors.Join(errs...)
}

// record never fails the transition: it already happened.
func (s *SubscriptionLifecycleService) record(ctx context.Context, c LifecycleCandidate, action string, metadata map[string]any) {
	_ = s.audit.Record(ctx, AuditEntry{
		TargetUserID: c.UserID, Action: action,
		ResourceType: "subscription", ResourceID: c.SubscriptionID, Metadata: metadata,
	})
}
