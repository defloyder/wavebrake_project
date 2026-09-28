-- +goose Up
-- A second location that serves the same accounts: a "mirror" node gets
-- the active grants of another node (the same credential works on both,
-- traffic counts on the same subscription), and has its own public
-- connection parameters. Additive; existing nodes are untouched.

alter table nodes add column if not exists shares_grants_of uuid references nodes(id) on delete set null;
-- Overrides of Core's VLESS/Hysteria settings for this node's links
-- (host, REALITY keys and SNI, Direct-TLS host, Hysteria host/port ...),
-- keys as in config.VLESSConfig. Empty for the primary node.
alter table nodes add column if not exists public_config jsonb not null default '{}'::jsonb;

-- Nodes report cumulative per-credential counters; with one credential on
-- two nodes, the delta baseline has to be kept per node.
create table if not exists node_grant_counters (
    node_id uuid not null references nodes(id) on delete cascade,
    grant_id uuid not null references access_grants(id) on delete cascade,
    last_bytes_up_total bigint not null default 0,
    last_bytes_down_total bigint not null default 0,
    updated_at timestamptz not null default now(),
    primary key (node_id, grant_id)
);

-- Existing baselines belong to each grant's own node.
insert into node_grant_counters (node_id, grant_id, last_bytes_up_total, last_bytes_down_total)
select g.node_id, c.grant_id, c.last_bytes_up_total, c.last_bytes_down_total
from grant_usage_counters c
join access_grants g on g.id = c.grant_id
on conflict (node_id, grant_id) do nothing;

-- +goose Down
drop table if exists node_grant_counters;
alter table nodes drop column if exists public_config, drop column if exists shares_grants_of;
