# WAVEBREAK API Handoff для разработчика Mobile/Desktop

Этот документ нужно передать разработчику мобильного и десктопного приложения, чтобы он подключил готовые клиенты к WAVEBREAK Core API.

Главное правило интеграции: мобильное и десктопное приложение работают только с `wavebreak-core`. Не нужно ходить в Laravel Web/Admin, не нужно читать PostgreSQL напрямую и не нужно общаться с node-agent напрямую.

## Что отправить разработчику

Отправь разработчику этот набор:

1. Репозиторий:

```text
git@github.com:defloyder/wavebrake_project.git
```

2. Основной файл для интеграции:

```text
MOBILE_DESKTOP_DEVELOPER_HANDOFF.md
```

3. Подробный API-документ:

```text
docs/mobile-desktop-api.md
```

4. Живой pilot guide для тестирования приложения:

```text
docs/mobile-desktop-pilot-testing.md
```

5. OpenAPI-контракт:

```text
wavebreak-core/api/openapi.yaml
```

6. Контракт будущей VPN-конфигурации:

```text
docs/vpn-config-contract.md
```

7. Результаты проверки:

```text
docs/results.md
```

## Текущее состояние

Backend уже умеет:

- регистрировать и авторизовывать пользователя;
- выдавать access/refresh tokens;
- обновлять refresh token с ротацией;
- отдавать bootstrap-данные для приложения;
- показывать тарифы;
- создавать активную подписку;
- регистрировать устройство пользователя;
- показывать доступные ноды/локации;
- создавать access grant под конкретное устройство;
- отдавать app-facing endpoint для VPN config;
- отзывать access grant;
- показывать usage;
- связывать Telegram identity через link token.

Важно: для pilot-сервера включена выдача VLESS REALITY ссылки. Для новых рабочих grants используй:

```text
protocol = vless
```

`GET /v1/access/grants/{grantID}/config` возвращает `connection_url`/`share_url` вида `vless://...#WVB-...`. Если сразу после создания grant статус `pending_node_ack`, нужно повторить запрос через несколько секунд, пока node-agent применит конфиг.

## Где находится Core API

Локально в Docker:

```text
http://127.0.0.1:18080
```

Живой pilot API для разработчика мобильного/десктопного приложения:

```text
http://91.149.241.52:18080
```

Production/staging должен быть HTTPS endpoint Core API:

```text
https://api.<domain>
```

В приложении лучше держать base URL конфигом окружения:

```text
WAVEBREAK_API_BASE_URL=https://api.<domain>
```

## Общие HTTP-правила

Для JSON-запросов:

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

Все даты приходят в ISO/RFC3339 формате:

```text
2026-09-11T08:00:00Z
```

Все идентификаторы сущностей сейчас UUID-строки.

## Auth Flow

### Регистрация

```http
POST /v1/auth/register
```

Request:

```json
{
  "email": "user@example.com",
  "password": "WaveBreakUser123!"
}
```

Response:

```json
{
  "user": {
    "id": "uuid",
    "email": "user@example.com",
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

Пароль должен быть минимум 10 символов.

### Вход

```http
POST /v1/auth/login
```

Request:

```json
{
  "email": "user@example.com",
  "password": "WaveBreakUser123!"
}
```

Response:

```json
{
  "access_token": "...",
  "refresh_token": "...",
  "token_type": "Bearer",
  "expires_in": 900
}
```

### Обновление токена

```http
POST /v1/auth/refresh
```

Request:

```json
{
  "refresh_token": "..."
}
```

Response:

```json
{
  "access_token": "...",
  "refresh_token": "...",
  "token_type": "Bearer",
  "expires_in": 900
}
```

Важное поведение: refresh token ротируется. После успешного refresh нужно сохранить новый `refresh_token` и забыть старый. Если приложение повторно использует старый refresh token, Core считает это reuse-сценарием и может инвалидировать сессию.

### Выход

```http
POST /v1/auth/logout
```

Request:

```json
{
  "refresh_token": "..."
}
```

Response:

```json
{
  "status": "ok"
}
```

### Как хранить токены в приложении

Mobile:

- `refresh_token` хранить в Keychain/Keystore;
- `access_token` по возможности держать в памяти;
- после рестарта приложения брать refresh token из secure storage и делать refresh при необходимости.

Desktop:

- Windows: Credential Manager / DPAPI-backed storage;
- macOS: Keychain;
- Linux: Secret Service / libsecret;
- не хранить refresh token в plain text config-файле.

### Retry-логика

Если авторизованный запрос вернул `401`:

1. Один раз вызвать `POST /v1/auth/refresh`.
2. Сохранить новый access/refresh token.
3. Повторить исходный запрос один раз.
4. Если refresh тоже вернул `401`, очистить локальную сессию и показать экран входа.

## Первый запрос после входа: Bootstrap

После login/register или после восстановления сессии:

```http
GET /v1/client/bootstrap
```

Этот endpoint нужен, чтобы одним запросом собрать состояние приложения.

Он возвращает:

- пользователя;
- обзор аккаунта;
- текущую подписку;
- usage;
- devices;
- Telegram identities;
- access grants;
- список тарифов;
- список нод/локаций.

Упрощенный response:

```json
{
  "user": {
    "id": "uuid",
    "email": "user@example.com",
    "role": "user",
    "status": "active"
  },
  "overview": {
    "subscription": null,
    "usage": null,
    "devices": [],
    "telegram": [],
    "access_summary": {
      "active_grants": 0,
      "revoked_grants": 0
    }
  },
  "plans": [],
  "nodes": [],
  "grants": []
}
```

Приложение должно использовать bootstrap как главный источник для первичной отрисовки кабинета.

## Тарифы и подписка

### Получить тарифы

```http
GET /v1/plans
```

Response:

```json
{
  "plans": [
    {
      "id": "uuid",
      "code": "starter-monthly",
      "name": "Starter",
      "price_minor": 900,
      "currency": "USD",
      "interval": "month",
      "device_limit": 1,
      "traffic_limit_bytes": null,
      "concurrent_connection_limit": 1,
      "is_active": true,
      "is_public": true,
      "sort_order": 10
    }
  ]
}
```

Цена хранится в minor units. Например `price_minor: 900` и `currency: "USD"` значит `$9.00`.

### Создать подписку

```http
POST /v1/subscriptions
```

Request:

```json
{
  "plan_id": "uuid"
}
```

Response:

```json
{
  "id": "uuid",
  "user_id": "uuid",
  "plan_id": "uuid",
  "status": "active",
  "traffic_limit_bytes_snapshot": null,
  "device_limit_snapshot": 1,
  "concurrent_connection_limit_snapshot": 1,
  "current_period_started_at": "2026-09-11T08:00:00Z",
  "current_period_ends_at": "2026-10-11T08:00:00Z"
}
```

Сейчас MVP активирует подписку сразу. Когда появится реальная платежка, app flow может получить промежуточные payment states.

### Получить текущую подписку

```http
GET /v1/subscriptions/current
```

Если активной подписки нет, Core вернет `404`.

## Devices

Перед выдачей доступа приложение должно зарегистрировать текущее устройство.

### Список устройств

```http
GET /v1/me/devices
```

Response:

```json
{
  "devices": [
    {
      "id": "uuid",
      "device_public_id": "uuid",
      "name": "MacBook Pro",
      "platform": "macos",
      "created_at": "2026-09-11T08:00:00Z",
      "updated_at": "2026-09-11T08:00:00Z",
      "last_seen_at": null,
      "revoked_at": null
    }
  ]
}
```

### Создать устройство

```http
POST /v1/me/devices
```

Request:

```json
{
  "name": "MacBook Pro",
  "platform": "macos"
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

Response:

```json
{
  "id": "uuid",
  "device_public_id": "uuid",
  "name": "MacBook Pro",
  "platform": "macos",
  "created_at": "2026-09-11T08:00:00Z",
  "updated_at": "2026-09-11T08:00:00Z"
}
```

Если лимит устройств исчерпан:

```json
{
  "code": "DEVICE_LIMIT_REACHED",
  "error": "DEVICE_LIMIT_REACHED"
}
```

### Обновить устройство

```http
PATCH /v1/me/devices/{deviceID}
```

Request:

```json
{
  "name": "Office MacBook",
  "platform": "macos"
}
```

### Отозвать устройство

```http
DELETE /v1/me/devices/{deviceID}
```

Response:

```json
{
  "status": "ok"
}
```

## Locations / Nodes

Получить список доступных локаций:

```http
GET /v1/locations
```

Response:

```json
{
  "nodes": [
    {
      "id": "uuid",
      "code": "TR-IST-01",
      "region": "TR",
      "status": "online",
      "desired_revision": 4,
      "applied_revision": 4,
      "last_heartbeat_at": "2026-09-11T08:00:00Z"
    }
  ]
}
```

В UI нужно показывать только ноды со статусом `online` как доступные для подключения. Offline-ноды можно показывать как недоступные.

## Access Grants

Access grant - это серверное разрешение на доступ к конкретной ноде для конкретного пользователя и устройства.

### Список grant-ов

```http
GET /v1/access/grants
```

Response:

```json
{
  "grants": [
    {
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
    }
  ]
}
```

### Создать grant

```http
POST /v1/access/grants
```

Request:

```json
{
  "node_id": "uuid",
  "device_id": "uuid",
  "protocol": "vless"
}
```

Поддерживаемые значения `protocol`:

```text
vless
wireguard
outline
```

Для mobile/desktop сейчас основной протокол:

```text
vless
```

Core проверяет:

- у пользователя есть активная подписка;
- трафик не исчерпан;
- `device_id` принадлежит пользователю;
- устройство не отозвано;
- node существует.

Если нет активной подписки:

```json
{
  "code": "active subscription is required",
  "error": "active subscription is required"
}
```

Если лимит трафика исчерпан:

```json
{
  "code": "TRAFFIC_LIMIT_REACHED",
  "error": "TRAFFIC_LIMIT_REACHED"
}
```

### Отозвать grant

```http
POST /v1/access/grants/{grantID}/revoke
```

Response:

```json
{
  "id": "uuid",
  "status": "revoked",
  "revoked_at": "2026-09-11T08:00:00Z",
  "revoked_reason": "user"
}
```

После revoke приложение должно:

- остановить VPN-туннель, если он активен;
- удалить локальный runtime config для этого grant;
- обновить список grant-ов или bootstrap.

## VPN Config Endpoint

Получить конфигурацию для grant:

```http
GET /v1/access/grants/{grantID}/config
```

Текущий response:

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
    "applied_revision": 4,
    "last_heartbeat_at": "2026-09-11T08:00:00Z"
  },
  "device": {
    "id": "uuid",
    "device_public_id": "uuid",
    "name": "MacBook Pro",
    "platform": "macos"
  },
  "location": {
    "node_id": "uuid",
    "node_code": "NL-PILOT-01",
    "region": "NL",
    "country": "Netherlands",
    "city": "Amsterdam",
    "label": "🇳🇱 Netherlands, Amsterdam",
    "display_name": "🇳🇱 Netherlands, Amsterdam",
    "status": "online",
    "online": true,
    "is_available": true,
    "protocol_hint": "vless-reality"
  },
  "connection_test": {
    "node_id": "uuid",
    "node_code": "NL-PILOT-01",
    "protocol": "vless",
    "transport": "tcp",
    "security": "reality",
    "host": "91.149.241.52",
    "port": 443,
    "sni": "www.microsoft.com",
    "timeout_ms": 8000,
    "test_targets": ["api.telegram.org:443", "telegram.org:443", "t.me:443"]
  },
  "config_status": "ready",
  "config_version": 4,
  "connection_url": "vless://grant-uuid@91.149.241.52:443?...#WVB-NL-PILOT-01-XXXXXXXX",
  "share_url": "vless://grant-uuid@91.149.241.52:443?...#WVB-NL-PILOT-01-XXXXXXXX",
  "vless": {
    "client_id": "uuid",
    "label": "WVB-NL-PILOT-01-XXXXXXXX",
    "protocol": "vless",
    "security": "reality",
    "network": "tcp",
    "server": "91.149.241.52",
    "port": 443,
    "location": { "...": "same shape as top-level location above" },
    "connection_test": { "...": "same shape as top-level connection_test above" }
  }
}
```

`location` и `connection_test` также приходят в `GET /v1/client/bootstrap` (как `locations: []`, один объект на каждую ноду) и в `GET /v1/locations` — используй их, чтобы показать пользователю человекочитаемую локацию ("🇳🇱 Netherlands, Amsterdam") и чтобы приложение могло само выполнить сетевой тест подключения (TCP-коннект на `host:port` из `connection_test`, не выдумывая endpoint самостоятельно), не дожидаясь фактического VPN-туннеля.

`flow` в `vless` присутствует только если на сервере включен XTLS Vision (`WAVEBREAK_VLESS_FLOW` не `none`); на pilot сейчас используется совместимый режим без flow, так что поле в ответе может отсутствовать — не полагайся на его наличие.

Что делать приложению сейчас:

- если `config_status = pending_node_ack`, показать "Конфигурация готовится" и повторить запрос через несколько секунд;
- если `config_status = ready`, использовать `connection_url` / `share_url`;
- хранить grant и polling state;
- после revoke остановить подключение и удалить локальный runtime config.

Что приложение не должно делать:

- не генерировать endpoint ноды самостоятельно;
- не подставлять фейковые peer public keys;
- не обращаться к node-agent напрямую.

### Future WireGuard response

WireGuard остается будущим контрактом. Когда он будет включен, endpoint может возвращать такую форму:

```json
{
  "config_status": "ready",
  "config_version": 7,
  "wireguard": {
    "interface": {
      "private_key": "client_generated_or_core_wrapped",
      "address": "10.77.0.12/32",
      "dns": ["1.1.1.1", "1.0.0.1"],
      "mtu": 1420
    },
    "peer": {
      "public_key": "server-public-key",
      "preshared_key": "optional-psk",
      "endpoint": "tr-ist-01.example.com:51820",
      "allowed_ips": ["0.0.0.0/0", "::/0"],
      "persistent_keepalive": 25
    }
  },
  "raw_config": "[Interface]\n..."
}
```

Для pilot использовать VLESS REALITY link из `connection_url`.

## Usage

Получить usage за текущий период:

```http
GET /v1/me/usage
```

Получить историю:

```http
GET /v1/me/usage/history?period=7d
GET /v1/me/usage/history?period=30d
GET /v1/me/usage/history?period=current
```

Usage считается на стороне Core из node usage reports. Mobile/Desktop не должны отправлять traffic counters напрямую.

## Telegram Identity

Список identities:

```http
GET /v1/me/identities
```

Создать link token:

```http
POST /v1/me/identities/telegram/link
```

Отвязать Telegram:

```http
DELETE /v1/me/identities/telegram
```

Mobile/Desktop может показать link token или открыть deep link в Telegram-бот, когда бот будет готов. Сервисные bot endpoints из приложения вызывать нельзя.

## Error Format

Core возвращает ошибки в формате:

```json
{
  "code": "ERROR_CODE_OR_MESSAGE",
  "error": "Human readable message or code"
}
```

Типовые статусы:

| HTTP | Что значит | Что делать приложению |
| --- | --- | --- |
| `400` | Невалидный запрос | Показать ошибку формы/валидации |
| `401` | Access token отсутствует/истек/невалиден | Refresh один раз, затем logout при повторной ошибке |
| `403` | Нет подписки, лимит, запрет роли | Показать экран тарифа/лимита |
| `404` | Сущность не найдена или не принадлежит пользователю | Обновить state, убрать устаревший объект |
| `500` | Ошибка Core | Показать retry/error state, залогировать request |

## Рекомендуемый app state machine

Минимальный startup flow:

```text
App start
  -> есть refresh_token?
    -> нет: Login/Register screen
    -> да: использовать access_token если есть
      -> GET /v1/client/bootstrap
        -> 200: Main screen
        -> 401: POST /v1/auth/refresh
          -> 200: сохранить новые tokens, повторить bootstrap
          -> 401: очистить session, Login/Register screen
