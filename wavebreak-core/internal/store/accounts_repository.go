package store

import (
	"context"
	"encoding/json"
	"errors"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"

	"wavebreak-core/internal/accounts"
)

// ErrLiveSubscriptionExists: the one-live-subscription-per-user index
// (migration 00004) rejected a new subscription.
var ErrLiveSubscriptionExists = errors.New("user already has a live subscription")

const liveSubscriptionStatuses = `('pending', 'trialing', 'active', 'past_due', 'suspended')`

// isLiveSubscriptionConflict recognizes the unique-index violation.
func isLiveSubscriptionConflict(err error) bool {
	var pgErr *pgconn.PgError
	return errors.As(err, &pgErr) && pgErr.Code == "23505" && pgErr.ConstraintName == "subscriptions_one_live_per_user_idx"
}

// AccountsRepository adapts the Store to the accounts package ports
// (users, plans, subscriptions, access, devices, password reset, audit).
type AccountsRepository struct {
	st *Store
}

func (s *Store) Accounts() *AccountsRepository { return &AccountsRepository{st: s} }

var (
	_ accounts.UserRepository          = (*AccountsRepository)(nil)
	_ accounts.PlanRepository          = (*AccountsRepository)(nil)
	_ accounts.SubscriptionRepository  = (*AccountsRepository)(nil)
	_ accounts.AccessRepository        = (*AccountsRepository)(nil)
	_ accounts.DeviceRepository        = (*AccountsRepository)(nil)
	_ accounts.PasswordResetRepository = (*AccountsRepository)(nil)
	_ accounts.AuditLog                = (*AccountsRepository)(nil)
)

func notFound(err error) error {
	if errors.Is(err, pgx.ErrNoRows) || errors.Is(err, ErrNotFound) {
		return accounts.ErrNotFound
	}
	return err
}

func (r *AccountsRepository) UserByID(ctx context.Context, userID string) (accounts.UserRecord, error) {
	u, err := r.st.GetUserByID(ctx, userID)
	if err != nil {
		return accounts.UserRecord{}, notFound(err)
	}
	return accounts.UserRecord{ID: u.ID, Email: u.Email, Username: u.Username, Role: u.Role, Status: u.Status, CreatedAt: u.CreatedAt, LastLoginAt: u.LastLoginAt, DisabledAt: u.DisabledAt}, nil
}

func (r *AccountsRepository) PlanByID(ctx context.Context, planID string) (accounts.PlanRecord, error) {
	var p accounts.PlanRecord
	err := r.st.db.QueryRow(ctx, `
		select id::text, code, name, price_minor, currency, interval, duration_days, traffic_limit_bytes, device_limit, is_active
		from plans
		where id::text = $1 and deleted_at is null`, planID,
	).Scan(&p.ID, &p.Code, &p.Name, &p.PriceMinor, &p.Currency, &p.Interval, &p.DurationDays, &p.TrafficLimitBytes, &p.DeviceLimit, &p.IsActive)
	return p, notFound(err)
}

const subscriptionRecordColumns = `
	id::text, user_id::text, plan_id::text, status, source, started_at, current_period_end,
	coalesce(traffic_limit_override_bytes, traffic_limit_bytes_snapshot),
	coalesce(device_limit_override, device_limit_snapshot, 1),
	primary_grant_id::text, created_at`

func scanSubscriptionRecord(row pgx.Row) (accounts.SubscriptionRecord, error) {
	var s accounts.SubscriptionRecord
	err := row.Scan(&s.ID, &s.UserID, &s.PlanID, &s.Status, &s.Source, &s.StartedAt, &s.CurrentPeriodEnd, &s.TrafficLimitBytes, &s.DeviceLimit, &s.PrimaryGrantID, &s.CreatedAt)
	return s, err
}

func (r *AccountsRepository) LiveSubscription(ctx context.Context, userID string) (accounts.SubscriptionRecord, error) {
	s, err := scanSubscriptionRecord(r.st.db.QueryRow(ctx, `
		select `+subscriptionRecordColumns+`
		from subscriptions
		where user_id::text = $1 and status in `+liveSubscriptionStatuses+`
		order by created_at desc
		limit 1`, userID))
	return s, notFound(err)
}

func (r *AccountsRepository) Create(ctx context.Context, userID, planID, source, createdBy string) (accounts.SubscriptionRecord, error) {
	sub, err := r.st.CreateSubscriptionFor(ctx, userID, planID, source, createdBy)
	if errors.Is(err, ErrLiveSubscriptionExists) {
		return accounts.SubscriptionRecord{}, accounts.ErrLiveSubscriptionExists
	}
	if err != nil {
		return accounts.SubscriptionRecord{}, notFound(err)
	}
	s, err := scanSubscriptionRecord(r.st.db.QueryRow(ctx, `select `+subscriptionRecordColumns+` from subscriptions where id = $1`, sub.ID))
	return s, notFound(err)
}

func (r *AccountsRepository) SetPrimaryGrant(ctx context.Context, subscriptionID, grantID string) error {
	_, err := r.st.db.Exec(ctx, `update subscriptions set primary_grant_id = $2, updated_at = now() where id = $1`, subscriptionID, grantID)
	return err
}

