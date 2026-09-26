package store

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"

	"wavebreak-core/internal/security"
)

var ErrNotFound = errors.New("not found")
var ErrRefreshTokenReused = errors.New("refresh token was already revoked")
var ErrLimitReached = errors.New("limit reached")
var ErrConflict = errors.New("conflict")

type Store struct {
	db *pgxpool.Pool
}

type User struct {
	ID           string     `json:"id"`
	Email        string     `json:"email"`
	Username     string     `json:"username,omitempty"`
	PasswordHash string     `json:"-"`
	PasswordAlgo string     `json:"-"`
	Status       string     `json:"status"`
	Role         string     `json:"role"`
	LastLoginAt  *time.Time `json:"last_login_at,omitempty"`
	DisabledAt   *time.Time `json:"disabled_at,omitempty"`
	CreatedAt    time.Time  `json:"created_at"`
}

type Plan struct {
	ID                        string `json:"id"`
	Code                      string `json:"code"`
	Name                      string `json:"name"`
	Description               string `json:"description"`
	PriceCents                int64  `json:"price_cents"`
	PriceMinor                int64  `json:"price_minor"`
	Currency                  string `json:"currency"`
	Interval                  string `json:"interval"`
	DurationDays              *int   `json:"duration_days,omitempty"`
	DeviceLimit               int    `json:"device_limit"`
	TrafficLimitBytes         *int64 `json:"traffic_limit_bytes,omitempty"`
	ConcurrentConnectionLimit *int   `json:"concurrent_connection_limit,omitempty"`
	IsActive                  bool   `json:"is_active"`
	IsPublic                  bool   `json:"is_public"`
	SortOrder                 int    `json:"sort_order"`
}

type Subscription struct {
	ID                                string    `json:"id"`
	UserID                            string    `json:"user_id"`
	PlanID                            string    `json:"plan_id"`
	Status                            string    `json:"status"`
	Source                            string    `json:"source"`
	SourceReference                   *string   `json:"source_reference,omitempty"`
	CreatedBy                         *string   `json:"created_by,omitempty"`
	TrafficLimitBytesSnapshot         *int64    `json:"traffic_limit_bytes_snapshot,omitempty"`
	DeviceLimitSnapshot               *int      `json:"device_limit_snapshot,omitempty"`
	ConcurrentConnectionLimitSnapshot *int      `json:"concurrent_connection_limit_snapshot,omitempty"`
	TrafficLimitOverrideBytes         *int64    `json:"traffic_limit_override_bytes,omitempty"`
	DeviceLimitOverride               *int      `json:"device_limit_override,omitempty"`
	CurrentPeriodEnd                  time.Time `json:"current_period_end"`
	CreatedAt                         time.Time `json:"created_at"`
	UpdatedAt                         time.Time `json:"updated_at"`
}

type Node struct {
	ID              string     `json:"id"`
	Code            string     `json:"code"`
	Region          string     `json:"region"`
	Status          string     `json:"status"`
	DesiredRevision int        `json:"desired_revision"`
	AppliedRevision int        `json:"applied_revision"`
	LastSyncError   *string    `json:"last_sync_error,omitempty"`
	LastHeartbeatAt *time.Time `json:"last_heartbeat_at,omitempty"`
}

type AccessGrant struct {
	ID              string     `json:"id"`
	UserID          string     `json:"user_id"`
	SubscriptionID  *string    `json:"subscription_id,omitempty"`
	DeviceID        *string    `json:"device_id,omitempty"`
	NodeID          string     `json:"node_id"`
	Protocol        string     `json:"protocol"`
	Status          string     `json:"status"`
	ExpiresAt       time.Time  `json:"expires_at"`
	RevokedAt       *time.Time `json:"revoked_at,omitempty"`
	RevokedReason   *string    `json:"revoked_reason,omitempty"`
	DesiredRevision int        `json:"desired_revision"`
	CreatedAt       time.Time  `json:"created_at"`
}

type OutboxEvent struct {
	ID          string
	Type        string
	AggregateID string
	Payload     json.RawMessage
	CreatedAt   time.Time
}

type DesiredState struct {
	NodeID   string          `json:"node_id"`
	Revision int             `json:"revision"`
	State    json.RawMessage `json:"state"`
}

