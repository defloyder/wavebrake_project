-- +goose Up
-- Offers and promo codes (P9). Additive only: existing plans and
-- subscriptions are untouched.

-- A discount shown on a plan: the price before it (struck through in the
-- apps) and a short label ("-20%", "Хит"). Both optional.
alter table plans add column if not exists original_price_minor bigint check (original_price_minor is null or original_price_minor >= 0);
alter table plans add column if not exists badge text not null default '';

-- A promo code: a percent or a fixed amount off, optionally only for one
-- plan, valid within a window, up to a number of activations. Codes are
-- stored upper-case and matched case-insensitively.
create table if not exists promo_codes (
    id uuid primary key default gen_random_uuid(),
    code text not null unique check (code = upper(code) and length(code) between 3 and 40),
    description text not null default '',
    discount_type text not null check (discount_type in ('percent', 'fixed')),
    -- percent: 1..100; fixed: minor units of [currency].
    discount_value bigint not null check (discount_value > 0),
    currency text,
    plan_id uuid references plans(id) on delete set null,
    valid_from timestamptz,
    valid_until timestamptz,
    max_activations integer check (max_activations is null or max_activations > 0),
    activations_count integer not null default 0,
    is_active boolean not null default true,
    created_by uuid references users(id) on delete set null,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    check (discount_type <> 'percent' or discount_value <= 100),
    check (discount_type <> 'fixed' or currency is not null),
    check (valid_until is null or valid_from is null or valid_until > valid_from)
);

-- One activation per user and code; written when a purchase with the code
-- goes through (the payment step), not when the code is only checked.
create table if not exists promo_redemptions (
    id uuid primary key default gen_random_uuid(),
    promo_code_id uuid not null references promo_codes(id) on delete cascade,
    user_id uuid not null references users(id) on delete cascade,
    plan_id uuid references plans(id) on delete set null,
    subscription_id uuid references subscriptions(id) on delete set null,
    created_at timestamptz not null default now(),
    unique (promo_code_id, user_id)
);

-- +goose Down
drop table if exists promo_redemptions;
drop table if exists promo_codes;
alter table plans drop column if exists badge, drop column if exists original_price_minor;
