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