func New(db *pgxpool.Pool) *Store {
	return &Store{db: db}
}

func (s *Store) Ping(ctx context.Context) error {
	return s.db.Ping(ctx)
}

func (s *Store) CreateUser(ctx context.Context, email, passwordHash string) (User, error) {
	return s.CreateUserWithRole(ctx, email, passwordHash, "user")
}

func (s *Store) CreateUserWithRole(ctx context.Context, email, passwordHash, role string) (User, error) {
	var u User
	email = NormalizeEmail(email)
	err := s.db.QueryRow(ctx, `
		insert into users (email, password_hash, password_algo, role)
		values ($1, $2, 'argon2id', $3)
		returning id::text, coalesce(email, ''), coalesce(username, ''), coalesce(password_hash, ''), password_algo, status, role, last_login_at, disabled_at, created_at`,
		email, passwordHash, role,
	).Scan(&u.ID, &u.Email, &u.Username, &u.PasswordHash, &u.PasswordAlgo, &u.Status, &u.Role, &u.LastLoginAt, &u.DisabledAt, &u.CreatedAt)
	return u, normalizeDatabaseError(err)
}

func (s *Store) GetUserByEmail(ctx context.Context, email string) (User, error) {
	var u User
	email = NormalizeEmail(email)
	err := s.db.QueryRow(ctx, `
		select id::text, coalesce(email, ''), coalesce(username, ''), coalesce(password_hash, ''), password_algo, status, role, last_login_at, disabled_at, created_at
		from users where email = $1`, email,
	).Scan(&u.ID, &u.Email, &u.Username, &u.PasswordHash, &u.PasswordAlgo, &u.Status, &u.Role, &u.LastLoginAt, &u.DisabledAt, &u.CreatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return User{}, ErrNotFound
	}
	return u, err
}

func (s *Store) GetUserByID(ctx context.Context, id string) (User, error) {
	var u User
	err := s.db.QueryRow(ctx, `
		select id::text, coalesce(email, ''), coalesce(username, ''), coalesce(password_hash, ''), password_algo, status, role, last_login_at, disabled_at, created_at
		from users where id = $1`, id,
	).Scan(&u.ID, &u.Email, &u.Username, &u.PasswordHash, &u.PasswordAlgo, &u.Status, &u.Role, &u.LastLoginAt, &u.DisabledAt, &u.CreatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return User{}, ErrNotFound
	}
	return u, err
}

func (s *Store) CreateSession(ctx context.Context, userID, refreshToken string, expiresAt time.Time) error {
	_, err := s.db.Exec(ctx, `
		insert into sessions (user_id, refresh_token_hash, expires_at)
		values ($1, $2, $3)`, userID, security.TokenHash(refreshToken), expiresAt)
	return err
}

func (s *Store) RotateRefreshToken(ctx context.Context, refreshToken, newRefreshToken string, newExpiresAt time.Time) (User, error) {
	tx, err := s.db.Begin(ctx)
	if err != nil {
		return User{}, err
	}
	defer tx.Rollback(ctx)

	var u User
	var sessionID string
	var revokedAt *time.Time
	err = tx.QueryRow(ctx, `
		select s.id::text, s.revoked_at, u.id::text, coalesce(u.email, ''), coalesce(u.username, ''), coalesce(u.password_hash, ''), u.password_algo, u.status, u.role, u.last_login_at, u.disabled_at, u.created_at
		from sessions s
		join users u on u.id = s.user_id
		where s.refresh_token_hash = $1
		  and s.expires_at > now()`,
		security.TokenHash(refreshToken),
	).Scan(&sessionID, &revokedAt, &u.ID, &u.Email, &u.Username, &u.PasswordHash, &u.PasswordAlgo, &u.Status, &u.Role, &u.LastLoginAt, &u.DisabledAt, &u.CreatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return User{}, ErrNotFound
	}
	if err != nil {
		return User{}, err
	}
	if revokedAt != nil {
		_, _ = tx.Exec(ctx, `
			update sessions set revoked_at = coalesce(revoked_at, now()), revoked_reason = coalesce(revoked_reason, 'reuse_detected')
			where user_id = $1 and revoked_at is null`, u.ID)
		_ = tx.Commit(ctx)
		return User{}, ErrRefreshTokenReused
	}
	if u.DisabledAt != nil {
		return User{}, ErrNotFound
	}

	var newSessionID string
	err = tx.QueryRow(ctx, `
		insert into sessions (user_id, refresh_token_hash, expires_at)
		values ($1, $2, $3)
		returning id::text`,
		u.ID, security.TokenHash(newRefreshToken), newExpiresAt,
	).Scan(&newSessionID)
	if err != nil {
		return User{}, err
	}
	_, err = tx.Exec(ctx, `
		update sessions
		set revoked_at = now(), revoked_reason = 'rotated', replaced_by_session_id = $2
		where id = $1`, sessionID, newSessionID)
	if err != nil {
		return User{}, err
	}
	return u, tx.Commit(ctx)
}

