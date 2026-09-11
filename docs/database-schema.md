# WAVEBREAK Database Schema

PostgreSQL is owned by `wavebreak-core`.

Core migrations live in:

```text
wavebreak-core/migrations
```

Primary tables implemented:

- `users`
- `sessions`
- `devices`
- `user_identities`
- `account_link_tokens`
- `plans`
- `subscriptions`
- `payments`
- `nodes`
- `node_protocols`
- `node_enrollment_tokens`
- `access_credentials`
- `access_grants`
- `config_versions`
- `audit_events`
- `webhook_events`
- `idempotency_keys`
- `outbox_events`
- `processed_messages`
- `node_usage_reports`
- `subscription_usage`
- `subscription_usage_daily`
- `grant_usage_counters`
- `notifications`
- `admin_actions`

The migration also seeds initial monthly plans.

Production-readiness columns added in pass 1:

- `users.role` supports `user`, `support`, `admin`, `superadmin`.
- `users.disabled_at` lets Core reject disabled accounts.
- `sessions.revoked_at`, `revoked_reason`, and `replaced_by_session_id` support refresh rotation and reuse detection.
- `nodes.api_token_hash` stores node API token hashes.
- `nodes.desired_revision`, `applied_revision`, and `last_sync_error` support node desired-state sync.
- `config_versions.failed_at` and `failure_message` support node apply failure reporting.

Product/Core completion columns added in migration `00002_product_core_completion.sql`:

- `users.email` and `users.password_hash` are nullable for Telegram-first account readiness.
- `users.username`, `status`, `last_login_at`, `email_verified_at`, and `deleted_at` support account lifecycle and client/bot identity flows.
- `user_identities` stores provider links; MVP provider is `telegram`.
- `account_link_tokens` stores one-time hashed website-to-Telegram link tokens.
- `plans` now carry public/admin-ready commercial fields: `price_minor`, `currency`, `duration_days`, `device_limit`, `traffic_limit_bytes`, `concurrent_connection_limit`, `is_active`, `is_public`, `sort_order`, `deleted_at`.
- `subscriptions` store ownership/source and frozen snapshots for traffic, devices, and concurrent connection limits.
- `devices` support `device_public_id`, `platform`, `last_seen_at`, and soft revoke.
- `access_grants` now track `subscription_id`, `device_id`, revoke fields, and the desired-state revision that carried the change.
- `subscription_usage`, `subscription_usage_daily`, and `grant_usage_counters` aggregate monotonic node usage reports into subscription traffic accounting.
