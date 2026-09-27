package accounts

import (
	"context"
	"errors"
	"time"
)

// Audit actions written by this package.
const (
	AuditSubscriptionIssued     = "subscription_issued"
	AuditAccessCreated          = "access_created"
	AuditPasswordResetRequested = "password_reset_requested"
	AuditPasswordResetCompleted = "password_reset_completed"
)

// SubscriptionAssignmentService lets an admin force-assign a plan to a
// user who has no live subscription. It reuses the existing lifecycle:
// the subscription snapshots the plan terms, and the credential is a
// regular access grant on the default node.
type SubscriptionAssignmentService struct {
	users    UserRepository
	plans    PlanRepository
	subs     SubscriptionRepository
	access   AccessRepository
	audit    AuditLog
	details  *UserDetailsService
	protocol string
}

func NewSubscriptionAssignmentService(users UserRepository, plans PlanRepository, subs SubscriptionRepository, access AccessRepository, audit AuditLog, details *UserDetailsService, protocol string) *SubscriptionAssignmentService {
	if protocol == "" {
		protocol = "vless"
	}
	return &SubscriptionAssignmentService{users: users, plans: plans, subs: subs, access: access, audit: audit, details: details, protocol: protocol}
}

// Issue validates, creates and activates the subscription, issues its
// credential, records audit and returns the refreshed user details.
func (s *SubscriptionAssignmentService) Issue(ctx context.Context, actor Actor, userID, planID string) (UserDetails, error) {
	if _, err := s.users.UserByID(ctx, userID); errors.Is(err, ErrNotFound) {
		return UserDetails{}, errUserNotFound()
	} else if err != nil {
		return UserDetails{}, wrapInternal(CodeInternal, "Could not load user.", err)
	}

	plan, err := s.plans.PlanByID(ctx, planID)
	if errors.Is(err, ErrNotFound) {
		return UserDetails{}, errPlanNotFound()
	} else if err != nil {
		return UserDetails{}, wrapInternal(CodeInternal, "Could not load plan.", err)
	}
	if !plan.IsActive {
		return UserDetails{}, errPlanInactive()
	}

	if _, err := s.subs.LiveSubscription(ctx, userID); err == nil {
		return UserDetails{}, errAlreadyActive()
	} else if !errors.Is(err, ErrNotFound) {
		return UserDetails{}, wrapInternal(CodeInternal, "Could not check subscriptions.", err)
	}

	nodeID, err := s.access.DefaultNodeID(ctx)
	if errors.Is(err, ErrNotFound) {
		return UserDetails{}, errNoNode()
	} else if err != nil {
		return UserDetails{}, wrapInternal(CodeInternal, "Could not select a node.", err)
	}

	sub, err := s.subs.Create(ctx, userID, plan.ID, "admin", actor.UserID)
	if errors.Is(err, ErrLiveSubscriptionExists) {
		// Lost a race with another assignment; the DB index enforces it.
		return UserDetails{}, errAlreadyActive()
	} else if err != nil {
		return UserDetails{}, wrapInternal(CodeSubscriptionCreateFailed, "Subscription could not be created.", err)
	}

	grant, err := s.access.CreateSubscriptionGrant(ctx, userID, nodeID, s.protocol, sub.CurrentPeriodEnd)
	if err != nil {
		return UserDetails{}, wrapInternal(CodeSubscriptionCreateFailed, "Subscription created, but its access credential could not be issued; use Reissue.", err)
	}
	if err := s.subs.SetPrimaryGrant(ctx, sub.ID, grant.ID); err != nil {
		return UserDetails{}, wrapInternal(CodeSubscriptionCreateFailed, "Access credential could not be linked to the subscription.", err)
	}

	s.record(ctx, AuditEntry{
		Actor: actor, TargetUserID: userID, Action: AuditSubscriptionIssued,
		ResourceType: "subscription", ResourceID: sub.ID,
		Metadata: map[string]any{
			"plan_id": plan.ID, "plan_code": plan.Code, "status": sub.Status,
			"expires_at": sub.CurrentPeriodEnd.UTC().Format(time.RFC3339),
		},
	})
	s.record(ctx, AuditEntry{
		Actor: actor, TargetUserID: userID, Action: AuditAccessCreated,
		ResourceType: "access_grant", ResourceID: grant.ID,
		Metadata: map[string]any{"subscription_id": sub.ID, "node_id": nodeID, "protocol": grant.Protocol},
	})

	return s.details.Get(ctx, userID)
}

// record never fails the business action: the action already happened.
func (s *SubscriptionAssignmentService) record(ctx context.Context, entry AuditEntry) {
	_ = s.audit.Record(ctx, entry)
}
