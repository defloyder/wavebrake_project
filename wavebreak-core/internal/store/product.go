package store

import (
	"context"
	"encoding/json"
	"errors"
	"time"

	"github.com/jackc/pgx/v5"

	"wavebreak-core/internal/security"
)

type UserIdentity struct {
	ID             string          `json:"id"`
	UserID         string          `json:"user_id"`
	Provider       string          `json:"provider"`
	ProviderUserID string          `json:"provider_user_id"`
	DisplayName    *string         `json:"display_name,omitempty"`
	Username       *string         `json:"username,omitempty"`
	LinkedAt       time.Time       `json:"linked_at"`
	LastSeenAt     *time.Time      `json:"last_seen_at,omitempty"`
	Metadata       json.RawMessage `json:"metadata,omitempty"`
}

type AccountLinkToken struct {
	ID        string    `json:"id"`
	UserID    string    `json:"user_id"`
	Provider  string    `json:"provider"`
	Token     string    `json:"token"`
	ExpiresAt time.Time `json:"expires_at"`
}

type Device struct {
	ID             string     `json:"id"`
	UserID         string     `json:"user_id"`
	DevicePublicID string     `json:"device_public_id"`
	Name           string     `json:"name"`
	Platform       *string    `json:"platform,omitempty"`
	CreatedAt      time.Time  `json:"created_at"`
	UpdatedAt      time.Time  `json:"updated_at"`
	LastSeenAt     *time.Time `json:"last_seen_at,omitempty"`
	RevokedAt      *time.Time `json:"revoked_at,omitempty"`
}

type UsageSummary struct {
	SubscriptionID string `json:"subscription_id"`
	BytesUp        int64  `json:"bytes_up"`
	BytesDown      int64  `json:"bytes_down"`
	BytesTotal     int64  `json:"bytes_total"`
	LimitBytes     *int64 `json:"limit_bytes,omitempty"`
	PercentUsed    *int   `json:"percent_used,omitempty"`
}

type UsageDay struct {
	Date      time.Time `json:"date"`
	BytesUp   int64     `json:"bytes_up"`
	BytesDown int64     `json:"bytes_down"`
}

type UserOverview struct {
	User          User           `json:"user"`
	Subscription  *Subscription  `json:"subscription,omitempty"`
	Usage         *UsageSummary  `json:"usage,omitempty"`
	Devices       []Device       `json:"devices"`
	Telegram      []UserIdentity `json:"telegram"`
	AccessSummary map[string]int `json:"access_summary"`
}

type AdminDashboard struct {
	Users         int64 `json:"users"`
	ActiveUsers   int64 `json:"active_users"`
	Subscriptions int64 `json:"subscriptions"`
	ActiveSubs    int64 `json:"active_subscriptions"`
	Plans         int64 `json:"plans"`
	Nodes         int64 `json:"nodes"`
	NodesOnline   int64 `json:"nodes_online"`
	AccessGrants  int64 `json:"access_grants"`
	BytesTotal    int64 `json:"bytes_total"`
}

type AdminUser struct {
	ID          string     `json:"id"`
	Email       string     `json:"email"`
	Username    string     `json:"username,omitempty"`
	Status      string     `json:"status"`
	Role        string     `json:"role"`
	LastLoginAt *time.Time `json:"last_login_at,omitempty"`
	DisabledAt  *time.Time `json:"disabled_at,omitempty"`
	CreatedAt   time.Time  `json:"created_at"`
}

type AuditEvent struct {
	ID          string          `json:"id"`
	ActorUserID *string         `json:"actor_user_id,omitempty"`
	Action      string          `json:"action"`
	TargetType  string          `json:"target_type"`
	TargetID    *string         `json:"target_id,omitempty"`
	Metadata    json.RawMessage `json:"metadata"`
	CreatedAt   time.Time       `json:"created_at"`
}

type TrafficRow struct {
	SubscriptionID string `json:"subscription_id"`
	UserID         string `json:"user_id"`
	Status         string `json:"status"`
	BytesUp        int64  `json:"bytes_up"`
	BytesDown      int64  `json:"bytes_down"`
	BytesTotal     int64  `json:"bytes_total"`
	LimitBytes     *int64 `json:"limit_bytes,omitempty"`
}

type AccessGrantConfig struct {
	Grant         AccessGrant    `json:"grant"`
	Node          Node           `json:"node"`
	Device        *Device        `json:"device,omitempty"`
	ConfigStatus  string         `json:"config_status"`
	ConfigVersion int            `json:"config_version"`
	WireGuard     map[string]any `json:"wireguard,omitempty"`
	Outline       map[string]any `json:"outline,omitempty"`
	Warnings      []string       `json:"warnings,omitempty"`
}

type ClientBootstrap struct {
	User     User         `json:"user"`
	Overview UserOverview `json:"overview"`
	Plans    []Plan       `json:"plans"`
	Nodes    []Node       `json:"nodes"`
}