func (s *Store) RevokeRefreshToken(ctx context.Context, refreshToken, reason string) error {
	_, err := s.db.Exec(ctx, `
		update sessions
		set revoked_at = now(), revoked_reason = $2
		where refresh_token_hash = $1 and revoked_at is null`,
		security.TokenHash(refreshToken), reason)
	return err
}

func (s *Store) ListPlans(ctx context.Context) ([]Plan, error) {
	rows, err := s.db.Query(ctx, `
		select id::text, code, name, description, price_cents, price_minor, currency, interval, duration_days,
		       device_limit, traffic_limit_bytes, concurrent_connection_limit, is_active, is_public, sort_order
		from plans
		where is_active = true and is_public = true and deleted_at is null
		order by sort_order asc, price_minor asc`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var plans []Plan
	for rows.Next() {
		var p Plan
		if err := rows.Scan(&p.ID, &p.Code, &p.Name, &p.Description, &p.PriceCents, &p.PriceMinor, &p.Currency, &p.Interval, &p.DurationDays, &p.DeviceLimit, &p.TrafficLimitBytes, &p.ConcurrentConnectionLimit, &p.IsActive, &p.IsPublic, &p.SortOrder); err != nil {
			return nil, err
		}
		plans = append(plans, p)
	}
	return plans, rows.Err()
}

func (s *Store) CreateSubscription(ctx context.Context, userID, planID string) (Subscription, error) {
	return s.CreateSubscriptionFor(ctx, userID, planID, "web", userID)
}

func (s *Store) CreateSubscriptionFor(ctx context.Context, userID, planID, source, createdBy string) (Subscription, error) {
	return s.CreateSubscriptionForOptions(ctx, userID, planID, source, createdBy, "active", nil)
}

func (s *Store) CreateSubscriptionForOptions(ctx context.Context, userID, planID, source, createdBy, status string, currentPeriodEnd *time.Time) (Subscription, error) {
	tx, err := s.db.Begin(ctx)
	if err != nil {
		return Subscription{}, err
	}
	defer tx.Rollback(ctx)

	var sub Subscription
	err = tx.QueryRow(ctx, `
		insert into subscriptions (
			user_id, plan_id, status, source, created_by, current_period_end,
			traffic_limit_bytes_snapshot, device_limit_snapshot, concurrent_connection_limit_snapshot, started_at
		)
		select $1, p.id, $5, $3, $4, coalesce($6::timestamptz, now() + make_interval(days => coalesce(p.duration_days, 30))),
		       p.traffic_limit_bytes, p.device_limit, p.concurrent_connection_limit, case when $5 = 'active' then now() else null end
		from plans p
		where p.id = $2 and p.is_active = true and p.deleted_at is null
		returning id::text, user_id::text, plan_id::text, status, source, source_reference, created_by::text,
		          traffic_limit_bytes_snapshot, device_limit_snapshot, concurrent_connection_limit_snapshot,
		          traffic_limit_override_bytes, device_limit_override, current_period_end, created_at, updated_at`,
		userID, planID, source, createdBy, status, currentPeriodEnd,
	).Scan(&sub.ID, &sub.UserID, &sub.PlanID, &sub.Status, &sub.Source, &sub.SourceReference, &sub.CreatedBy, &sub.TrafficLimitBytesSnapshot, &sub.DeviceLimitSnapshot, &sub.ConcurrentConnectionLimitSnapshot, &sub.TrafficLimitOverrideBytes, &sub.DeviceLimitOverride, &sub.CurrentPeriodEnd, &sub.CreatedAt, &sub.UpdatedAt)
	if err != nil {
		return Subscription{}, err
	}
	payload, _ := json.Marshal(sub)
	if err := insertOutbox(ctx, tx, "subscription.activated", sub.ID, payload); err != nil {
		return Subscription{}, err
	}
	return sub, tx.Commit(ctx)
}

func (s *Store) GetActiveSubscription(ctx context.Context, userID string) (Subscription, error) {
	var sub Subscription
	err := s.db.QueryRow(ctx, `
		select id::text, user_id::text, plan_id::text, status, source, source_reference, created_by::text,
		       traffic_limit_bytes_snapshot, device_limit_snapshot, concurrent_connection_limit_snapshot,
		       traffic_limit_override_bytes, device_limit_override, current_period_end, created_at, updated_at
		from subscriptions
		where user_id = $1 and status = 'active'
		order by created_at desc
		limit 1`, userID,
	).Scan(&sub.ID, &sub.UserID, &sub.PlanID, &sub.Status, &sub.Source, &sub.SourceReference, &sub.CreatedBy, &sub.TrafficLimitBytesSnapshot, &sub.DeviceLimitSnapshot, &sub.ConcurrentConnectionLimitSnapshot, &sub.TrafficLimitOverrideBytes, &sub.DeviceLimitOverride, &sub.CurrentPeriodEnd, &sub.CreatedAt, &sub.UpdatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return Subscription{}, ErrNotFound
	}
	return sub, err
}

func (s *Store) EnrollNode(ctx context.Context, code, region string) (Node, error) {
	tx, err := s.db.Begin(ctx)
	if err != nil {
		return Node{}, err
	}
	defer tx.Rollback(ctx)

	var node Node
	err = tx.QueryRow(ctx, `
		insert into nodes (code, region, status)
		values ($1, $2, 'online')
		on conflict (code) do update set region = excluded.region, status = 'online', updated_at = now()
		returning id::text, code, region, status, last_heartbeat_at`,
		code, region,
	).Scan(&node.ID, &node.Code, &node.Region, &node.Status, &node.LastHeartbeatAt)
	if err != nil {
		return Node{}, err
	}
	payload, _ := json.Marshal(node)
	if err := insertOutbox(ctx, tx, "node.online", node.ID, payload); err != nil {
		return Node{}, err
	}
	return node, tx.Commit(ctx)
}

func (s *Store) CreateNodeEnrollmentToken(ctx context.Context, region, token string, expiresAt time.Time) error {
	_, err := s.db.Exec(ctx, `
		insert into node_enrollment_tokens (token_hash, region, expires_at)
		values ($1, $2, $3)`,
		security.TokenHash(token), region, expiresAt)
	return err
}

func (s *Store) EnrollNodeWithToken(ctx context.Context, code, enrollmentToken, nodeAPIToken string) (Node, error) {
	tx, err := s.db.Begin(ctx)
	if err != nil {
		return Node{}, err
	}
	defer tx.Rollback(ctx)

	var region string
	var tokenID string
	err = tx.QueryRow(ctx, `
		select id::text, region
		from node_enrollment_tokens
		where token_hash = $1 and used_at is null and expires_at > now()
		for update`,
		security.TokenHash(enrollmentToken),
	).Scan(&tokenID, &region)
	if errors.Is(err, pgx.ErrNoRows) {
		return Node{}, ErrNotFound
	}
	if err != nil {
		return Node{}, err
	}

	var node Node
	err = tx.QueryRow(ctx, `
		insert into nodes (code, region, status, api_token_hash)
		values ($1, $2, 'online', $3)
		on conflict (code) do update set
			region = excluded.region,
			status = 'online',
			api_token_hash = excluded.api_token_hash,
			updated_at = now()
		returning id::text, code, region, status, desired_revision, applied_revision, last_sync_error, last_heartbeat_at`,
		code, region, security.TokenHash(nodeAPIToken),
	).Scan(&node.ID, &node.Code, &node.Region, &node.Status, &node.DesiredRevision, &node.AppliedRevision, &node.LastSyncError, &node.LastHeartbeatAt)
	if err != nil {
		return Node{}, err
	}
	if _, err := tx.Exec(ctx, `update node_enrollment_tokens set used_at = now() where id = $1`, tokenID); err != nil {
		return Node{}, err
	}
	payload, _ := json.Marshal(node)
	if err := insertOutbox(ctx, tx, "node.online", node.ID, payload); err != nil {
		return Node{}, err
	}
	return node, tx.Commit(ctx)
}

func (s *Store) GetNodeByAPIToken(ctx context.Context, token string) (Node, error) {
	var node Node
	err := s.db.QueryRow(ctx, `
		select id::text, code, region, status, desired_revision, applied_revision, last_sync_error, last_heartbeat_at
		from nodes
		where api_token_hash = $1`,
		security.TokenHash(token),
	).Scan(&node.ID, &node.Code, &node.Region, &node.Status, &node.DesiredRevision, &node.AppliedRevision, &node.LastSyncError, &node.LastHeartbeatAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return Node{}, ErrNotFound
	}
	return node, err
}

func (s *Store) RecordHeartbeat(ctx context.Context, nodeID string) (Node, error) {
	var node Node
	err := s.db.QueryRow(ctx, `
		update nodes
		set status = 'online', last_heartbeat_at = now(), updated_at = now()
		where id = $1
		returning id::text, code, region, status, desired_revision, applied_revision, last_sync_error, last_heartbeat_at`,
		nodeID,
	).Scan(&node.ID, &node.Code, &node.Region, &node.Status, &node.DesiredRevision, &node.AppliedRevision, &node.LastSyncError, &node.LastHeartbeatAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return Node{}, ErrNotFound
	}
	return node, err
}

func (s *Store) ListNodes(ctx context.Context) ([]Node, error) {
	rows, err := s.db.Query(ctx, `
		select id::text, code, region, status, desired_revision, applied_revision, last_sync_error, last_heartbeat_at
		from nodes order by code`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var nodes []Node
	for rows.Next() {
		var n Node
		if err := rows.Scan(&n.ID, &n.Code, &n.Region, &n.Status, &n.DesiredRevision, &n.AppliedRevision, &n.LastSyncError, &n.LastHeartbeatAt); err != nil {
			return nil, err
		}
		nodes = append(nodes, n)
	}
	return nodes, rows.Err()
}

func (s *Store) CreateDesiredState(ctx context.Context, nodeID string, state json.RawMessage) (DesiredState, error) {
	tx, err := s.db.Begin(ctx)
	if err != nil {
		return DesiredState{}, err
	}
	defer tx.Rollback(ctx)

	var revision int
	err = tx.QueryRow(ctx, `
		update nodes
		set desired_revision = desired_revision + 1, updated_at = now()
		where id = $1
		returning desired_revision`, nodeID).Scan(&revision)
	if err != nil {
		return DesiredState{}, err
	}
	_, err = tx.Exec(ctx, `
		insert into config_versions (node_id, version, desired_state)
		values ($1, $2, $3)`, nodeID, revision, state)
	if err != nil {
		return DesiredState{}, err
	}
	return DesiredState{NodeID: nodeID, Revision: revision, State: state}, tx.Commit(ctx)
}

func (s *Store) LatestDesiredState(ctx context.Context, nodeID string) (DesiredState, error) {
	var state DesiredState
	err := s.db.QueryRow(ctx, `
		select node_id::text, version, desired_state
		from config_versions
		where node_id = $1
		order by version desc
		limit 1`, nodeID,
	).Scan(&state.NodeID, &state.Revision, &state.State)
	if errors.Is(err, pgx.ErrNoRows) {
		return DesiredState{NodeID: nodeID, Revision: 0, State: json.RawMessage(`{}`)}, nil
	}
	return state, err
}

func (s *Store) AckDesiredState(ctx context.Context, nodeID string, revision int) error {
	tx, err := s.db.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)
	if _, err := tx.Exec(ctx, `
		update config_versions
		set acked_at = now(), failed_at = null, failure_message = null
		where node_id = $1 and version = $2`, nodeID, revision); err != nil {
		return err
	}
	if _, err := tx.Exec(ctx, `
		update nodes
		set applied_revision = greatest(applied_revision, $2), last_sync_error = null, updated_at = now()
		where id = $1`, nodeID, revision); err != nil {
		return err
	}
	return tx.Commit(ctx)
}

func (s *Store) FailDesiredState(ctx context.Context, nodeID string, revision int, message string) error {
	tx, err := s.db.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)
	if _, err := tx.Exec(ctx, `
		update config_versions
		set failed_at = now(), failure_message = $3
		where node_id = $1 and version = $2`, nodeID, revision, message); err != nil {
		return err
	}
	if _, err := tx.Exec(ctx, `
		update nodes set last_sync_error = $2, updated_at = now()
		where id = $1`, nodeID, message); err != nil {
		return err
	}
	return tx.Commit(ctx)
}