```

Минимальный flow выдачи доступа:

```text
Main screen
  -> проверить active subscription
    -> нет: показать plans, POST /v1/subscriptions
  -> проверить current device
    -> нет: POST /v1/me/devices
  -> GET /v1/locations
  -> пользователь выбирает online node
  -> POST /v1/access/grants { node_id, device_id, protocol: "vless" }
  -> GET /v1/access/grants/{grantID}/config
    -> pending_node_ack: показать "конфигурация готовится", повторить polling
    -> ready: использовать connection_url/share_url
```

## Минимальные экраны приложения

Разработчику надо реализовать или связать с API:

- Login;
- Registration;
- Account overview;
- Plans/subscription;
- Devices;
- Locations;
- Access grants;
- VPN config/connect state;
- Usage;
- Logout.

## cURL smoke сценарий

Локальный smoke можно прогнать против Docker Core:

```bash
BASE=http://127.0.0.1:18080
EMAIL="app-dev-$(date +%s)@wavebreak.test"
PASSWORD="WaveBreakUser123!"

curl -s "$BASE/readyz"

REGISTER_RESPONSE=$(curl -s -X POST "$BASE/v1/auth/register" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\"}")

ACCESS_TOKEN=$(echo "$REGISTER_RESPONSE" | jq -r '.tokens.access_token')
REFRESH_TOKEN=$(echo "$REGISTER_RESPONSE" | jq -r '.tokens.refresh_token')