func (s *Store) ListUserIdentities(ctx context.Context, userID string) ([]UserIdentity, error) {
	rows, err := s.db.Query(ctx, `
		select id::text, user_id::text, provider, provider_user_id, display_name, username, linked_at, last_seen_at, coalesce(metadata, '{}'::jsonb)
		from user_identities
		where user_id = $1
		order by provider, linked_at desc`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var identities []UserIdentity
	for rows.Next() {
		var identity UserIdentity
		if err := rows.Scan(&identity.ID, &identity.UserID, &identity.Provider, &identity.ProviderUserID, &identity.DisplayName, &identity.Username, &identity.LinkedAt, &identity.LastSeenAt, &identity.Metadata); err != nil {
			return nil, err
		}
		identities = append(identities, identity)
	}
	return identities, rows.Err()
}

func (s *Store) RecordUserLogin(ctx context.Context, userID string) error {
	_, err := s.db.Exec(ctx, `update users set last_login_at = now(), updated_at = now() where id = $1`, userID)
	return err
}

func (s *Store) CreateAccountLinkToken(ctx context.Context, userID, provider, token string, expiresAt time.Time) (AccountLinkToken, error) {
	var result AccountLinkToken
	err := s.db.QueryRow(ctx, `
		insert into account_link_tokens (user_id, provider, token_hash, expires_at)
		values ($1, $2, $3, $4)
		returning id::text, user_id::text, provider, expires_at`,
		userID, provider, security.TokenHash(token), expiresAt,
	).Scan(&result.ID, &result.UserID, &result.Provider, &result.ExpiresAt)
	result.Token = token
	return result, err
}

func (s *Store) UnlinkUserIdentity(ctx context.Context, userID, provider string) error {
	tag, err := s.db.Exec(ctx, `delete from user_identities where user_id = $1 and provider = $2`, userID, provider)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}

func (s *Store) UpsertTelegramIdentity(ctx context.Context, providerUserID, displayName, username string, metadata any) (User, error) {
	tx, err := s.db.Begin(ctx)
	if err != nil {
		return User{}, err
	}
	defer tx.Rollback(ctx)

	meta, err := json.Marshal(metadata)
	if err != nil {
		return User{}, err
	}

	var existingUserID string
	err = tx.QueryRow(ctx, `
		select user_id::text
		from user_identities
		where provider = 'telegram' and provider_user_id = $1
		for update`, providerUserID).Scan(&existingUserID)
	if err != nil && !errors.Is(err, pgx.ErrNoRows) {
		return User{}, err
	}
	if errors.Is(err, pgx.ErrNoRows) {
		err = tx.QueryRow(ctx, `
			insert into users (username, status, role)
			values (nullif($1, ''), 'active', 'user')
			returning id::text`, username).Scan(&existingUserID)
		if err != nil {
			return User{}, err
		}
		_, err = tx.Exec(ctx, `
			insert into user_identities (user_id, provider, provider_user_id, display_name, username, last_seen_at, metadata)
			values ($1, 'telegram', $2, nullif($3, ''), nullif($4, ''), now(), $5)`,
			existingUserID, providerUserID, displayName, username, meta)
		if err != nil {
			return User{}, err
		}
	} else {
		_, err = tx.Exec(ctx, `
			update user_identities
			set display_name = nullif($2, ''), username = nullif($3, ''), last_seen_at = now(), metadata = $4
			where provider = 'telegram' and provider_user_id = $1`,
			providerUserID, displayName, username, meta)
		if err != nil {
			return User{}, err
		}
	}
	if err := tx.Commit(ctx); err != nil {
		return User{}, err
	}
	return s.GetUserByID(ctx, existingUserID)
}

func (s *Store) LinkTelegramWithToken(ctx context.Context, token, providerUserID, displayName, username string, metadata any) (User, error) {
	tx, err := s.db.Begin(ctx)
	if err != nil {
		return User{}, err
	}
	defer tx.Rollback(ctx)

	var userID string
	err = tx.QueryRow(ctx, `
		select user_id::text
		from account_link_tokens
		where provider = 'telegram' and token_hash = $1 and used_at is null and expires_at > now()
		for update`, security.TokenHash(token)).Scan(&userID)
	if errors.Is(err, pgx.ErrNoRows) {
		return User{}, ErrNotFound
	}
	if err != nil {
		return User{}, err
	}
	meta, err := json.Marshal(metadata)
	if err != nil {
		return User{}, err
	}
	if _, err := tx.Exec(ctx, `
		insert into user_identities (user_id, provider, provider_user_id, display_name, username, last_seen_at, metadata)
		values ($1, 'telegram', $2, nullif($3, ''), nullif($4, ''), now(), $5)
		on conflict (provider, provider_user_id) do update set
		    user_id = excluded.user_id,
		    display_name = excluded.display_name,
		    username = excluded.username,
		    last_seen_at = now(),
		    metadata = excluded.metadata`,
		userID, providerUserID, displayName, username, meta); err != nil {
		return User{}, err
	}
	if _, err := tx.Exec(ctx, `
		update account_link_tokens
		set used_at = now()
		where provider = 'telegram' and token_hash = $1`, security.TokenHash(token)); err != nil {
		return User{}, err
	}
	if err := tx.Commit(ctx); err != nil {
		return User{}, err
	}
	return s.GetUserByID(ctx, userID)
}

func (s *Store) ListDevices(ctx context.Context, userID string) ([]Device, error) {
	rows, err := s.db.Query(ctx, `
		select id::text, user_id::text, device_public_id, name, platform, created_at, updated_at, last_seen_at, revoked_at
		from devices
		where user_id = $1
		order by revoked_at nulls first, created_at desc`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var devices []Device
	for rows.Next() {
		var d Device
		if err := rows.Scan(&d.ID, &d.UserID, &d.DevicePublicID, &d.Name, &d.Platform, &d.CreatedAt, &d.UpdatedAt, &d.LastSeenAt, &d.RevokedAt); err != nil {
			return nil, err
		}
		devices = append(devices, d)
	}
	return devices, rows.Err()
}

func (s *Store) CreateDevice(ctx context.Context, userID, name, platform string) (Device, error) {
	tx, err := s.db.Begin(ctx)
	if err != nil {
		return Device{}, err
	}
	defer tx.Rollback(ctx)

	limit, err := effectiveDeviceLimit(ctx, tx, userID)
	if err != nil {
		return Device{}, err
	}
	var activeCount int
	if err := tx.QueryRow(ctx, `select count(*) from devices where user_id = $1 and revoked_at is null`, userID).Scan(&activeCount); err != nil {
		return Device{}, err
	}
	if limit > 0 && activeCount >= limit {
		return Device{}, ErrLimitReached
	}

	var d Device
	err = tx.QueryRow(ctx, `
		insert into devices (user_id, name, platform)
		values ($1, $2, nullif($3, ''))
		returning id::text, user_id::text, coalesce(device_public_id, ''), name, platform, created_at, updated_at, last_seen_at, revoked_at`,
		userID, name, platform,
	).Scan(&d.ID, &d.UserID, &d.DevicePublicID, &d.Name, &d.Platform, &d.CreatedAt, &d.UpdatedAt, &d.LastSeenAt, &d.RevokedAt)
	if err != nil {
		return Device{}, err
	}
	if _, err := tx.Exec(ctx, `update devices set device_public_id = $2 where id = $1`, d.ID, d.ID); err != nil {
		return Device{}, err
	}
	d.DevicePublicID = d.ID
	return d, tx.Commit(ctx)
}

func (s *Store) UpdateDevice(ctx context.Context, userID, deviceID, name, platform string) (Device, error) {
	var d Device
	err := s.db.QueryRow(ctx, `
		update devices
		set name = coalesce(nullif($3, ''), name),
		    platform = coalesce(nullif($4, ''), platform),
		    updated_at = now()
		where user_id = $1 and id = $2 and revoked_at is null
		returning id::text, user_id::text, device_public_id, name, platform, created_at, updated_at, last_seen_at, revoked_at`,
		userID, deviceID, name, platform,
	).Scan(&d.ID, &d.UserID, &d.DevicePublicID, &d.Name, &d.Platform, &d.CreatedAt, &d.UpdatedAt, &d.LastSeenAt, &d.RevokedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return Device{}, ErrNotFound
	}
	return d, err
}

func (s *Store) RevokeDevice(ctx context.Context, userID, deviceID string) error {
	tag, err := s.db.Exec(ctx, `
		update devices
		set revoked_at = coalesce(revoked_at, now()), updated_at = now()
		where user_id = $1 and id = $2`, userID, deviceID)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}

func (s *Store) UsageSummary(ctx context.Context, userID string) (UsageSummary, error) {
	sub, err := s.GetActiveSubscription(ctx, userID)
	if err != nil {
		return UsageSummary{}, err
	}
	limit := effectiveTrafficLimit(sub)
	var usage UsageSummary
	err = s.db.QueryRow(ctx, `
		select s.id::text, coalesce(u.bytes_up, 0), coalesce(u.bytes_down, 0), coalesce(u.bytes_up + u.bytes_down, 0)
		from subscriptions s
		left join subscription_usage u on u.subscription_id = s.id
		where s.id = $1`, sub.ID,
	).Scan(&usage.SubscriptionID, &usage.BytesUp, &usage.BytesDown, &usage.BytesTotal)
	if err != nil {
		return UsageSummary{}, err
	}
	usage.LimitBytes = limit
	if limit != nil && *limit > 0 {
		pct := int((usage.BytesTotal * 100) / *limit)
		usage.PercentUsed = &pct
	}
	return usage, nil
}

func (s *Store) UsageHistory(ctx context.Context, userID string, days int) ([]UsageDay, error) {
	sub, err := s.GetActiveSubscription(ctx, userID)
	if err != nil {
		return nil, err
	}
	rows, err := s.db.Query(ctx, `
		select usage_date::timestamptz, bytes_up, bytes_down
		from subscription_usage_daily
		where subscription_id = $1 and usage_date >= current_date - ($2::int - 1)
		order by usage_date`, sub.ID, days)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var history []UsageDay
	for rows.Next() {
		var d UsageDay
		if err := rows.Scan(&d.Date, &d.BytesUp, &d.BytesDown); err != nil {
			return nil, err
		}
		history = append(history, d)
	}
	return history, rows.Err()
}

func (s *Store) UserOverview(ctx context.Context, userID string) (UserOverview, error) {
	user, err := s.GetUserByID(ctx, userID)
	if err != nil {
		return UserOverview{}, err
	}
	devices, err := s.ListDevices(ctx, userID)
	if err != nil {
		return UserOverview{}, err
	}
	identities, err := s.ListUserIdentities(ctx, userID)
	if err != nil {
		return UserOverview{}, err
	}
	grants, err := s.ListAccessGrants(ctx, userID)
	if err != nil {
		return UserOverview{}, err
	}
	summary := map[string]int{"active": 0, "revoked": 0, "expired": 0}
	for _, grant := range grants {
		summary[grant.Status]++
	}
	overview := UserOverview{User: user, Devices: devices, Telegram: identities, AccessSummary: summary}
	sub, err := s.GetActiveSubscription(ctx, userID)
	if err == nil {
		overview.Subscription = &sub
		usage, err := s.UsageSummary(ctx, userID)
		if err == nil {
			overview.Usage = &usage
		}
	} else if !errors.Is(err, ErrNotFound) {
		return UserOverview{}, err
	}
	return overview, nil
}

func (s *Store) ClientBootstrap(ctx context.Context, userID string) (ClientBootstrap, error) {
	user, err := s.GetUserByID(ctx, userID)
	if err != nil {
		return ClientBootstrap{}, err
	}
	overview, err := s.UserOverview(ctx, userID)
	if err != nil {
		return ClientBootstrap{}, err
	}
	plans, err := s.ListPlans(ctx)
	if err != nil {
		return ClientBootstrap{}, err
	}
	nodes, err := s.ListNodes(ctx)
	if err != nil {
		return ClientBootstrap{}, err
	}
	return ClientBootstrap{User: user, Overview: overview, Plans: plans, Nodes: nodes}, nil
}

func (s *Store) AccessGrantConfig(ctx context.Context, userID, grantID string) (AccessGrantConfig, error) {
	var grant AccessGrant
	err := s.db.QueryRow(ctx, `
		select id::text, user_id::text, subscription_id::text, device_id::text, node_id::text, protocol, status, expires_at, revoked_at, revoked_reason, desired_revision, created_at
		from access_grants
		where id = $1 and user_id = $2`, grantID, userID,
	).Scan(&grant.ID, &grant.UserID, &grant.SubscriptionID, &grant.DeviceID, &grant.NodeID, &grant.Protocol, &grant.Status, &grant.ExpiresAt, &grant.RevokedAt, &grant.RevokedReason, &grant.DesiredRevision, &grant.CreatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return AccessGrantConfig{}, ErrNotFound
	}
	if err != nil {
		return AccessGrantConfig{}, err
	}
	var node Node
	err = s.db.QueryRow(ctx, `
		select id::text, code, region, status, desired_revision, applied_revision, last_sync_error, last_heartbeat_at
		from nodes
		where id = $1`, grant.NodeID,
	).Scan(&node.ID, &node.Code, &node.Region, &node.Status, &node.DesiredRevision, &node.AppliedRevision, &node.LastSyncError, &node.LastHeartbeatAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return AccessGrantConfig{}, ErrNotFound
	}
	if err != nil {
		return AccessGrantConfig{}, err
	}

	var device *Device
	if grant.DeviceID != nil {
		var d Device
		err := s.db.QueryRow(ctx, `
			select id::text, user_id::text, device_public_id, name, platform, created_at, updated_at, last_seen_at, revoked_at
			from devices
			where id = $1 and user_id = $2`, *grant.DeviceID, userID,
		).Scan(&d.ID, &d.UserID, &d.DevicePublicID, &d.Name, &d.Platform, &d.CreatedAt, &d.UpdatedAt, &d.LastSeenAt, &d.RevokedAt)
		if err != nil && !errors.Is(err, pgx.ErrNoRows) {
			return AccessGrantConfig{}, err
		}
		if err == nil {
			device = &d
		}
	}

	result := AccessGrantConfig{
		Grant:         grant,
		Node:          node,
		Device:        device,
		ConfigStatus:  "pending_runtime_config",
		ConfigVersion: grant.DesiredRevision,
		Warnings: []string{
			"VPN runtime config generation is intentionally not active yet.",
			"Use this response shape for mobile/desktop integration; real peer keys/endpoints will be filled by the VPN config implementation pass.",
		},
	}
	switch grant.Protocol {
	case "outline":
		result.Outline = map[string]any{
			"access_url": nil,
			"server":     map[string]any{"region": node.Region, "code": node.Code},
		}
	default:
		result.WireGuard = map[string]any{
			"interface": map[string]any{
				"private_key": "client_generated",
				"address":     nil,
				"dns":         []string{"1.1.1.1", "1.0.0.1"},
				"mtu":         1420,
			},
			"peer": map[string]any{
				"public_key":           nil,
				"preshared_key":        nil,
				"endpoint":             nil,
				"allowed_ips":          []string{"0.0.0.0/0", "::/0"},
				"persistent_keepalive": 25,
			},
		}
	}
	return result, nil
}

func (s *Store) RevokeAccessGrant(ctx context.Context, actorUserID, grantID, reason string) (AccessGrant, error) {
	tx, err := s.db.Begin(ctx)
	if err != nil {
		return AccessGrant{}, err
	}
	defer tx.Rollback(ctx)

	var grant AccessGrant
	err = tx.QueryRow(ctx, `
		update access_grants
		set status = 'revoked', revoked_at = coalesce(revoked_at, now()), revoked_reason = coalesce(nullif($3, ''), 'manual'), updated_at = now()
		where id = $1 and ($2::text = '' or user_id::text = $2)
		returning id::text, user_id::text, subscription_id::text, device_id::text, node_id::text, protocol, status, expires_at, revoked_at, revoked_reason, desired_revision, created_at`,
		grantID, actorUserID, reason,
	).Scan(&grant.ID, &grant.UserID, &grant.SubscriptionID, &grant.DeviceID, &grant.NodeID, &grant.Protocol, &grant.Status, &grant.ExpiresAt, &grant.RevokedAt, &grant.RevokedReason, &grant.DesiredRevision, &grant.CreatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return AccessGrant{}, ErrNotFound
	}
	if err != nil {
		return AccessGrant{}, err
	}
	revision, err := refreshNodeDesiredStateTx(ctx, tx, grant.NodeID)
	if err != nil {
		return AccessGrant{}, err
	}
	grant.DesiredRevision = revision
	if _, err := tx.Exec(ctx, `update access_grants set desired_revision = $2, updated_at = now() where id = $1`, grant.ID, revision); err != nil {
		return AccessGrant{}, err
	}
	payload, _ := json.Marshal(grant)
	if err := insertOutbox(ctx, tx, "access.revoked", grant.ID, payload); err != nil {
		return AccessGrant{}, err
	}
	return grant, tx.Commit(ctx)
}

func (s *Store) RecordNodeUsageReport(ctx context.Context, nodeID, grantID string, upTotal, downTotal int64, reportedAt time.Time) error {
	tx, err := s.db.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)

	var subscriptionID string
	if err := tx.QueryRow(ctx, `
		select subscription_id::text
		from access_grants
		where id = $1 and node_id = $2 and status = 'active'`,
		grantID, nodeID).Scan(&subscriptionID); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return ErrNotFound
		}
		return err
	}

	var lastUp, lastDown, totalUp, totalDown int64
	err = tx.QueryRow(ctx, `
		select last_bytes_up_total, last_bytes_down_total, total_bytes_up, total_bytes_down
		from grant_usage_counters
		where grant_id = $1
		for update`, grantID).Scan(&lastUp, &lastDown, &totalUp, &totalDown)
	if err != nil && !errors.Is(err, pgx.ErrNoRows) {
		return err
	}
	if errors.Is(err, pgx.ErrNoRows) {
		lastUp, lastDown, totalUp, totalDown = 0, 0, 0, 0
	}
	deltaUp := monotonicDelta(lastUp, upTotal)
	deltaDown := monotonicDelta(lastDown, downTotal)
	nextUp := totalUp + deltaUp
	nextDown := totalDown + deltaDown

	if _, err := tx.Exec(ctx, `
		insert into node_usage_reports (node_id, period_start, period_end, bytes_in, bytes_out, grant_id, bytes_up_total, bytes_down_total, reported_at)
		values ($1, $4, $4, $2, $3, $5, $6, $7, $4)`,
		nodeID, deltaDown, deltaUp, reportedAt, grantID, upTotal, downTotal); err != nil {
		return err
	}
	if _, err := tx.Exec(ctx, `
		insert into grant_usage_counters (grant_id, subscription_id, last_bytes_up_total, last_bytes_down_total, total_bytes_up, total_bytes_down)
		values ($1, $2, $3, $4, $5, $6)
		on conflict (grant_id) do update set
		    subscription_id = excluded.subscription_id,
		    last_bytes_up_total = excluded.last_bytes_up_total,
		    last_bytes_down_total = excluded.last_bytes_down_total,
		    total_bytes_up = excluded.total_bytes_up,
		    total_bytes_down = excluded.total_bytes_down,
		    updated_at = now()`,
		grantID, subscriptionID, upTotal, downTotal, nextUp, nextDown); err != nil {
		return err
	}
	if _, err := tx.Exec(ctx, `
		insert into subscription_usage (subscription_id, bytes_up, bytes_down)
		values ($1, $2, $3)
		on conflict (subscription_id) do update set
		    bytes_up = subscription_usage.bytes_up + excluded.bytes_up,
		    bytes_down = subscription_usage.bytes_down + excluded.bytes_down,
		    updated_at = now()`,
		subscriptionID, deltaUp, deltaDown); err != nil {
		return err
	}
	if _, err := tx.Exec(ctx, `
		insert into subscription_usage_daily (subscription_id, usage_date, bytes_up, bytes_down)
		values ($1, $4::date, $2, $3)
		on conflict (subscription_id, usage_date) do update set
		    bytes_up = subscription_usage_daily.bytes_up + excluded.bytes_up,
		    bytes_down = subscription_usage_daily.bytes_down + excluded.bytes_down`,
		subscriptionID, deltaUp, deltaDown, reportedAt); err != nil {
		return err
	}
	return tx.Commit(ctx)
}