func (s *Store) CreateAccessGrant(ctx context.Context, userID, nodeID, protocol, deviceID string, expiresAt time.Time) (AccessGrant, error) {
	tx, err := s.db.Begin(ctx)
	if err != nil {
		return AccessGrant{}, err
	}
	defer tx.Rollback(ctx)

	var sub Subscription
	err = tx.QueryRow(ctx, `
		select id::text, user_id::text, plan_id::text, status, source, source_reference, created_by::text,
		       traffic_limit_bytes_snapshot, device_limit_snapshot, concurrent_connection_limit_snapshot,
		       traffic_limit_override_bytes, device_limit_override, current_period_end, created_at, updated_at
		from subscriptions
		where user_id = $1 and status = 'active' and current_period_end > now()
		order by created_at desc
		limit 1`, userID,
	).Scan(&sub.ID, &sub.UserID, &sub.PlanID, &sub.Status, &sub.Source, &sub.SourceReference, &sub.CreatedBy, &sub.TrafficLimitBytesSnapshot, &sub.DeviceLimitSnapshot, &sub.ConcurrentConnectionLimitSnapshot, &sub.TrafficLimitOverrideBytes, &sub.DeviceLimitOverride, &sub.CurrentPeriodEnd, &sub.CreatedAt, &sub.UpdatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return AccessGrant{}, ErrNotFound
	}
	if err != nil {
		return AccessGrant{}, err
	}
	if err := enforceTrafficLimit(ctx, tx, sub); err != nil {
		return AccessGrant{}, err
	}
	var deviceValue any
	if deviceID != "" {
		var activeDeviceID string
		err = tx.QueryRow(ctx, `
			select id::text
			from devices
			where id = $1 and user_id = $2 and revoked_at is null`,
			deviceID, userID,
		).Scan(&activeDeviceID)
		if errors.Is(err, pgx.ErrNoRows) {
			return AccessGrant{}, ErrNotFound
		}
		if err != nil {
			return AccessGrant{}, err
		}
		deviceValue = activeDeviceID
	}

	var grant AccessGrant
	err = tx.QueryRow(ctx, `
		insert into access_grants (user_id, subscription_id, device_id, node_id, protocol, status, expires_at)
		values ($1, $2, $3, $4, $5, 'active', $6)
		returning id::text, user_id::text, subscription_id::text, device_id::text, node_id::text, protocol, status, expires_at, revoked_at, revoked_reason, desired_revision, created_at`,
		userID, sub.ID, deviceValue, nodeID, protocol, expiresAt,
	).Scan(&grant.ID, &grant.UserID, &grant.SubscriptionID, &grant.DeviceID, &grant.NodeID, &grant.Protocol, &grant.Status, &grant.ExpiresAt, &grant.RevokedAt, &grant.RevokedReason, &grant.DesiredRevision, &grant.CreatedAt)
	if err != nil {
		return AccessGrant{}, err
	}
	revision, err := refreshNodeDesiredStateTx(ctx, tx, nodeID)
	if err != nil {
		return AccessGrant{}, err
	}
	grant.DesiredRevision = revision
	_, err = tx.Exec(ctx, `update access_grants set desired_revision = $2, updated_at = now() where id = $1`, grant.ID, revision)
	if err != nil {
		return AccessGrant{}, err
	}
	payload, _ := json.Marshal(grant)
	if err := insertOutbox(ctx, tx, "access.created", grant.ID, payload); err != nil {
		return AccessGrant{}, err
	}
	return grant, tx.Commit(ctx)
}