func (r *AccountsRepository) Grants(ctx context.Context, subscriptionID string) ([]accounts.GrantRecord, error) {
	rows, err := r.st.db.Query(ctx, `
		select g.id::text, g.node_id::text, coalesce(n.code, ''), g.device_id::text, g.protocol, g.status, g.expires_at, g.created_at
		from access_grants g
		left join nodes n on n.id = g.node_id
		where g.subscription_id = $1
		order by g.created_at desc`, subscriptionID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []accounts.GrantRecord
	for rows.Next() {
		var g accounts.GrantRecord
		if err := rows.Scan(&g.ID, &g.NodeID, &g.NodeCode, &g.DeviceID, &g.Protocol, &g.Status, &g.ExpiresAt, &g.CreatedAt); err != nil {
			return nil, err
		}
		out = append(out, g)
	}
	return out, rows.Err()
}

// Usage reads the per-subscription totals the node usage pipeline
// maintains (RecordNodeUsageReport -> subscription_usage).
func (r *AccountsRepository) Usage(ctx context.Context, subscriptionID string) (accounts.UsageTotals, error) {
	var u accounts.UsageTotals
	err := r.st.db.QueryRow(ctx, `select bytes_up, bytes_down from subscription_usage where subscription_id = $1`, subscriptionID).Scan(&u.BytesUp, &u.BytesDown)
	if errors.Is(err, pgx.ErrNoRows) {
		return accounts.UsageTotals{}, nil
	}
	return u, err
}

// DefaultNodeID: the node new subscription credentials go to — the online
// primary that already serves the most of them (a freshly enrolled node
// never takes over), freshest heartbeat as the tie-break. Mirror nodes
// (migration 00006) serve another node's credentials and are never picked.
func (r *AccountsRepository) DefaultNodeID(ctx context.Context) (string, error) {
	var id string
	err := r.st.db.QueryRow(ctx, `
		select n.id::text from nodes n
		where n.status = 'online' and n.shares_grants_of is null
		order by (select count(*) from access_grants g where g.node_id = n.id and g.status = 'active') desc,
		         n.last_heartbeat_at desc nulls last, n.code
		limit 1`).Scan(&id)
	return id, notFound(err)
}

func (r *AccountsRepository) CreateSubscriptionGrant(ctx context.Context, userID, nodeID, protocol string, expiresAt time.Time) (accounts.GrantRecord, error) {
	g, err := r.st.CreateAccessGrant(ctx, userID, nodeID, protocol, "", expiresAt)
	if err != nil {
		return accounts.GrantRecord{}, notFound(err)
	}
	return accounts.GrantRecord{ID: g.ID, NodeID: g.NodeID, DeviceID: g.DeviceID, Protocol: g.Protocol, Status: g.Status, ExpiresAt: g.ExpiresAt, CreatedAt: g.CreatedAt}, nil
}

func (r *AccountsRepository) UserDevices(ctx context.Context, userID string) ([]accounts.DeviceRecord, error) {
	rows, err := r.st.db.Query(ctx, `
		select id::text, coalesce(device_public_id, id::text), name, platform, subscription_id::text, created_at, last_seen_at, revoked_at
		from devices
		where user_id::text = $1
		order by revoked_at nulls first, coalesce(last_seen_at, created_at) desc`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []accounts.DeviceRecord
	for rows.Next() {
		var d accounts.DeviceRecord
		if err := rows.Scan(&d.ID, &d.DevicePublicID, &d.Name, &d.Platform, &d.SubscriptionID, &d.CreatedAt, &d.LastSeenAt, &d.RevokedAt); err != nil {
			return nil, err
		}
		out = append(out, d)
	}
	return out, rows.Err()
}

func (r *AccountsRepository) CreateResetToken(ctx context.Context, userID, tokenHash, channel, requestedBy string, expiresAt time.Time) error {
	_, err := r.st.db.Exec(ctx, `
		insert into password_reset_tokens (user_id, token_hash, channel, requested_by, expires_at)
		values ($1, $2, $3, nullif($4, '')::uuid, $5)`, userID, tokenHash, channel, requestedBy, expiresAt)
	return err
}

// ConsumeResetToken: one transaction marks the token used (only if unused
// and unexpired), invalidates the user's other outstanding tokens, sets
// the password and revokes every session so old refresh tokens die.
func (r *AccountsRepository) ConsumeResetToken(ctx context.Context, tokenHash, passwordHash, passwordAlgo string, now time.Time) (string, error) {
	tx, err := r.st.db.Begin(ctx)
	if err != nil {
		return "", err
	}
	defer tx.Rollback(ctx)

	var userID string
	err = tx.QueryRow(ctx, `
		update password_reset_tokens
		set used_at = $2
		where token_hash = $1 and used_at is null and expires_at > $2
		returning user_id::text`, tokenHash, now).Scan(&userID)
	if err != nil {
		return "", notFound(err)
	}
	if _, err := tx.Exec(ctx, `update password_reset_tokens set used_at = $2 where user_id = $1 and used_at is null`, userID, now); err != nil {
		return "", err
	}
	if _, err := tx.Exec(ctx, `update users set password_hash = $2, password_algo = $3, updated_at = now() where id = $1`, userID, passwordHash, passwordAlgo); err != nil {
		return "", err
	}
	if _, err := tx.Exec(ctx, `update sessions set revoked_at = now(), revoked_reason = 'password_reset' where user_id = $1 and revoked_at is null`, userID); err != nil {
		return "", err
	}
	return userID, tx.Commit(ctx)
}

func (r *AccountsRepository) Record(ctx context.Context, e accounts.AuditEntry) error {
	metadata := e.Metadata
	if metadata == nil {
		metadata = map[string]any{}
	}
	body, err := json.Marshal(metadata)
	if err != nil {
		return err
	}
	_, err = r.st.db.Exec(ctx, `
		insert into audit_events (actor_user_id, action, target_type, target_id, metadata, target_user_id, request_id)
		values (nullif($1, '')::uuid, $2, $3, nullif($4, '')::uuid, $5, nullif($6, '')::uuid, nullif($7, ''))`,
		e.Actor.UserID, e.Action, e.ResourceType, e.ResourceID, body, e.TargetUserID, e.Actor.RequestID)
	return err
}
