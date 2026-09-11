-- +goose Up
alter table users
    alter column email drop not null,
    alter column password_hash drop not null,
    add column if not exists username text,
    add column if not exists status text not null default 'active',
    add column if not exists last_login_at timestamptz,
    add column if not exists email_verified_at timestamptz,
    add column if not exists deleted_at timestamptz;

alter table users drop constraint if exists users_status_check;
alter table users add constraint users_status_check check (status in ('active', 'disabled', 'deleted'));
create unique index if not exists users_username_unique_idx on users (lower(username)) where username is not null;

create table if not exists user_identities (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references users(id) on delete cascade,
    provider text not null,
    provider_user_id text not null,
    display_name text,
    username text,
    linked_at timestamptz not null default now(),
    last_seen_at timestamptz,
    metadata jsonb,
    unique (provider, provider_user_id)
);

create index if not exists user_identities_user_idx on user_identities (user_id, provider);

create table if not exists account_link_tokens (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references users(id) on delete cascade,
    provider text not null,
    token_hash text not null unique,
    expires_at timestamptz not null,
    used_at timestamptz,
    created_at timestamptz not null default now()
);

create index if not exists account_link_tokens_user_idx on account_link_tokens (user_id, provider, expires_at desc);

alter table plans
    add column if not exists description text not null default '',
    add column if not exists price_minor integer,
    add column if not exists currency char(3) not null default 'USD',
    add column if not exists duration_days integer,
    add column if not exists device_limit integer not null default 1,
    add column if not exists traffic_limit_bytes bigint,
    add column if not exists concurrent_connection_limit integer,
    add column if not exists is_active boolean,
    add column if not exists is_public boolean not null default true,
    add column if not exists sort_order integer not null default 0,
    add column if not exists updated_at timestamptz not null default now(),
    add column if not exists deleted_at timestamptz;

update plans
set price_minor = coalesce(price_minor, price_cents),
    duration_days = coalesce(duration_days, case interval when 'year' then 365 else 30 end),
    is_active = coalesce(is_active, active),
    traffic_limit_bytes = coalesce(
        traffic_limit_bytes,
        case code
            when 'starter-monthly' then 107374182400::bigint
            when 'plus-monthly' then 322122547200::bigint
            else null
        end
    ),
    concurrent_connection_limit = coalesce(concurrent_connection_limit, device_limit)
where price_minor is null or duration_days is null or is_active is null or traffic_limit_bytes is null or concurrent_connection_limit is null;

alter table plans
    alter column price_minor set not null,
    alter column is_active set not null;

alter table subscriptions drop constraint if exists subscriptions_status_check;
alter table subscriptions add constraint subscriptions_status_check check (status in ('pending', 'trialing', 'active', 'past_due', 'expired', 'cancelled', 'suspended'));
alter table subscriptions
    add column if not exists source text not null default 'web',
    add column if not exists source_reference text,
    add column if not exists created_by uuid references users(id) on delete set null,
    add column if not exists traffic_limit_bytes_snapshot bigint,
    add column if not exists device_limit_snapshot integer,
    add column if not exists concurrent_connection_limit_snapshot integer,
    add column if not exists traffic_limit_override_bytes bigint,
    add column if not exists device_limit_override integer,
    add column if not exists started_at timestamptz,
    add column if not exists ended_at timestamptz;

update subscriptions s
set created_by = coalesce(created_by, user_id),
    started_at = coalesce(started_at, s.created_at),
    traffic_limit_bytes_snapshot = coalesce(traffic_limit_bytes_snapshot, p.traffic_limit_bytes),
    device_limit_snapshot = coalesce(device_limit_snapshot, p.device_limit),
    concurrent_connection_limit_snapshot = coalesce(concurrent_connection_limit_snapshot, p.concurrent_connection_limit)
from plans p
where p.id = s.plan_id;

alter table payments drop constraint if exists payments_status_check;
alter table payments add constraint payments_status_check check (status in ('pending', 'paid', 'failed', 'cancelled', 'refunded'));
alter table payments
    add column if not exists user_id uuid references users(id) on delete set null,
    add column if not exists external_reference text,
    add column if not exists paid_at timestamptz,
    add column if not exists updated_at timestamptz not null default now();

alter table devices
    add column if not exists device_public_id text,
    add column if not exists platform text,
    add column if not exists updated_at timestamptz not null default now(),
    add column if not exists last_seen_at timestamptz,
    add column if not exists revoked_at timestamptz;

update devices
set device_public_id = coalesce(device_public_id, id::text)
where device_public_id is null;

create unique index if not exists devices_public_id_unique_idx on devices (device_public_id);
create index if not exists devices_user_active_idx on devices (user_id, revoked_at);

alter table access_grants
    add column if not exists subscription_id uuid references subscriptions(id) on delete set null,
    add column if not exists device_id uuid references devices(id) on delete set null,
    add column if not exists revoked_at timestamptz,
    add column if not exists revoked_reason text,
    add column if not exists desired_revision integer not null default 0;

create index if not exists access_grants_user_status_idx on access_grants (user_id, status);
create index if not exists access_grants_node_status_idx on access_grants (node_id, status);

create table if not exists subscription_usage (
    subscription_id uuid primary key references subscriptions(id) on delete cascade,
    bytes_up bigint not null default 0,
    bytes_down bigint not null default 0,
    updated_at timestamptz not null default now()
);

create table if not exists subscription_usage_daily (
    subscription_id uuid not null references subscriptions(id) on delete cascade,
    usage_date date not null,
    bytes_up bigint not null default 0,
    bytes_down bigint not null default 0,
    primary key (subscription_id, usage_date)
);

alter table node_usage_reports
    add column if not exists grant_id uuid references access_grants(id) on delete cascade,
    add column if not exists bytes_up_total bigint,
    add column if not exists bytes_down_total bigint,
    add column if not exists reported_at timestamptz;

create index if not exists node_usage_reports_grant_idx on node_usage_reports (grant_id, reported_at desc);

create table if not exists grant_usage_counters (
    grant_id uuid primary key references access_grants(id) on delete cascade,
    subscription_id uuid references subscriptions(id) on delete set null,
    last_bytes_up_total bigint not null default 0,
    last_bytes_down_total bigint not null default 0,
    total_bytes_up bigint not null default 0,
    total_bytes_down bigint not null default 0,
    updated_at timestamptz not null default now()
);

-- +goose Down
drop table if exists grant_usage_counters;
drop table if exists subscription_usage_daily;
drop table if exists subscription_usage;
drop table if exists account_link_tokens;
drop table if exists user_identities;
