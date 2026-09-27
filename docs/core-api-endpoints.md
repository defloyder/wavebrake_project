# WAVEBREAK Core API Endpoints

OpenAPI contract:

```text
wavebreak-core/api/openapi.yaml
```

Implemented endpoints:

- `GET /healthz`
- `GET /readyz`
- `GET /metrics`
- `POST /v1/auth/register`
- `POST /v1/auth/login`
- `POST /v1/auth/refresh`
- `POST /v1/auth/logout`
- `GET /v1/me`
- `GET /v1/client/bootstrap`
- `GET /v1/me/overview`
- `GET /v1/me/identities`
- `POST /v1/me/identities/telegram/link`
- `DELETE /v1/me/identities/telegram`
- `GET /v1/me/usage`
- `GET /v1/me/usage/history?period=7d|30d|current`
- `GET /v1/me/devices`
- `POST /v1/me/devices`
- `PATCH /v1/me/devices/{deviceID}`
- `DELETE /v1/me/devices/{deviceID}`
- `GET /v1/plans`
- `GET /v1/locations`
- `POST /v1/subscriptions`
- `GET /v1/subscriptions/current`
- `GET /v1/nodes`
- `POST /v1/nodes/enroll`
- `POST /v1/nodes/{nodeID}/desired-state`
- `POST /v1/node/enroll`
- `POST /v1/node/heartbeat`
- `POST /v1/node/usage`
- `GET /v1/node/state`
- `POST /v1/node/state/ack`
- `POST /v1/node/state/fail`
- `GET /v1/access/grants`
- `POST /v1/access/grants`
- `GET /v1/access/grants/{grantID}/config`
- `POST /v1/access/grants/{grantID}/revoke`
- `GET /v1/admin/dashboard`
- `GET /v1/admin/users`
- `GET /v1/admin/plans`
- `POST /v1/admin/plans`
- `PUT /v1/admin/plans/{planID}`
- `DELETE /v1/admin/plans/{planID}`
- `GET /v1/admin/subscriptions`
- `PATCH /v1/admin/subscriptions/{subscriptionID}/status`
- `GET /v1/admin/devices`
- `POST /v1/admin/devices/{deviceID}/revoke`
- `GET /v1/admin/traffic`
- `GET /v1/admin/audit`
- `GET /v1/admin/access/grants`
- `POST /v1/admin/access/grants/{grantID}/revoke`
- `POST /v1/bot/telegram/identify`
- `GET /v1/bot/users/{userID}/overview`

Notes:

- Core remains the only business/data API for Web/Admin/Bot-ready clients.
- Mobile and desktop clients should start from `GET /v1/client/bootstrap` after auth. It returns the user, overview, plans, devices, nodes, and current grants in one response.
- Mobile and desktop clients should bind a grant to a device by passing `device_id` to `POST /v1/access/grants`.
- `GET /v1/access/grants/{grantID}/config` is the app-facing VPN config contract. Current status is `pending_runtime_config`; real WireGuard/Outline material is the next backend step.
- `POST /v1/node/usage` accepts monotonic aggregate counters per `grant_id` and aggregates them into subscription usage.
- Access grant create/revoke updates node desired-state and relies on the existing node ACK flow.

Admin user management (`internal/accounts`, see `wavebreak-core/api/openapi.yaml`):

- `GET /v1/admin/users/{userID}` (support, admin, superadmin): one normalized response `{user, subscription, access, traffic, devices, connections}`.
  - `subscription`: the live subscription with its plan, `started_at`, `expires_at`, effective `traffic_limit_bytes` / `device_limit`; `null` when none.
  - `access`: `credential_id` (primary access grant id), `subscription_url` (built only by `accounts.SubscriptionURLBuilder` from `WAVEBREAK_SUBSCRIPTION_URL_BASE`, default `https://api.wavebreak.com.tr/v1/sub/`), `active_grants`, `grants[]`.
  - `traffic`: `bytes_up`, `bytes_down`, `bytes_total`, `limit_bytes`, `remaining_bytes`, `used_percent` aggregated from `subscription_usage`; the three limit fields are `null` for an unlimited plan; `null` without a subscription.
  - `devices`: `registered` (non-revoked), `limit` (from the live subscription), `items[]`.
  - `connections.active`: `null` until nodes report live connections (`source: not_reported`).
- `GET /v1/admin/users/{userID}/devices` (support, admin, superadmin).
- `POST /v1/admin/users/{userID}/subscriptions` `{"plan_id"}` (admin, superadmin): validates user and plan, rejects a second live subscription, creates + activates it with the plan snapshot, issues its grant on the online node with the freshest heartbeat (protocol `WAVEBREAK_ADMIN_ACCESS_PROTOCOL`, default `vless`), stores it as `primary_grant_id`, audits `subscription_issued` and `access_created`, returns the refreshed details (201).
- `POST /v1/admin/users/{userID}/access` (admin, superadmin): issues the missing credential of the user's live subscription (bought in the app, or created before `primary_grant_id` existed): grant on the default node, stored as `primary_grant_id`, audits `access_created`, returns the refreshed details (200). Idempotent — an existing active credential is kept (and linked as primary). No live subscription -> `SUBSCRIPTION_NOT_FOUND` (404); not active or period over -> `SUBSCRIPTION_NOT_ACTIVE` (422); `NO_NODE_AVAILABLE` (503); `ACCESS_ISSUE_FAILED` (500).
- `PATCH /v1/admin/subscriptions/{subscriptionID}` with `expires_at`: also moves `expires_at` of the subscription's active grants to the new period end and bumps the desired revision of the affected nodes (same transaction). Nodes only receive unexpired grants, so before this an admin extension still cut access at the old date.
- `POST /v1/admin/users/{userID}/password-reset` (admin, superadmin): creates a one-time reset token (TTL `WAVEBREAK_PASSWORD_RESET_TTL`, default 1h), stores only its hash, builds `WAVEBREAK_PASSWORD_RESET_URL_BASE?token=...` and hands it to the notifier, audits `password_reset_requested`, returns `{status: reset_link_created, channel, delivery, expires_at}` (202). No email provider exists yet, so `delivery` is `not_configured`. Users without email -> `PASSWORD_RESET_CHANNEL_UNAVAILABLE` (422).
- `POST /v1/auth/password-reset/confirm` `{"token","password"}` (public): consumes the token once before expiry, sets the password (argon2id), revokes all sessions, audits `password_reset_completed`. Invalid/expired/used -> `PASSWORD_RESET_TOKEN_INVALID` (400).
- Error model of these endpoints: `{"error": {"code", "message", "request_id"}}` with codes `USER_NOT_FOUND`, `PLAN_NOT_FOUND`, `PLAN_INACTIVE`, `SUBSCRIPTION_ALREADY_ACTIVE`, `SUBSCRIPTION_CREATE_FAILED`, `NO_NODE_AVAILABLE`, `PASSWORD_RESET_CHANNEL_UNAVAILABLE`, `PASSWORD_RESET_FAILED`, `PASSWORD_RESET_TOKEN_INVALID`, `WEAK_PASSWORD`, `VALIDATION_FAILED`, `INTERNAL_ERROR`. Older endpoints keep `{"code","error"}` because shipped mobile/desktop clients parse it; they now answer `409 SUBSCRIPTION_ALREADY_ACTIVE` instead of 500 on a duplicate subscription.
