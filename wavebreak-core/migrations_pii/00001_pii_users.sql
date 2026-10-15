-- +goose Up
create table pii_users (
    user_id uuid primary key,
    email text unique check (email is null or (email <> '' and email = lower(btrim(email)))),
    username text,
    password_hash text,
    password_algo text not null default 'argon2id',
    email_verified_at timestamptz,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create unique index pii_users_username_unique_idx on pii_users (lower(username)) where username is not null;

-- +goose Down
drop table if exists pii_users;
