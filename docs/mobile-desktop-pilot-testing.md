# WAVEBREAK Mobile/Desktop Pilot Testing Guide

Документ для разработчика мобильного и десктопного приложения. Его задача - быстро подключить готовые клиенты к живому pilot API, проверить полный клиентский flow и не упереться в неочевидные ограничения текущего backend.

## Коротко

Репозиторий:

```text
git@github.com:defloyder/wavebrake_project.git
```

Pilot Core API:

```text
http://91.149.241.52:18080
```

Проверка доступности Core:

```text
GET http://91.149.241.52:18080/readyz
```

Публичный сайт и админка для справки:

```text
Web:   http://91.149.241.52:18000
Admin: http://91.149.241.52:18002
```

Для мобильного/десктопного приложения нужен только Core API. Laravel Web/Admin, PostgreSQL, Redis, RabbitMQ и node-agent напрямую из приложения не вызываются.

## Важное ограничение пилота

Пилотный сервер уже позволяет тестировать:

- регистрацию и вход;
- refresh token flow;
- загрузку bootstrap-состояния;
- тарифы;
- создание подписки;
- регистрацию устройства;
- список доступных нод;
- создание access grant;
- получение config endpoint;
- revoke access grant.

Но настоящая VPN-конфигурация еще не генерируется. Сейчас endpoint:

```text
GET /v1/access/grants/{grantID}/config
```

возвращает:

```json
{
  "config_status": "pending_runtime_config"
}
```

Это нормальное текущее состояние. Приложение должно показать состояние вроде "конфигурация готовится" и не пытаться поднимать реальный VPN-туннель, пока backend не начнет возвращать `config_status: "ready"`.

## Настройка клиента

Base URL должен быть конфигом окружения, а не захардкоженной строкой:

```text
WAVEBREAK_API_BASE_URL=http://91.149.241.52:18080
```

На pilot сейчас HTTP без TLS. Для production/staging нужно будет заменить base URL на HTTPS endpoint вида:

```text
https://api.<domain>
```

Общие headers для JSON:

```http
Accept: application/json
Content-Type: application/json
```

Для авторизованных запросов:

```http
Authorization: Bearer <access_token>
Accept: application/json
Content-Type: application/json
```

Токены:

- `access_token` живет коротко, ориентир по ответу сейчас `expires_in: 900`;
- `refresh_token` ротируется при refresh;
- после успешного `POST /v1/auth/refresh` нужно сохранить новый refresh token и забыть старый;
- при `401` приложение делает refresh один раз, повторяет исходный запрос один раз, затем чистит сессию при повторной ошибке.

## Тестовые аккаунты

Разработчик может самостоятельно создавать тестовых пользователей через API. Рекомендуемый формат email:

```text
mobile-dev-<timestamp>@wavebreak.test
desktop-dev-<timestamp>@wavebreak.test
```

Пароль для тестов:

```text
WaveBreakUser123!
```

Админские учетные данные для интеграции приложения не нужны и в репозитории не хранятся.

## End-to-End Flow

Минимальный сценарий, который приложение должно пройти на pilot API:

1. `GET /readyz`
2. `POST /v1/auth/register`
3. сохранить `tokens.access_token` и `tokens.refresh_token`
4. `GET /v1/client/bootstrap`
5. `GET /v1/plans`
6. `POST /v1/subscriptions`
7. `POST /v1/me/devices`
8. `GET /v1/locations`
9. выбрать online node, сейчас ожидается `NL-PILOT-01`
10. `POST /v1/access/grants` с `node_id`, `device_id`, `protocol: "wireguard"`
11. `GET /v1/access/grants/{grantID}/config`
12. убедиться, что `config_status` сейчас `pending_runtime_config`
13. `POST /v1/auth/refresh`
14. `POST /v1/access/grants/{grantID}/revoke`

## Endpoint Quick Reference