func (s *Store) AdminDashboard(ctx context.Context) (AdminDashboard, error) {
	var d AdminDashboard
	err := s.db.QueryRow(ctx, `
		select
		  (select count(*) from users where deleted_at is null),
		  (select count(*) from users where status = 'active' and deleted_at is null),
		  (select count(*) from subscriptions),
		  (select count(*) from subscriptions where status = 'active'),
		  (select count(*) from plans where deleted_at is null),
		  (select count(*) from nodes),
		  (select count(*) from nodes where status = 'online'),
		  (select count(*) from access_grants),
		  (select coalesce(sum(bytes_up + bytes_down), 0) from subscription_usage)`,
	).Scan(&d.Users, &d.ActiveUsers, &d.Subscriptions, &d.ActiveSubs, &d.Plans, &d.Nodes, &d.NodesOnline, &d.AccessGrants, &d.BytesTotal)
	return d, err
}

func (s *Store) ListUsers(ctx context.Context) ([]AdminUser, error) {
	rows, err := s.db.Query(ctx, `
		select id::text, coalesce(email, ''), coalesce(username, ''), status, role, last_login_at, disabled_at, created_at
		from users
		where deleted_at is null
		order by created_at desc
		limit 200`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var users []AdminUser
	for rows.Next() {
		var u AdminUser
		if err := rows.Scan(&u.ID, &u.Email, &u.Username, &u.Status, &u.Role, &u.LastLoginAt, &u.DisabledAt, &u.CreatedAt); err != nil {
			return nil, err
		}
		users = append(users, u)
	}
	return users, rows.Err()
}

func (s *Store) ListAllPlans(ctx context.Context) ([]Plan, error) {
	rows, err := s.db.Query(ctx, `
		select id::text, code, name, description, price_cents, price_minor, currency, interval, duration_days,
		       device_limit, traffic_limit_bytes, concurrent_connection_limit, is_active, is_public, sort_order
		from plans
		where deleted_at is null
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

func (s *Store) CreatePlan(ctx context.Context, p Plan) (Plan, error) {
	if p.Currency == "" {
		p.Currency = "USD"
	}
	if p.Interval == "" {
		p.Interval = "month"
	}
	if p.DurationDays == nil {
		days := 30
		if p.Interval == "year" {
			days = 365
		}
		p.DurationDays = &days
	}
	err := s.db.QueryRow(ctx, `
		insert into plans (
			code, name, description, price_cents, price_minor, currency, interval, duration_days,
			device_limit, traffic_limit_bytes, concurrent_connection_limit, active, is_active, is_public, sort_order
		)
		values ($1, $2, $3, $4, $4, $5, $6, $7, $8, $9, $10, $11, $11, $12, $13)
		returning id::text, code, name, description, price_cents, price_minor, currency, interval, duration_days,
		          device_limit, traffic_limit_bytes, concurrent_connection_limit, is_active, is_public, sort_order`,
		p.Code, p.Name, p.Description, p.PriceMinor, p.Currency, p.Interval, p.DurationDays,
		p.DeviceLimit, p.TrafficLimitBytes, p.ConcurrentConnectionLimit, p.IsActive, p.IsPublic, p.SortOrder,
	).Scan(&p.ID, &p.Code, &p.Name, &p.Description, &p.PriceCents, &p.PriceMinor, &p.Currency, &p.Interval, &p.DurationDays, &p.DeviceLimit, &p.TrafficLimitBytes, &p.ConcurrentConnectionLimit, &p.IsActive, &p.IsPublic, &p.SortOrder)
	return p, err
}

func (s *Store) UpdatePlan(ctx context.Context, p Plan) (Plan, error) {
	err := s.db.QueryRow(ctx, `
		update plans
		set code = $2,
		    name = $3,
		    description = $4,
		    price_cents = $5,
		    price_minor = $5,
		    currency = $6,
		    interval = $7,
		    duration_days = $8,
		    device_limit = $9,
		    traffic_limit_bytes = $10,
		    concurrent_connection_limit = $11,
		    active = $12,
		    is_active = $12,
		    is_public = $13,
		    sort_order = $14,
		    updated_at = now()
		where id = $1 and deleted_at is null
		returning id::text, code, name, description, price_cents, price_minor, currency, interval, duration_days,
		          device_limit, traffic_limit_bytes, concurrent_connection_limit, is_active, is_public, sort_order`,
		p.ID, p.Code, p.Name, p.Description, p.PriceMinor, p.Currency, p.Interval, p.DurationDays,
		p.DeviceLimit, p.TrafficLimitBytes, p.ConcurrentConnectionLimit, p.IsActive, p.IsPublic, p.SortOrder,
	).Scan(&p.ID, &p.Code, &p.Name, &p.Description, &p.PriceCents, &p.PriceMinor, &p.Currency, &p.Interval, &p.DurationDays, &p.DeviceLimit, &p.TrafficLimitBytes, &p.ConcurrentConnectionLimit, &p.IsActive, &p.IsPublic, &p.SortOrder)
	if errors.Is(err, pgx.ErrNoRows) {
		return Plan{}, ErrNotFound
	}
	return p, err
}

func (s *Store) SoftDeletePlan(ctx context.Context, planID string) error {
	tag, err := s.db.Exec(ctx, `update plans set deleted_at = now(), active = false, is_active = false, updated_at = now() where id = $1 and deleted_at is null`, planID)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}

func (s *Store) ListAllSubscriptions(ctx context.Context) ([]Subscription, error) {
	rows, err := s.db.Query(ctx, `
		select id::text, user_id::text, plan_id::text, status, source, source_reference, created_by::text,
		       traffic_limit_bytes_snapshot, device_limit_snapshot, concurrent_connection_limit_snapshot,
		       traffic_limit_override_bytes, device_limit_override, current_period_end, created_at, updated_at
		from subscriptions
		order by created_at desc
		limit 200`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var subs []Subscription
	for rows.Next() {
		var sub Subscription
		if err := rows.Scan(&sub.ID, &sub.UserID, &sub.PlanID, &sub.Status, &sub.Source, &sub.SourceReference, &sub.CreatedBy, &sub.TrafficLimitBytesSnapshot, &sub.DeviceLimitSnapshot, &sub.ConcurrentConnectionLimitSnapshot, &sub.TrafficLimitOverrideBytes, &sub.DeviceLimitOverride, &sub.CurrentPeriodEnd, &sub.CreatedAt, &sub.UpdatedAt); err != nil {
			return nil, err
		}
		subs = append(subs, sub)
	}
	return subs, rows.Err()
}

func (s *Store) UpdateSubscriptionStatus(ctx context.Context, subscriptionID, status string) (Subscription, error) {
	var sub Subscription
	err := s.db.QueryRow(ctx, `
		update subscriptions
		set status = $2,
		    ended_at = case when $2 in ('expired', 'cancelled') then now() else ended_at end,
		    updated_at = now()
		where id = $1
		returning id::text, user_id::text, plan_id::text, status, source, source_reference, created_by::text,
		          traffic_limit_bytes_snapshot, device_limit_snapshot, concurrent_connection_limit_snapshot,
		          traffic_limit_override_bytes, device_limit_override, current_period_end, created_at, updated_at`,
		subscriptionID, status,
	).Scan(&sub.ID, &sub.UserID, &sub.PlanID, &sub.Status, &sub.Source, &sub.SourceReference, &sub.CreatedBy, &sub.TrafficLimitBytesSnapshot, &sub.DeviceLimitSnapshot, &sub.ConcurrentConnectionLimitSnapshot, &sub.TrafficLimitOverrideBytes, &sub.DeviceLimitOverride, &sub.CurrentPeriodEnd, &sub.CreatedAt, &sub.UpdatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return Subscription{}, ErrNotFound
	}
	return sub, err
}

func (s *Store) ListAllDevices(ctx context.Context) ([]Device, error) {
	rows, err := s.db.Query(ctx, `
		select id::text, user_id::text, device_public_id, name, platform, created_at, updated_at, last_seen_at, revoked_at
		from devices
		order by created_at desc
		limit 200`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var devices []Device
	for rows.Next() {
		var d Device
		if err := rows.Scan(&d.ID, &d.UserID, &d.DevicePublicID, &d.Name, &d.Platform, &d.CreatedAt, &d.UpdatedAt, &d.LastSeenAt, &d.RevokedAt); err != nil {
			return nil, err
		}
		devices = append(devices, d)
	}
	return devices, rows.Err()
}

func (s *Store) AdminRevokeDevice(ctx context.Context, deviceID string) error {
	tag, err := s.db.Exec(ctx, `update devices set revoked_at = coalesce(revoked_at, now()), updated_at = now() where id = $1`, deviceID)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}

func (s *Store) ListTrafficRows(ctx context.Context) ([]TrafficRow, error) {
	rows, err := s.db.Query(ctx, `
		select s.id::text, s.user_id::text, s.status,
		       coalesce(u.bytes_up, 0),
		       coalesce(u.bytes_down, 0),
		       coalesce(u.bytes_up + u.bytes_down, 0),
		       coalesce(s.traffic_limit_override_bytes, s.traffic_limit_bytes_snapshot)
		from subscriptions s
		left join subscription_usage u on u.subscription_id = s.id
		order by u.updated_at desc nulls last, s.created_at desc
		limit 200`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var result []TrafficRow
	for rows.Next() {
		var row TrafficRow
		if err := rows.Scan(&row.SubscriptionID, &row.UserID, &row.Status, &row.BytesUp, &row.BytesDown, &row.BytesTotal, &row.LimitBytes); err != nil {
			return nil, err
		}
		result = append(result, row)
	}
	return result, rows.Err()
}

func (s *Store) ListAuditEvents(ctx context.Context) ([]AuditEvent, error) {
	rows, err := s.db.Query(ctx, `
		select id::text, actor_user_id::text, action, target_type, target_id::text, metadata, created_at
		from audit_events
		order by created_at desc
		limit 200`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var events []AuditEvent
	for rows.Next() {
		var ev AuditEvent
		if err := rows.Scan(&ev.ID, &ev.ActorUserID, &ev.Action, &ev.TargetType, &ev.TargetID, &ev.Metadata, &ev.CreatedAt); err != nil {
			return nil, err
		}
		events = append(events, ev)
	}
	return events, rows.Err()
}

func (s *Store) ListAllAccessGrants(ctx context.Context) ([]AccessGrant, error) {
	rows, err := s.db.Query(ctx, `
		select id::text, user_id::text, subscription_id::text, device_id::text, node_id::text, protocol, status, expires_at, revoked_at, revoked_reason, desired_revision, created_at
		from access_grants
		order by created_at desc
		limit 200`)
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

func monotonicDelta(previous, current int64) int64 {
	if current >= previous {
		return current - previous
	}
	return current
}

func effectiveTrafficLimit(sub Subscription) *int64 {
	if sub.TrafficLimitOverrideBytes != nil {
		return sub.TrafficLimitOverrideBytes
	}
	return sub.TrafficLimitBytesSnapshot
}

func enforceTrafficLimit(ctx context.Context, tx pgx.Tx, sub Subscription) error {
	limit := effectiveTrafficLimit(sub)
	if limit == nil || *limit <= 0 {
		return nil
	}
	var used int64
	if err := tx.QueryRow(ctx, `select coalesce(bytes_up + bytes_down, 0) from subscription_usage where subscription_id = $1`, sub.ID).Scan(&used); err != nil && !errors.Is(err, pgx.ErrNoRows) {
		return err
	}
	if used >= *limit {
		return ErrLimitReached
	}
	return nil
}

func effectiveDeviceLimit(ctx context.Context, tx pgx.Tx, userID string) (int, error) {
	var limit int
	err := tx.QueryRow(ctx, `
		select coalesce(s.device_limit_override, s.device_limit_snapshot, p.device_limit, 1)
		from subscriptions s
		join plans p on p.id = s.plan_id
		where s.user_id = $1 and s.status = 'active'
		order by s.created_at desc
		limit 1`, userID).Scan(&limit)
	if errors.Is(err, pgx.ErrNoRows) {
		return 1, nil
	}
	return limit, err
}

func refreshNodeDesiredStateTx(ctx context.Context, tx pgx.Tx, nodeID string) (int, error) {
	var revision int
	if err := tx.QueryRow(ctx, `
		update nodes
		set desired_revision = desired_revision + 1, updated_at = now()
		where id = $1
		returning desired_revision`, nodeID).Scan(&revision); err != nil {
		return 0, err
	}
	var desired json.RawMessage
	if err := tx.QueryRow(ctx, `
		select jsonb_build_object(
		    'revision', $2::int,
		    'node_id', $1::uuid,
		    'grants', coalesce(jsonb_agg(jsonb_build_object(
		        'id', id,
		        'user_id', user_id,
		        'subscription_id', subscription_id,
		        'device_id', device_id,
		        'protocol', protocol,
		        'status', status,
		        'expires_at', expires_at
		    ) order by created_at) filter (where id is not null), '[]'::jsonb)
		)
		from access_grants
		where node_id = $1 and status = 'active' and expires_at > now()`, nodeID, revision).Scan(&desired); err != nil {
		return 0, err
	}
	if _, err := tx.Exec(ctx, `
		insert into config_versions (node_id, version, desired_state)
		values ($1, $2, $3)`, nodeID, revision, desired); err != nil {
		return 0, err
	}
	return revision, nil
}