func (s *Store) ListAccessGrants(ctx context.Context, userID string) ([]AccessGrant, error) {
	rows, err := s.db.Query(ctx, `
		select id::text, user_id::text, subscription_id::text, device_id::text, node_id::text, protocol, status, expires_at, revoked_at, revoked_reason, desired_revision, created_at
		from access_grants
		where user_id = $1
		order by created_at desc`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var grants []AccessGrant
	for rows.Next() {
		var g AccessGrant
		if err := rows.Scan(&g.ID, &g.UserID, &g.SubscriptionID, &g.DeviceID, &g.NodeID, &g.Protocol, &g.Status, &g.ExpiresAt, &g.RevokedAt, &g.RevokedReason, &g.DesiredRevision, &g.CreatedAt); err != nil {
			return nil, err
		}
		grants = append(grants, g)
	}
	return grants, rows.Err()
}

func (s *Store) FetchOutboxBatch(ctx context.Context, limit int) ([]OutboxEvent, error) {
	rows, err := s.db.Query(ctx, `
		select id::text, type, aggregate_id::text, payload, created_at
		from outbox_events
		where published_at is null
		  and next_attempt_at <= now()
		order by created_at
		limit $1`, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var events []OutboxEvent
	for rows.Next() {
		var ev OutboxEvent
		if err := rows.Scan(&ev.ID, &ev.Type, &ev.AggregateID, &ev.Payload, &ev.CreatedAt); err != nil {
			return nil, err
		}
		events = append(events, ev)
	}
	return events, rows.Err()
}

func (s *Store) MarkOutboxPublished(ctx context.Context, id string) error {
	_, err := s.db.Exec(ctx, `update outbox_events set published_at = now(), updated_at = now() where id = $1`, id)
	return err
}

func (s *Store) MarkOutboxFailed(ctx context.Context, id string) error {
	_, err := s.db.Exec(ctx, `
		update outbox_events
		set attempts = attempts + 1,
		    next_attempt_at = now() + make_interval(secs => least(1800, 30 * (2 ^ attempts))::int),
		    updated_at = now()
		where id = $1`, id)
	return err
}

func (s *Store) WriteAuditEvent(ctx context.Context, actorUserID *string, action, targetType string, targetID *string, metadata any) error {
	payload, err := json.Marshal(metadata)
	if err != nil {
		return err
	}
	_, err = s.db.Exec(ctx, `
		insert into audit_events (actor_user_id, action, target_type, target_id, metadata)
		values ($1, $2, $3, $4, $5)`,
		actorUserID, action, targetType, targetID, payload)
	return err
}

func (s *Store) SetUserPassword(ctx context.Context, email, passwordHash string) error {
	tag, err := s.db.Exec(ctx, `
		update users
		set password_hash = $2, password_algo = 'argon2id', updated_at = now()
		where email = $1 and deleted_at is null`, NormalizeEmail(email), passwordHash)
	if err == nil && tag.RowsAffected() == 0 {
		return ErrNotFound
	}
	return normalizeDatabaseError(err)
}

func NormalizeEmail(email string) string {
	return strings.ToLower(strings.TrimSpace(email))
}

func normalizeDatabaseError(err error) error {
	if err == nil {
		return nil
	}
	var pgErr *pgconn.PgError
	if errors.As(err, &pgErr) && pgErr.Code == "23505" {
		return fmt.Errorf("%w: %s", ErrConflict, pgErr.ConstraintName)
	}
	return err
}

func insertOutbox(ctx context.Context, tx pgx.Tx, eventType, aggregateID string, payload []byte) error {
	_, err := tx.Exec(ctx, `
		insert into outbox_events (type, aggregate_id, payload)
		values ($1, $2, $3)`, eventType, aggregateID, payload)
	if err != nil {
		return fmt.Errorf("insert outbox event: %w", err)
	}
	return nil
}