| Назначение | Method | Path | Auth |
| --- | --- | --- | --- |
| Readiness | `GET` | `/readyz` | no |
| Register | `POST` | `/v1/auth/register` | no |
| Login | `POST` | `/v1/auth/login` | no |
| Refresh token | `POST` | `/v1/auth/refresh` | no |
| Logout | `POST` | `/v1/auth/logout` | no |
| App bootstrap | `GET` | `/v1/client/bootstrap` | yes |
| Plans | `GET` | `/v1/plans` | no |
| Create subscription | `POST` | `/v1/subscriptions` | yes |
| Current subscription | `GET` | `/v1/subscriptions/current` | yes |
| List devices | `GET` | `/v1/me/devices` | yes |
| Create device | `POST` | `/v1/me/devices` | yes |
| Update device | `PATCH` | `/v1/me/devices/{deviceID}` | yes |
| Revoke device | `DELETE` | `/v1/me/devices/{deviceID}` | yes |
| Locations / nodes | `GET` | `/v1/locations` | yes |
| List grants | `GET` | `/v1/access/grants` | yes |
| Create grant | `POST` | `/v1/access/grants` | yes |
| Grant config | `GET` | `/v1/access/grants/{grantID}/config` | yes |
| Revoke grant | `POST` | `/v1/access/grants/{grantID}/revoke` | yes |
| Current usage | `GET` | `/v1/me/usage` | yes |
| Usage history | `GET` | `/v1/me/usage/history?period=7d` | yes |
| Telegram identities | `GET` | `/v1/me/identities` | yes |
| Telegram link token | `POST` | `/v1/me/identities/telegram/link` | yes |
| Unlink Telegram | `DELETE` | `/v1/me/identities/telegram` | yes |

## Request And Response Examples

### Register

```http
POST /v1/auth/register
```

```json
{
  "email": "mobile-dev-20260914160000@wavebreak.test",
  "password": "WaveBreakUser123!"
}
```

Response shape:

```json
{
  "user": {
    "id": "uuid",
    "email": "mobile-dev-20260914160000@wavebreak.test",
    "role": "user",
    "status": "active"
  },
  "tokens": {
    "access_token": "...",
    "refresh_token": "...",
    "token_type": "Bearer",
    "expires_in": 900
  }
}
```

### Login

```http
POST /v1/auth/login
```

```json
{
  "email": "mobile-dev-20260914160000@wavebreak.test",
  "password": "WaveBreakUser123!"
}
```

Response shape:

```json
{
  "access_token": "...",
  "refresh_token": "...",
  "token_type": "Bearer",
  "expires_in": 900
}
```

Обрати внимание: register возвращает токены внутри `tokens`, login возвращает их на верхнем уровне.

### Create Subscription

Сначала получить тарифы:

```http
GET /v1/plans
```

Затем взять `plans[0].id` и создать подписку:

```http
POST /v1/subscriptions
```

```json
{
  "plan_id": "uuid"
}
```

Сейчас pilot активирует подписку сразу. Реальной оплаты в pilot flow пока нет.

### Create Device

```http
POST /v1/me/devices
```

```json
{
  "name": "Developer iPhone",
  "platform": "ios"
}
```

Рекомендуемые значения `platform`:

```text
ios
android
windows
macos
linux
```

### Locations

```http
GET /v1/locations
```

Ожидаемое pilot-состояние:

```json
{
  "nodes": [
    {
      "id": "uuid",
      "code": "NL-PILOT-01",
      "region": "NL",
      "status": "online"
    }
  ]
}
```

Приложение должно разрешать создание grant только для нод со `status: "online"`.

### Create Access Grant

```http
POST /v1/access/grants
```

```json
{
  "node_id": "uuid",
  "device_id": "uuid",
  "protocol": "wireguard"
}
```

Response shape:

```json
{
  "id": "uuid",
  "user_id": "uuid",
  "subscription_id": "uuid",
  "device_id": "uuid",
  "node_id": "uuid",
  "protocol": "wireguard",
  "status": "active",
  "desired_revision": 1
}
```

### Get Grant Config

```http
GET /v1/access/grants/{grantID}/config
```

Current pilot response shape:

```json
{
  "grant": {
    "id": "uuid",
    "status": "active",
    "protocol": "wireguard"
  },
  "node": {
    "id": "uuid",
    "code": "NL-PILOT-01",
    "region": "NL",
    "status": "online"
  },
  "device": {
    "id": "uuid",
    "name": "Developer iPhone",
    "platform": "ios"
  },
  "config_status": "pending_runtime_config",
  "wireguard": {
    "interface": {
      "private_key": "client_generated",
      "address": null,
      "dns": ["1.1.1.1", "1.0.0.1"],
      "mtu": 1420
    },
    "peer": {
      "public_key": null,
      "preshared_key": null,
      "endpoint": null,
      "allowed_ips": ["0.0.0.0/0", "::/0"],
      "persistent_keepalive": 25
    }
  }
}
```

До `config_status: "ready"` приложение не должно собирать WireGuard config из null-полей.

## UI/State Expectations

Приложение должно корректно обрабатывать такие состояния:

