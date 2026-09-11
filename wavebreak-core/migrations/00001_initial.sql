-- +goose Up
create extension if not exists pgcrypto;

create table users (
    id uuid primary key default gen_random_uuid(),
    email text not null unique,
    password_hash text not null,
    password_algo text not null default 'argon2id',
    role text not null default 'user' check (role in ('user', 'support', 'admin', 'superadmin')),
    mfa_secret_ciphertext bytea,
    mfa_enabled_at timestamptz,
    recovery_codes_hash jsonb not null default '[]'::jsonb,
    disabled_at timestamptz,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create table sessions (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references users(id) on delete cascade,
    refresh_token_hash text not null unique,
    expires_at timestamptz not null,
    revoked_at timestamptz,
    revoked_reason text,
    replaced_by_session_id uuid references sessions(id) on delete set null,
    created_at timestamptz not null default now()
);

create index sessions_user_active_idx on sessions (user_id, expires_at) where revoked_at is null;

create table devices (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references users(id) on delete cascade,
    name text not null,
    fingerprint text,
    created_at timestamptz not null default now()
);

create table plans (
    id uuid primary key default gen_random_uuid(),
    code text not null unique,
    name text not null,
    price_cents integer not null check (price_cents >= 0),
    interval text not null check (interval in ('month', 'year')),
    active boolean not null default true,
    created_at timestamptz not null default now()
);

insert into plans (code, name, price_cents, interval) values
    ('starter-monthly', 'Starter', 900, 'month'),
    ('plus-monthly', 'Plus', 1900, 'month'),
    ('fleet-monthly', 'Fleet', 4900, 'month')
on conflict (code) do nothing;

create table subscriptions (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references users(id) on delete cascade,
    plan_id uuid not null references plans(id),
    status text not null check (status in ('trialing', 'active', 'past_due', 'expired', 'cancelled')),
    current_period_end timestamptz not null,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create table payments (
    id uuid primary key default gen_random_uuid(),
    subscription_id uuid references subscriptions(id) on delete set null,
    provider text not null,
    provider_payment_id text,
    amount_cents integer not null,
    currency char(3) not null default 'USD',
    status text not null check (status in ('pending', 'paid', 'failed', 'refunded')),
    created_at timestamptz not null default now()
);

create table nodes (
    id uuid primary key default gen_random_uuid(),
    code text not null unique,
    region text not null,
    status text not null check (status in ('online', 'offline', 'degraded', 'maintenance', 'draining')),
    api_token_hash text unique,
    desired_revision integer not null default 0,
    applied_revision integer not null default 0,
    last_sync_error text,
    last_heartbeat_at timestamptz,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create table node_protocols (
    id uuid primary key default gen_random_uuid(),
    node_id uuid not null references nodes(id) on delete cascade,
    protocol text not null,
    port integer not null,
    enabled boolean not null default true,
    unique (node_id, protocol)
);

create table node_enrollment_tokens (
    id uuid primary key default gen_random_uuid(),
    token_hash text not null unique,
    region text not null,
    expires_at timestamptz not null,
    used_at timestamptz,
    created_at timestamptz not null default now()
);

create table access_credentials (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references users(id) on delete cascade,
    public_key text,
    encrypted_private_material bytea,
    created_at timestamptz not null default now()
);

create table access_grants (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references users(id) on delete cascade,
    node_id uuid not null references nodes(id) on delete cascade,
    protocol text not null,
    status text not null check (status in ('active', 'revoked', 'expired')),
    expires_at timestamptz not null,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create table config_versions (
    id uuid primary key default gen_random_uuid(),
    node_id uuid not null references nodes(id) on delete cascade,
    version integer not null,
    desired_state jsonb not null,
    acked_at timestamptz,
    failed_at timestamptz,
    failure_message text,
    created_at timestamptz not null default now(),
    unique (node_id, version)
);

create index config_versions_node_latest_idx on config_versions (node_id, version desc);

create table audit_events (
    id uuid primary key default gen_random_uuid(),
    actor_user_id uuid references users(id) on delete set null,
    action text not null,
    target_type text not null,
    target_id uuid,
    metadata jsonb not null default '{}'::jsonb,
    created_at timestamptz not null default now()
);

create table webhook_events (
    id uuid primary key default gen_random_uuid(),
    provider text not null,
    provider_event_id text not null,
    payload jsonb not null,
    processed_at timestamptz,
    created_at timestamptz not null default now(),
    unique (provider, provider_event_id)
);

create table idempotency_keys (
    key text primary key,
    request_hash text not null,
    response_code integer,
    response_body jsonb,
    expires_at timestamptz not null,
    created_at timestamptz not null default now()
);

create table outbox_events (
    id uuid primary key default gen_random_uuid(),
    type text not null,
    aggregate_id uuid not null,
    payload jsonb not null,
    attempts integer not null default 0,
    next_attempt_at timestamptz not null default now(),
    published_at timestamptz,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create index outbox_events_pending_idx on outbox_events (next_attempt_at, created_at) where published_at is null;

create table processed_messages (
    message_id text primary key,
    consumer text not null,
    processed_at timestamptz not null default now()
);

create table node_usage_reports (
    id uuid primary key default gen_random_uuid(),
    node_id uuid not null references nodes(id) on delete cascade,
    period_start timestamptz not null,
    period_end timestamptz not null,
    bytes_in bigint not null default 0,
    bytes_out bigint not null default 0,
    created_at timestamptz not null default now()
);

create table notifications (
    id uuid primary key default gen_random_uuid(),
    user_id uuid references users(id) on delete set null,
    channel text not null,
    subject text,
    body text not null,
    status text not null default 'pending',
    created_at timestamptz not null default now(),
    sent_at timestamptz
);

create table admin_actions (
    id uuid primary key default gen_random_uuid(),
    admin_user_id uuid not null references users(id) on delete cascade,
    action text not null,
    payload jsonb not null default '{}'::jsonb,
    created_at timestamptz not null default now()
);

-- +goose Down
drop table if exists admin_actions;
drop table if exists notifications;
drop table if exists node_usage_reports;
drop table if exists processed_messages;
drop table if exists outbox_events;
drop table if exists idempotency_keys;
drop table if exists webhook_events;
drop table if exists audit_events;
drop table if exists config_versions;
drop table if exists access_grants;
drop table if exists access_credentials;
drop table if exists node_enrollment_tokens;
drop table if exists node_protocols;
drop table if exists nodes;
drop table if exists payments;
drop table if exists subscriptions;
drop table if exists plans;
drop table if exists devices;
drop table if exists sessions;
drop table if exists users;
