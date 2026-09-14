# WAVEBREAK Mobile/Desktop API Contract

This document is the integration guide for mobile and desktop clients.

Core rule: clients talk to `wavebreak-core` only. Do not call Laravel Web/Admin and do not read PostgreSQL directly.

## Environments

Local Docker:

```text
Core API: http://127.0.0.1:18080
```

Production should expose only the Core HTTPS API to apps:

```text
Core API: https://api.<domain>
```

All authenticated requests use:

```http
Authorization: Bearer <access_token>
Accept: application/json
Content-Type: application/json
```

## Auth Flow

Register:

```http
POST /v1/auth/register
```

```json
{
  "email": "user@example.com",
  "password": "long-password"
}
```

Login:

```http
POST /v1/auth/login
```

```json
{
  "email": "user@example.com",
  "password": "long-password"
}
```

Response contains:

```json
{
  "access_token": "...",
  "refresh_token": "...",
  "token_type": "Bearer",
  "expires_in": 900
}
```

Refresh:

```http
POST /v1/auth/refresh
```

```json
{
  "refresh_token": "..."
}
```

Logout:

```http
POST /v1/auth/logout
```

```json
{
  "refresh_token": "..."
}
```

Client behavior:

- Store refresh token in the OS secure storage/keychain.
- Store access token in memory when possible.
- Refresh when a request returns `401`, then retry once.
- If refresh returns `401`, clear local session and show login.

## App Bootstrap

After login or app start with a valid token:

```http
GET /v1/client/bootstrap
```

Returns current user, account overview, plans, available nodes.

Use it to hydrate:

- current user/account state
- active subscription
- usage summary
- devices
- Telegram identity status
- active/revoked grants
- plan list
- available node locations

## Subscription

List public plans:

```http
GET /v1/plans
```

Create subscription:

```http
POST /v1/subscriptions
```

```json
{
  "plan_id": "uuid"
}
```

Get current subscription:

```http
GET /v1/subscriptions/current
```

Important fields:

- `traffic_limit_bytes_snapshot`
- `device_limit_snapshot`
- `concurrent_connection_limit_snapshot`
- `traffic_limit_override_bytes`
- `device_limit_override`

The app should display effective limits from overrides first, then snapshots.

## Devices

List devices:

```http
GET /v1/me/devices
```

Register current device:

```http
POST /v1/me/devices
```

```json
{
  "name": "MacBook Pro",
  "platform": "macOS"
}
```

Update device:

```http
PATCH /v1/me/devices/{deviceID}
```

```json
{
  "name": "Office MacBook",
  "platform": "macOS"
}
```

Revoke device:

```http
DELETE /v1/me/devices/{deviceID}
```

If the plan limit is reached, Core returns:

```json
{
  "code": "DEVICE_LIMIT_REACHED",
  "error": "DEVICE_LIMIT_REACHED"
}
```

## Locations / Nodes

List available locations:

```http
GET /v1/locations
```

For MVP, the response is a node list. Mobile/desktop should show:

- `code`
- `region`
- `status`
- `last_heartbeat_at`

Only create access for nodes with `status = online`.

## Access Grants

List grants:

```http
GET /v1/access/grants
```

Create a grant for a device:

```http
POST /v1/access/grants
```

```json
{
  "node_id": "uuid",
  "device_id": "uuid",
  "protocol": "vless"
}
```

Supported protocol values now:

- `vless`
- `wireguard`
- `outline`

For the live pilot, use `vless`. Core returns a VLESS REALITY `connection_url` from `GET /v1/access/grants/{grantID}/config`.

Core validates:

- user has an active subscription
- traffic quota is not exhausted
- `device_id`, when provided, belongs to the user and is not revoked
- selected node exists

Quota error:

```json
{
  "code": "TRAFFIC_LIMIT_REACHED",
  "error": "TRAFFIC_LIMIT_REACHED"
}
```

Revoke grant:

```http
POST /v1/access/grants/{grantID}/revoke
```

Revocation updates Core desired-state for the node. The client can keep polling grant list/config until status changes from `active`.

## VPN Config Contract

Fetch config for a grant:

```http
GET /v1/access/grants/{grantID}/config
```

Current response shape:

```json
{
  "grant": {
    "id": "uuid",
    "user_id": "uuid",
    "subscription_id": "uuid",
    "device_id": "uuid",
    "node_id": "uuid",
    "protocol": "vless",
    "status": "active",
    "expires_at": "2026-10-11T08:00:00Z",
    "desired_revision": 4,
    "created_at": "2026-09-11T08:00:00Z"
  },
  "node": {
    "id": "uuid",
    "code": "TR-IST-01",
    "region": "TR",
    "status": "online",
    "desired_revision": 4,
    "applied_revision": 4
  },
  "device": {
    "id": "uuid",
    "device_public_id": "uuid",
    "name": "MacBook Pro",
    "platform": "macOS"
  },
  "config_status": "ready",
  "config_version": 4,
  "connection_url": "vless://grant-uuid@91.149.241.52:18443?...#WVB-NL-PILOT-01-XXXXXXXX",
  "share_url": "vless://grant-uuid@91.149.241.52:18443?...#WVB-NL-PILOT-01-XXXXXXXX",
  "vless": {
    "client_id": "uuid",
    "label": "WVB-NL-PILOT-01-XXXXXXXX",
    "protocol": "vless",
    "security": "reality",
    "network": "tcp",
    "flow": "xtls-rprx-vision",
    "server": "91.149.241.52",
    "port": 18443
  }
}
```

For VLESS pilot grants, apps should treat config statuses as:

- `pending_node_ack`: Core created the grant, node-agent is applying the Xray config
- `ready`: use `connection_url` / `share_url`
- `revoked`: stop the tunnel and delete local runtime config

WireGuard-specific fields are still a future contract.

## Usage

Current usage:

```http
GET /v1/me/usage
```

History:

```http
GET /v1/me/usage/history?period=7d
GET /v1/me/usage/history?period=30d
GET /v1/me/usage/history?period=current
```

Usage is subscription-level, aggregated from node reports. Apps should not upload traffic counters directly; only node agents report usage.

## Telegram Link

List identities:

```http
GET /v1/me/identities
```

Create one-time link token:

```http
POST /v1/me/identities/telegram/link
```

Unlink Telegram:

```http
DELETE /v1/me/identities/telegram
```

The mobile/desktop app may display the link token or deep-link to the future Telegram bot. Bot integration itself uses service-token endpoints and is not called from user clients.

## Error Format

Core returns:

```json
{
  "code": "ERROR_CODE_OR_MESSAGE",
  "error": "Human readable message or code"
}
```

Important statuses:

- `400`: validation error
- `401`: missing/invalid/expired token
- `403`: active subscription required, quota reached, role denied
- `404`: entity not found or not owned by user
- `500`: Core runtime error

## Recommended Client Screens

Minimum app screens:

- Login/register
- Account overview
- Subscription/plans
- Devices
- Locations
- Access grants
- VPN config/connect state
- Usage

Minimum happy path:

1. Login/register.
2. `GET /v1/client/bootstrap`.
3. If no active subscription, show plans and call `POST /v1/subscriptions`.
4. Ensure current device exists with `POST /v1/me/devices`.
5. Show online locations from `/v1/locations`.
6. Create access grant with `node_id`, `device_id`, `protocol`.
7. Poll `GET /v1/access/grants/{grantID}/config`.
8. When `config_status` is `ready`, use `connection_url` / `share_url`.
9. Show usage from `/v1/me/usage`.