| Состояние API | Что показывать в приложении |
| --- | --- |
| нет refresh token | экран входа/регистрации |
| bootstrap `401` | refresh один раз, затем logout при ошибке |
| нет активной подписки | экран тарифов |
| устройство не создано | создать device для текущего клиента |
| device limit reached | показать лимит тарифа |
| нет online nodes | локации недоступны, подключение disabled |
| grant `active` + config `pending_runtime_config` | доступ создан, VPN-конфигурация готовится |
| config `ready` в будущем | передать config в native VPN adapter |
| grant `revoked` | остановить туннель и удалить локальный runtime config |

## PowerShell Smoke Test

Этот скрипт можно запускать на Windows без `jq`.

```powershell
$base = "http://91.149.241.52:18080"
$email = "mobile-dev-$(Get-Date -Format yyyyMMddHHmmss)@wavebreak.test"
$password = "WaveBreakUser123!"

Write-Host "Core readiness"
Invoke-RestMethod -Method Get -Uri "$base/readyz"

Write-Host "Register $email"
$register = Invoke-RestMethod `
  -Method Post `
  -Uri "$base/v1/auth/register" `
  -ContentType "application/json" `
  -Body (@{ email = $email; password = $password } | ConvertTo-Json)

$accessToken = $register.tokens.access_token
$refreshToken = $register.tokens.refresh_token
$headers = @{ Authorization = "Bearer $accessToken"; Accept = "application/json" }

Write-Host "Bootstrap"
$bootstrap = Invoke-RestMethod -Method Get -Uri "$base/v1/client/bootstrap" -Headers $headers

Write-Host "Plans"
$plans = Invoke-RestMethod -Method Get -Uri "$base/v1/plans" -Headers $headers
$planId = $plans.plans[0].id

Write-Host "Create subscription"
$subscription = Invoke-RestMethod `
  -Method Post `
  -Uri "$base/v1/subscriptions" `
  -Headers $headers `
  -ContentType "application/json" `
  -Body (@{ plan_id = $planId } | ConvertTo-Json)

Write-Host "Create device"
$device = Invoke-RestMethod `
  -Method Post `
  -Uri "$base/v1/me/devices" `
  -Headers $headers `
  -ContentType "application/json" `
  -Body (@{ name = "Developer Windows"; platform = "windows" } | ConvertTo-Json)

Write-Host "Locations"
$locations = Invoke-RestMethod -Method Get -Uri "$base/v1/locations" -Headers $headers
$node = $locations.nodes | Where-Object { $_.status -eq "online" } | Select-Object -First 1
if (-not $node) { throw "No online node found" }

Write-Host "Create grant on node $($node.code)"
$grant = Invoke-RestMethod `
  -Method Post `
  -Uri "$base/v1/access/grants" `
  -Headers $headers `
  -ContentType "application/json" `
  -Body (@{ node_id = $node.id; device_id = $device.id; protocol = "wireguard" } | ConvertTo-Json)

Write-Host "Get config"
$config = Invoke-RestMethod `
  -Method Get `
  -Uri "$base/v1/access/grants/$($grant.id)/config" `
  -Headers $headers

Write-Host "Refresh token"
$refresh = Invoke-RestMethod `
  -Method Post `
  -Uri "$base/v1/auth/refresh" `
  -ContentType "application/json" `
  -Body (@{ refresh_token = $refreshToken } | ConvertTo-Json)

Write-Host "Revoke grant"
$revokeHeaders = @{ Authorization = "Bearer $($refresh.access_token)"; Accept = "application/json" }
$revoked = Invoke-RestMethod `
  -Method Post `
  -Uri "$base/v1/access/grants/$($grant.id)/revoke" `
  -Headers $revokeHeaders

[PSCustomObject]@{
  status = "PASSED"
  email = $email
  plan = $plans.plans[0].code
  node = $node.code
  device_id = $device.id
  grant_id = $grant.id
  config_status = $config.config_status
  revoke_status = $revoked.status
}
```

Ожидаемый результат:

```text
status        : PASSED
node          : NL-PILOT-01
config_status : pending_runtime_config
revoke_status : revoked
```

## Curl Smoke Test

Для Linux/macOS удобно использовать `jq`:

```bash
BASE="http://91.149.241.52:18080"
EMAIL="desktop-dev-$(date +%Y%m%d%H%M%S)@wavebreak.test"
PASSWORD="WaveBreakUser123!"

curl -s "$BASE/readyz"

REGISTER_RESPONSE=$(curl -s -X POST "$BASE/v1/auth/register" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\"}")

