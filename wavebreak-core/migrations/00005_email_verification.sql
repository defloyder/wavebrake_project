-- +goose Up
-- Email verification for app sign-ups. Additive only: existing accounts
-- keep working unchanged (email_verification_required defaults to false —
-- they may confirm their address from the app, but are never locked out).

alter table users add column if not exists email_verified_at timestamptz;
-- Set for accounts created by an app that runs the verification step;
-- such an account can't sign in until the address is confirmed.
alter table users add column if not exists email_verification_required boolean not null default false;
-- Language of the emails this user gets ('ru' / 'en').
alter table users add column if not exists email_language text not null default 'ru';

-- One pending code per user: a new code replaces the old one. Only the
-- hash is stored; attempts are counted to stop guessing.
create table if not exists email_verification_codes (
    user_id uuid primary key references users(id) on delete cascade,
    code_hash text not null,
    expires_at timestamptz not null,
    attempts integer not null default 0,
    sent_at timestamptz not null default now()
);

-- +goose Down
drop table if exists email_verification_codes;
alter table users drop column if exists email_language,
    drop column if exists email_verification_required,
    drop column if exists email_verified_at;
