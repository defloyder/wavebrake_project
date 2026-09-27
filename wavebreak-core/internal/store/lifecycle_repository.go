package store

import (
	"context"
	"encoding/json"
	"errors"
	"time"

	"github.com/jackc/pgx/v5"

	"wavebreak-core/internal/accounts"
)

var _ accounts.LifecycleRepository = (*AccountsRepository)(nil)

// effectiveLimitSQL is the traffic limit a subscription is held to: the
// admin override, else the plan snapshot taken at activation.
const effectiveLimitSQL = `coalesce(s.traffic_limit_override_bytes, s.traffic_limit_bytes_snapshot)`

func (r *AccountsRepository) DueForGrace(ctx context.Context, now time.Time) ([]accounts.LifecycleCandidate, error) {
	return r.candidates(ctx, `
		select s.id::text, s.user_id::text,
		       case when s.current_period_end <= $1 then '`+accounts.LifecycleReasonPeriodEnded+`'
		            else '`+accounts.LifecycleReasonTrafficExhausted+`' end
		from subscriptions s
		left join subscription_usage u on u.subscription_id = s.id
		where s.status in ('active', 'trialing')
		  and (s.current_period_end <= $1
		       or (`+effectiveLimitSQL+` > 0
		           and coalesce(u.bytes_up, 0) + coalesce(u.bytes_down, 0) >= `+effectiveLimitSQL+`))
		order by s.current_period_end`, now)
}

func (r *AccountsRepository) DueForExpiry(ctx context.Context, cutoff time.Time) ([]accounts.LifecycleCandidate, error) {
	return r.candidates(ctx, `
		select id::text, user_id::text, '`+accounts.LifecycleReasonGraceEnded+`'
		from subscriptions
		where status = 'past_due' and current_period_end <= $1
		order by current_period_end`, cutoff)
}

func (r *AccountsRepository) candidates(ctx context.Context, query string, at time.Time) ([]accounts.LifecycleCandidate, error) {
	rows, err := r.st.db.Query(ctx, query, at)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []accounts.LifecycleCandidate
	for rows.Next() {
		var c accounts.LifecycleCandidate
		if err := rows.Scan(&c.SubscriptionID, &c.UserID, &c.Reason); err != nil {
			return nil, err
		}
		out = append(out, c)
	}
	return out, rows.Err()
}

// EnterGrace: past_due, period ended at now at the latest, and the keys
// expire now so nodes stop accepting them. Renewal moves the key expiry
// forward again (syncSubscriptionGrantExpiryTx), so the link survives.
func (r *AccountsRepository) EnterGrace(ctx context.Context, subscriptionID string, now time.Time) error {
	tx, err := r.st.db.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)

	tag, err := tx.Exec(ctx, `
		update subscriptions
		set status = 'past_due', current_period_end = least(current_period_end, $2), updated_at = now()
		where id = $1 and status in ('active', 'trialing')`, subscriptionID, now)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return accounts.ErrNotFound
	}
	if err := syncSubscriptionGrantExpiryTx(ctx, tx, subscriptionID, now); err != nil {
		return err
	}
	payload, _ := json.Marshal(map[string]any{"subscription_id": subscriptionID, "status": "past_due"})
	if err := insertOutbox(ctx, tx, "subscription.past_due", subscriptionID, payload); err != nil {
		return err
	}
	return tx.Commit(ctx)
}

// ExpireAndReset: expired, every key revoked, and every device bound to
// the subscription revoked except the most recently active one, which
// stays registered but no longer belongs to a subscription.
func (r *AccountsRepository) ExpireAndReset(ctx context.Context, subscriptionID string) (accounts.ResetOutcome, error) {
	var out accounts.ResetOutcome
	tx, err := r.st.db.Begin(ctx)
	if err != nil {
		return out, err
	}
	defer tx.Rollback(ctx)

	tag, err := tx.Exec(ctx, `
		update subscriptions
		set status = 'expired', ended_at = now(), updated_at = now()
		where id = $1 and status = 'past_due'`, subscriptionID)
	if err != nil {
		return out, err
	}
	if tag.RowsAffected() == 0 {
		return out, accounts.ErrNotFound
	}

	rows, err := tx.Query(ctx, `
		update access_grants
		set status = 'revoked', revoked_at = coalesce(revoked_at, now()), revoked_reason = 'subscription_expired', updated_at = now()
		where subscription_id = $1 and status = 'active'
		returning id::text, node_id::text`, subscriptionID)
	if err != nil {
		return out, err
	}
	var grantIDs []string
	nodes := map[string]bool{}
	for rows.Next() {
		var id, nodeID string
		if err := rows.Scan(&id, &nodeID); err != nil {
			rows.Close()
			return out, err
		}
		grantIDs = append(grantIDs, id)
		nodes[nodeID] = true
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return out, err
	}
	for nodeID := range nodes {
		if _, err := refreshNodeDesiredStateTx(ctx, tx, nodeID); err != nil {
			return out, err
		}
	}
	for _, id := range grantIDs {
		payload, _ := json.Marshal(map[string]any{"id": id, "subscription_id": subscriptionID, "revoked_reason": "subscription_expired"})
		if err := insertOutbox(ctx, tx, "access.revoked", id, payload); err != nil {
			return out, err
		}
	}
	out.RevokedGrants = len(grantIDs)

	err = tx.QueryRow(ctx, `
		select id::text from devices
		where subscription_id = $1 and revoked_at is null
		order by coalesce(last_seen_at, created_at) desc
		limit 1`, subscriptionID).Scan(&out.KeptDeviceID)
	if err != nil && !errors.Is(err, pgx.ErrNoRows) {
		return out, err
	}
	tag, err = tx.Exec(ctx, `
		update devices set revoked_at = now(), updated_at = now()
		where subscription_id = $1 and revoked_at is null and id::text <> $2`, subscriptionID, out.KeptDeviceID)
	if err != nil {
		return out, err
	}
	out.RevokedDevices = int(tag.RowsAffected())
	if _, err := tx.Exec(ctx, `
		update devices set subscription_id = null, updated_at = now()
		where subscription_id = $1`, subscriptionID); err != nil {
		return out, err
	}

	payload, _ := json.Marshal(map[string]any{"subscription_id": subscriptionID, "status": "expired"})
	if err := insertOutbox(ctx, tx, "subscription.expired", subscriptionID, payload); err != nil {
		return out, err
	}
	return out, tx.Commit(ctx)
}