ACCESS_TOKEN=$(echo "$REGISTER_RESPONSE" | jq -r '.tokens.access_token')
REFRESH_TOKEN=$(echo "$REGISTER_RESPONSE" | jq -r '.tokens.refresh_token')
AUTH_HEADER="Authorization: Bearer $ACCESS_TOKEN"

curl -s "$BASE/v1/client/bootstrap" -H "$AUTH_HEADER" | jq

PLAN_ID=$(curl -s "$BASE/v1/plans" -H "$AUTH_HEADER" | jq -r '.plans[0].id')

curl -s -X POST "$BASE/v1/subscriptions" \
  -H "$AUTH_HEADER" \
  -H "Content-Type: application/json" \
  -d "{\"plan_id\":\"$PLAN_ID\"}" | jq

DEVICE_RESPONSE=$(curl -s -X POST "$BASE/v1/me/devices" \
  -H "$AUTH_HEADER" \
  -H "Content-Type: application/json" \
  -d '{"name":"Developer Linux","platform":"linux"}')

DEVICE_ID=$(echo "$DEVICE_RESPONSE" | jq -r '.id')
NODE_ID=$(curl -s "$BASE/v1/locations" -H "$AUTH_HEADER" | jq -r '.nodes[] | select(.status=="online") | .id' | head -n 1)

GRANT_RESPONSE=$(curl -s -X POST "$BASE/v1/access/grants" \
  -H "$AUTH_HEADER" \
  -H "Content-Type: application/json" \
  -d "{\"node_id\":\"$NODE_ID\",\"device_id\":\"$DEVICE_ID\",\"protocol\":\"wireguard\"}")

GRANT_ID=$(echo "$GRANT_RESPONSE" | jq -r '.id')

curl -s "$BASE/v1/access/grants/$GRANT_ID/config" -H "$AUTH_HEADER" | jq

NEW_ACCESS_TOKEN=$(curl -s -X POST "$BASE/v1/auth/refresh" \
  -H "Content-Type: application/json" \
  -d "{\"refresh_token\":\"$REFRESH_TOKEN\"}" | jq -r '.access_token')

curl -s -X POST "$BASE/v1/access/grants/$GRANT_ID/revoke" \
  -H "Authorization: Bearer $NEW_ACCESS_TOKEN" | jq
```

## Error Format

Core errors use this shape:

```json
{
  "code": "ERROR_CODE_OR_MESSAGE",
  "error": "Human readable message or code"
}
```

Typical handling:

| HTTP | Meaning | Client behavior |
| --- | --- | --- |
| `400` | invalid request/body | show validation/form error |
| `401` | missing/expired/invalid access token | refresh once, then logout if refresh fails |
| `403` | no active subscription, quota reached, role denied | show subscription/limit state |
| `404` | entity not found or not owned by user | refresh state and remove stale local object |
| `500` | Core runtime error | show retry state and log request details |

## What To Send Back When Something Fails

Если разработчик ловит ошибку, пусть пришлет:

```text
Platform:
App version/build:
Time with timezone:
Base URL:
User email:
Endpoint:
HTTP method:
HTTP status:
Request body without tokens/passwords:
Response body:
Steps to reproduce:
```

Токены, пароли и приватные ключи отправлять нельзя.

## Developer Acceptance Checklist

Перед тем как считать интеграцию приложения готовой к следующему backend pass:

- приложение умеет менять `WAVEBREAK_API_BASE_URL` без пересборки production-кода;
- registration и login работают;
- refresh token rotation работает;
- bootstrap загружает состояние после старта приложения;
- тарифы отображаются из Core;
- подписка создается через Core;
- текущее устройство создается и переиспользуется;
- список локаций показывает online node `NL-PILOT-01`;
- access grant создается с правильным `device_id`;
- config endpoint открывается;
- `pending_runtime_config` отображается как отдельное неошибочное состояние;
- revoke grant чистит локальное состояние подключения;
- logout чистит локальные токены;
- приложение не обращается к Laravel, node-agent, PostgreSQL, Redis или RabbitMQ напрямую.

## Related Documents

- `MOBILE_DESKTOP_DEVELOPER_HANDOFF.md` - главный handoff по интеграции.
- `docs/mobile-desktop-api.md` - компактный контракт API.
- `docs/vpn-config-contract.md` - контракт будущей VPN-конфигурации.
- `wavebreak-core/api/openapi.yaml` - OpenAPI contract.
- `docs/pilot-vps-deployment.md` - как развернут pilot stack.
