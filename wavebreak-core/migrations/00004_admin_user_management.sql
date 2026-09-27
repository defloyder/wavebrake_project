-- +goose Up
-- Admin user management (user details, forced subscription assignment,
-- password reset, device tracking, richer audit). Only adds what was
-- missing; existing tables are extended, nothing is rewritten.

-- 1. One live subscription per user (project rule 2026-09-27). Pilot data
--    had users with two live subscriptions (created before the rule).
--    Keep the one that actually carries traffic (tie: the newest) and
--    close the others, together with their active grants.
with ranked as (
    select s.id,
           row_number() over (
               partition by s.user_id
               order by coalesce(u.bytes_up + u.bytes_down, 0) desc, s.created_at desc
           ) as rn
    from subscriptions s
    left join subscription_usage u on u.subscription_id = s.id
    where s.status in ('pending', 'trialing', 'active', 'past_due', 'suspended')
),
closed as (
    update subscriptions s
    set status = 'cancelled', ended_at = coalesce(s.ended_at, now()), updated_at = now()
    from ranked r
    where r.id = s.id and r.rn > 1
    returning s.id
)
update access_grants g
set status = 'revoked', revoked_at = coalesce(g.revoked_at, now()),
    revoked_reason = coalesce(g.revoked_reason, 'subscription_deduplicated'), updated_at = now()
from closed c
where g.subscription_id = c.id and g.status = 'active';

create unique index if not exists subscriptions_one_live_per_user_idx
    on subscriptions (user_id)
    where status in ('pending', 'trialing', 'active', 'past_due', 'suspended');

create index if not exists subscriptions_user_status_idx on subscriptions (user_id, status);

-- 2. Stable subscription credential: the grant whose id is used in the
--    subscription URL, so the URL doesn't change while the subscription
--    lives. Existing subscriptions fall back to their newest active grant.
alter table subscriptions
    add column if not exists primary_grant_id uuid references access_grants(id) on delete set null;

-- 3. Devices belong to the subscription they were registered under.
alter table devices
    add column if not exists subscription_id uuid references subscriptions(id) on delete set null;
create index if not exists devices_subscription_idx on devices (subscription_id);

-- 4. Password reset: only the SHA-256 hash of the token is stored;
--    one-time (used_at) and short-lived (expires_at).
create table if not exists password_reset_tokens (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references users(id) on delete cascade,
    token_hash text not null unique,
    channel text not null,
    requested_by uuid references users(id) on delete set null,
    expires_at timestamptz not null,
    used_at timestamptz,
    created_at timestamptz not null default now()
);
create index if not exists password_reset_tokens_user_idx on password_reset_tokens (user_id, created_at desc);

-- 5. Audit: who was affected and which request did it.
alter table audit_events
    add column if not exists target_user_id uuid references users(id) on delete set null,
    add column if not exists request_id text;
create index if not exists audit_events_target_user_idx on audit_events (target_user_id, created_at desc);

-- 6. Usage lookups per grant over time.
create index if not exists node_usage_reports_grant_reported_idx on node_usage_reports (grant_id, reported_at);

-- +goose Down
drop index if exists node_usage_reports_grant_reported_idx;
drop index if exists audit_events_target_user_idx;
alter table audit_events drop column if exists request_id, drop column if exists target_user_id;
drop table if exists password_reset_tokens;
drop index if exists devices_subscription_idx;
alter table devices drop column if exists subscription_id;
alter table subscriptions drop column if exists primary_grant_id;
drop index if exists subscriptions_user_status_idx;
drop index if exists subscriptions_one_live_per_user_idx;