// RenewPastDueSubscription renews the user's past_due subscription in
// place with the chosen plan: same subscription and credential (the link
// keeps working), a fresh period and plan terms, usage counted from zero,
// and the keys served to nodes again until the new period end.
// ErrNotFound when the user has no past_due subscription or the plan is
// not available.
func (s *Store) RenewPastDueSubscription(ctx context.Context, userID, planID string) (Subscription, error) {
	tx, err := s.db.Begin(ctx)
	if err != nil {
		return Subscription{}, err
	}
	defer tx.Rollback(ctx)

	var sub Subscription
	err = tx.QueryRow(ctx, `
		update subscriptions s
		set plan_id = p.id,
		    status = 'active',
		    traffic_limit_bytes_snapshot = p.traffic_limit_bytes,
		    device_limit_snapshot = p.device_limit,
		    concurrent_connection_limit_snapshot = p.concurrent_connection_limit,
		    traffic_limit_override_bytes = null,
		    device_limit_override = null,
		    current_period_end = now() + make_interval(days => coalesce(p.duration_days, 30)),
		    ended_at = null,
		    updated_at = now()
		from plans p
		where s.user_id = $1 and s.status = 'past_due'
		  and p.id = $2 and p.is_active = true and p.deleted_at is null
		returning s.id::text, s.user_id::text, s.plan_id::text, s.status, s.source, s.source_reference, s.created_by::text,
		          s.traffic_limit_bytes_snapshot, s.device_limit_snapshot, s.concurrent_connection_limit_snapshot,
		          s.traffic_limit_override_bytes, s.device_limit_override, s.current_period_end, s.created_at, s.updated_at`,
		userID, planID,
	).Scan(&sub.ID, &sub.UserID, &sub.PlanID, &sub.Status, &sub.Source, &sub.SourceReference, &sub.CreatedBy, &sub.TrafficLimitBytesSnapshot, &sub.DeviceLimitSnapshot, &sub.ConcurrentConnectionLimitSnapshot, &sub.TrafficLimitOverrideBytes, &sub.DeviceLimitOverride, &sub.CurrentPeriodEnd, &sub.CreatedAt, &sub.UpdatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return Subscription{}, ErrNotFound
	}
	if err != nil {
		return Subscription{}, err
	}
	if _, err := tx.Exec(ctx, `
		insert into subscription_usage (subscription_id, bytes_up, bytes_down)
		values ($1, 0, 0)
		on conflict (subscription_id) do update set bytes_up = 0, bytes_down = 0, updated_at = now()`, sub.ID); err != nil {
		return Subscription{}, err
	}
	if _, err := tx.Exec(ctx, `
		update grant_usage_counters set total_bytes_up = 0, total_bytes_down = 0, updated_at = now()
		where subscription_id = $1`, sub.ID); err != nil {
		return Subscription{}, err
	}
	if err := syncSubscriptionGrantExpiryTx(ctx, tx, sub.ID, sub.CurrentPeriodEnd); err != nil {
		return Subscription{}, err
	}
	payload, _ := json.Marshal(sub)
	if err := insertOutbox(ctx, tx, "subscription.renewed", sub.ID, payload); err != nil {
		return Subscription{}, err
	}
	return sub, tx.Commit(ctx)
}

// CurrentSubscription is the user's live subscription, past_due included
// (the app shows "renew until …" for it); ErrNotFound when there is none.
func (s *Store) CurrentSubscription(ctx context.Context, userID string) (Subscription, error) {
	var sub Subscription
	err := s.db.QueryRow(ctx, `
		select id::text, user_id::text, plan_id::text, status, source, source_reference, created_by::text,
		       traffic_limit_bytes_snapshot, device_limit_snapshot, concurrent_connection_limit_snapshot,
		       traffic_limit_override_bytes, device_limit_override, current_period_end, created_at, updated_at
		from subscriptions
		where user_id = $1 and status in `+liveSubscriptionStatuses+`
		order by created_at desc
		limit 1`, userID,
	).Scan(&sub.ID, &sub.UserID, &sub.PlanID, &sub.Status, &sub.Source, &sub.SourceReference, &sub.CreatedBy, &sub.TrafficLimitBytesSnapshot, &sub.DeviceLimitSnapshot, &sub.ConcurrentConnectionLimitSnapshot, &sub.TrafficLimitOverrideBytes, &sub.DeviceLimitOverride, &sub.CurrentPeriodEnd, &sub.CreatedAt, &sub.UpdatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return Subscription{}, ErrNotFound
	}
	return sub, err
}
