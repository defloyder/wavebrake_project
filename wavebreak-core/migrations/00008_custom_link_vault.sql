-- +goose Up
-- The user's own VPN links, synced between their devices (owner, 15.10).
-- Off by default in the apps. Stored encrypted (AES-256-GCM, a key derived
-- from the server secret, bound to the user id): one sealed document per
-- account; [version] guards against two devices overwriting each other.
create table if not exists custom_link_vaults (
    user_id uuid primary key references users(id) on delete cascade,
    nonce bytea not null,
    ciphertext bytea not null,
    version bigint not null default 1 check (version > 0),
    updated_at timestamptz not null default now()
);

-- +goose Down
drop table if exists custom_link_vaults;