curl -s "$BASE/v1/client/bootstrap" \
  -H "Authorization: Bearer $ACCESS_TOKEN"

PLAN_ID=$(curl -s "$BASE/v1/plans" | jq -r '.plans[0].id')

curl -s -X POST "$BASE/v1/subscriptions" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"plan_id\":\"$PLAN_ID\"}"

DEVICE_RESPONSE=$(curl -s -X POST "$BASE/v1/me/devices" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name":"Developer Device","platform":"desktop"}')

DEVICE_ID=$(echo "$DEVICE_RESPONSE" | jq -r '.id')
NODE_ID=$(curl -s "$BASE/v1/locations" \
  -H "Authorization: Bearer $ACCESS_TOKEN" | jq -r '.nodes[0].id')

GRANT_RESPONSE=$(curl -s -X POST "$BASE/v1/access/grants" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"node_id\":\"$NODE_ID\",\"device_id\":\"$DEVICE_ID\",\"protocol\":\"vless\"}")

GRANT_ID=$(echo "$GRANT_RESPONSE" | jq -r '.id')

curl -s "$BASE/v1/access/grants/$GRANT_ID/config" \
  -H "Authorization: Bearer $ACCESS_TOKEN"

curl -s -X POST "$BASE/v1/auth/refresh" \
  -H "Content-Type: application/json" \
  -d "{\"refresh_token\":\"$REFRESH_TOKEN\"}"
```

## Что уже проверено

На текущем Docker stack проверен mobile/desktop happy path:

| Сценарий | Статус |
| --- | --- |
| Core readiness | PASSED |
| Register | PASSED |
| Refresh token | PASSED |
| Plans | PASSED |
| Subscription activation | PASSED |
| Device create | PASSED |
| Locations | PASSED |
| Device-bound access grant | PASSED |
| `GET /v1/client/bootstrap` | PASSED |
| `GET /v1/access/grants/{grantID}/config` | PASSED |
| Grant revoke | PASSED |

Также прошли:

```text
go test -race ./...
```

в Linux Docker для Core, и PHPUnit tests для Web/Admin после Composer install.

## Что пока не готово

Разработчику приложений важно знать ограничения:

- WireGuard/Outline конфигурация пока не генерируется;
- для pilot используется VLESS REALITY через `connection_url`;
- production domain/staging URL нужно выдать отдельно;
- реальная платежная интеграция ещё не подключена, MVP subscription активируется Core напрямую.

## Что нужно от разработчика приложения

Нужно подключить:

- HTTP client с base URL Core API;
- secure token storage;
- auth/register/login/refresh/logout;
- bootstrap hydration;
- subscription/plans screen;
- device registration;
- locations list;
- access grant creation with `device_id`;
- polling config endpoint;
- UI state для `pending_node_ack`;
- обработку `config_status = ready` и `connection_url`;
- cleanup при revoke/logout.

## Короткое сообщение, которое можно отправить разработчику

```text
Привет. Для подключения mobile/desktop к WAVEBREAK бери Core API из репозитория:
git@github.com:defloyder/wavebrake_project.git

Главный документ: MOBILE_DESKTOP_DEVELOPER_HANDOFF.md
Pilot testing: docs/mobile-desktop-pilot-testing.md
Подробный API: docs/mobile-desktop-api.md
OpenAPI: wavebreak-core/api/openapi.yaml
VPN config contract: docs/vpn-config-contract.md

Клиенты должны ходить только в Core API, не в Laravel и не в node-agent.
Pilot Core URL: http://91.149.241.52:18080
Локальный Core URL: http://127.0.0.1:18080

Основной flow:
1. POST /v1/auth/login или /v1/auth/register
2. GET /v1/client/bootstrap
3. POST /v1/subscriptions, если нет активной подписки
4. POST /v1/me/devices для текущего устройства
5. GET /v1/locations
6. POST /v1/access/grants с node_id, device_id, protocol=vless
7. GET /v1/access/grants/{grantID}/config

На pilot config endpoint возвращает персональную VLESS REALITY ссылку в connection_url/share_url. Если config_status = pending_node_ack, покажи "конфигурация готовится" и повтори запрос. Когда config_status = ready, ссылку можно передавать в VPN runtime.
```
