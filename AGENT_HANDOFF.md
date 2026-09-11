# WAVEBREAK Agent Handoff

## Mobile/Desktop API Integration Prep - 2026-09-11

The latest pass prepared the Core API contract for already-built mobile and desktop clients. No UI features were added.

### Added/updated implementation

- `wavebreak-core/internal/httpapi/server.go`
  - Added authenticated `GET /v1/client/bootstrap`.
  - Added authenticated `GET /v1/access/grants/{grantID}/config`.
  - Extended `POST /v1/access/grants` request with optional `device_id`.
- `wavebreak-core/internal/httpapi/product.go`
  - Added handlers for client bootstrap and grant config.
- `wavebreak-core/internal/store/product.go`
  - Added `ClientBootstrap` response composition.
  - Added `AccessGrantConfig` response composition.
- `wavebreak-core/internal/store/store.go`
  - `CreateAccessGrant` now validates an optional active user-owned device and persists `device_id`.
- `wavebreak-web/app/Services/CoreClient.php`
  - `createGrant` can pass `device_id` while remaining backward compatible for existing web forms.
- `wavebreak-core/api/openapi.yaml`
  - Documented bootstrap and grant-config endpoints.
- `docs/mobile-desktop-api.md`
  - Main handoff document for mobile/desktop developers.
- `docs/vpn-config-contract.md`
  - Contract and next backend steps for real VPN config generation.

### Current app contract

Recommended mobile/desktop flow:

1. `POST /v1/auth/login` or `POST /v1/auth/register`.
2. Store `access_token` and `refresh_token` securely.
3. `GET /v1/client/bootstrap`.
4. If needed, activate a plan through `POST /v1/subscriptions`.
5. Register/update the current device through `POST /v1/me/devices`.
6. List locations through `GET /v1/locations`.
7. Create access with `POST /v1/access/grants` and pass `device_id`.
8. Fetch config through `GET /v1/access/grants/{grantID}/config`.
9. Revoke through `POST /v1/access/grants/{grantID}/revoke`.

The config endpoint is intentionally honest about backend state:

- It returns `config_status: "pending_runtime_config"` today.
- It includes a stable WireGuard/Outline-shaped payload for client integration.
- It does not yet return real private server peer material, endpoint, client address, or ready-to-import WireGuard config.
- Real VPN config generation is the next backend milestone described in `docs/vpn-config-contract.md`.

### Validation

| Area | Status | Evidence |
| --- | --- | --- |
| Docker Core/API/worker restart | PASSED | Rebuilt images and recreated `wavebreak-api` / `wavebreak-worker`; Core healthy on `http://127.0.0.1:18080`. |
| Mobile/Desktop API smoke | PASSED | Register, refresh, plan list, subscription, device, location, device-bound grant, bootstrap, grant config, revoke. |
| Device-bound grant persistence | PASSED | `POST /v1/access/grants` returned the requested `device_id`. |
| VPN config endpoint | PASSED | `GET /v1/access/grants/{grantID}/config` returned `pending_runtime_config` with a WireGuard-shaped payload. |
| Core Linux race tests | PASSED | `docker run --rm -v "${PWD}:/src" -w /src/wavebreak-core golang:1.25.7 go test -race ./...`. |
| Web Composer install/tests | PASSED | Linux Docker Composer install completed; PHPUnit passed 2 tests / 2 assertions after install. |
| Admin Composer install/tests | PASSED | Linux Docker Composer install completed; PHPUnit passed 2 tests / 2 assertions after install. |
| GitHub push | BLOCKED | Workspace root is not a git repository and no GitHub remote/auth was provided. |

### Notes for next agent/developer

- The source root `C:\Work Folder\WaveBreak` currently has no `.git`; `git status` returns `fatal: not a git repository`.
- If the user wants a GitHub push, first initialize or point this workspace at the intended remote repository.
- Do not make the app clients synthesize server-side VPN config. Apps should consume the config endpoint and report clear "config pending" UI until Core returns `config_status: "ready"`.
- Keep Core as the only owner of subscription, device, grant, and VPN config state.

Этот документ нужен следующему агенту, чтобы быстро понять текущее состояние workspace после первичной реализации WAVEBREAK.

## Контекст

Пользователь передал большой master-spec для production-ready MVP платформы WAVEBREAK. Требуемая архитектура:

- `wavebreak-core`: Go Core API + worker, единственный владелец business logic и PostgreSQL schema.
- `wavebreak-web`: Laravel public website + user cabinet, только через Core API.
- `wavebreak-admin`: Laravel admin app, только через Core API.
- `wavebreak-node`: Go node agent.
- `wavebreak-infrastructure`: Docker Compose, monitoring, Nginx, bootstrap scripts.

Важно: не использовать старый branding, чужие namespaces, чужие Redis prefixes или старые service names. Всё должно называться `WAVEBREAK` / `wavebreak`.

## Latest Product/Core Completion Pass - 2026-09-11

Пользователь передал новый spec: довести Core/Product/API readiness без смены архитектуры. Выполнено поверх существующего workspace, без пересоздания проекта.

### Core additions

- Added migration `wavebreak-core/migrations/00002_product_core_completion.sql`.
- Users are now ready for email/password and Telegram-first accounts:
  nullable `email` / `password_hash`, `username`, `status`, `last_login_at`, `email_verified_at`, `deleted_at`.
- Added Telegram identity/link-token model:
  `user_identities`, `account_link_tokens`.
- Plans/subscriptions now include commercial and lifecycle fields:
  plan `price_minor`, `currency`, `duration_days`, `device_limit`, `traffic_limit_bytes`, `concurrent_connection_limit`, `is_active`, `is_public`, `sort_order`, `deleted_at`;
  subscription `source`, `source_reference`, `created_by`, limit snapshots, overrides, lifecycle timestamps/statuses.
- Added traffic accounting:
  `subscription_usage`, `subscription_usage_daily`, `grant_usage_counters`;
  node reports monotonic `bytes_up_total` / `bytes_down_total` counters per grant and Core handles counter reset.
- Devices now support `device_public_id`, `platform`, `last_seen_at`, and soft revoke.
- Access grants now track `subscription_id`, `device_id`, revoke metadata, and desired-state revision.
- Access grant create/revoke updates node desired-state and publishes outbox events.
- Added bot service token config: `WAVEBREAK_BOT_SERVICE_TOKEN`.

### Core API additions

```text
GET    /v1/me/overview
GET    /v1/me/identities
POST   /v1/me/identities/telegram/link
DELETE /v1/me/identities/telegram
GET    /v1/me/usage
GET    /v1/me/usage/history?period=7d|30d|current
GET    /v1/me/devices
POST   /v1/me/devices
PATCH  /v1/me/devices/{deviceID}
DELETE /v1/me/devices/{deviceID}
POST   /v1/access/grants/{grantID}/revoke
POST   /v1/node/usage
GET    /v1/admin/dashboard
GET    /v1/admin/users
GET    /v1/admin/plans
POST   /v1/admin/plans
PUT    /v1/admin/plans/{planID}
DELETE /v1/admin/plans/{planID}
GET    /v1/admin/subscriptions
PATCH  /v1/admin/subscriptions/{subscriptionID}/status
GET    /v1/admin/devices
POST   /v1/admin/devices/{deviceID}/revoke
GET    /v1/admin/traffic
GET    /v1/admin/audit
GET    /v1/admin/access/grants
POST   /v1/admin/access/grants/{grantID}/revoke
POST   /v1/bot/telegram/identify
GET    /v1/bot/users/{userID}/overview
```

OpenAPI was updated in `wavebreak-core/api/openapi.yaml`.

### Laravel additions

- `wavebreak-web` CoreClient now consumes Core overview, usage, usage history, devices, Telegram link/unlink, and grant revoke.
- `wavebreak-web` dashboard has a new `/dashboard/devices` section and no longer crashes for users without active subscription usage.
- `wavebreak-admin` CoreClient now consumes Core admin dashboard, users, plans, subscriptions, devices, traffic, audit, grants, status updates, and revoke.
- `wavebreak-admin` routes/pages now include `/users`, `/subscriptions`, `/grants`, `/devices`, `/traffic`, `/audit`.
- Added `bootstrap/cache/*.php` to `wavebreak-admin/.dockerignore` to prevent dev-only Laravel cache from entering production image.

### Runtime fixes found and fixed

- Migration `00002` initially failed because `created_at` was ambiguous in the subscription backfill; fixed with `s.created_at`.
- Access grant revoke initially failed because a UUID ownership filter compared against an empty string for admin mode; fixed by casting the compared user id to text.
- Web dashboard initially returned 500 after fresh registration because usage 404 was treated as an exception; fixed CoreClient usage/history fallbacks.
- Admin container initially failed with `Laravel\Pail\PailServiceProvider` because cached dev package metadata was copied into no-dev runtime image; fixed admin `.dockerignore`.
- Admin `/users` initially returned 500 for users without `username`; fixed Blade fallback.

### Validation Table

| Area | Status | Evidence |
| --- | --- | --- |
| Database migrations | PASSED | `wavebreak-migrate` applied Goose version `2` on live PostgreSQL. |
| Core API compile/tests | PASSED | `docker run ... golang:1.25.7 go test ./...`. |
| Core race tests | PASSED | `docker run ... golang:1.25.7 go test -race ./...`. |
| Product/Core HTTP E2E | PASSED | readyz, admin RBAC, node enrollment, subscription snapshots, overview, device, Telegram link/bot identify, grant create, desired-state ACK, usage aggregate, revoke, admin reads. |
| Laravel Web Composer/tests | PASSED | Linux Docker Composer install; `php artisan test` passed 2 tests / 2 assertions. |
| Laravel Admin Composer/tests | PASSED | Linux Docker Composer install; `php artisan test` passed 2 tests / 2 assertions. |
| Web Docker smoke | PASSED | public pages plus `/dashboard`, `/dashboard/subscription`, `/dashboard/access`, `/dashboard/nodes`, `/dashboard/devices`. |
| Admin Docker smoke | PASSED | `/dashboard`, `/nodes`, `/plans`, `/enroll`, `/users`, `/subscriptions`, `/grants`, `/devices`, `/traffic`, `/audit`. |
| Compose default stack | PASSED | PostgreSQL, Redis, RabbitMQ, Core API, worker, Web, Admin, Prometheus, Grafana, Loki, Tempo, OTel Collector, Alertmanager, node-exporter, cAdvisor are Up; healthchecks green where defined. |
| Real payment provider | BLOCKED | Not requested for this stop point; schema abstraction exists, provider integration remains future work. |
| Real VPN/proxy runtime apply | BLOCKED | Stop point says not to implement real network runtime/config; node runtime adapter remains no-op. |

## Что уже сделано

### Root

- Создан общий workspace layout:

```text
WAVEBREAK
├── wavebreak-core
├── wavebreak-web
├── wavebreak-admin
├── wavebreak-node
├── wavebreak-infrastructure
├── docs
├── .github/workflows
├── README.md
├── AGENT_HANDOFF.md
└── .gitignore
```

- Root README описывает архитектуру, локальный запуск, production notes.
- CI добавлен в `.github/workflows/wavebreak-ci.yml`.

### wavebreak-core

Реализован Go modular monolith:

- `cmd/wavebreak-api`: HTTP API.
- `cmd/wavebreak-worker`: outbox publisher worker.
- `internal/config`: env-based config.
- `internal/database`: pgxpool setup.
- `internal/store`: PostgreSQL repository/domain operations.
- `internal/httpapi`: REST handlers and JWT auth.
- `internal/messaging`: RabbitMQ topology and event publishing.
- `internal/redisstore`: Redis heartbeat cache with `wavebreak:*` namespace.
- `internal/observability`: Prometheus metrics middleware/counters.

Core endpoints implemented:

```text
GET  /healthz
GET  /readyz
GET  /metrics
POST /v1/auth/register
POST /v1/auth/login
POST /v1/auth/refresh
GET  /v1/me
GET  /v1/plans
POST /v1/subscriptions
GET  /v1/subscriptions/current
GET  /v1/nodes
POST /v1/nodes/enroll
POST /v1/nodes/{nodeID}/heartbeat
GET  /v1/access/grants
POST /v1/access/grants
```

Database:

- Migration: `wavebreak-core/migrations/00001_initial.sql`.
- Includes required tables from the spec:
  `users`, `sessions`, `devices`, `plans`, `subscriptions`, `payments`,
  `nodes`, `node_protocols`, `node_enrollment_tokens`, `access_credentials`,
  `access_grants`, `config_versions`, `audit_events`, `webhook_events`,
  `idempotency_keys`, `outbox_events`, `processed_messages`,
  `node_usage_reports`, `notifications`, `admin_actions`.
- Seeds initial plans.
- Uses transactional outbox for subscription activation, node online, access grant created.

OpenAPI:

- `wavebreak-core/api/openapi.yaml`.

Docker:

- `wavebreak-core/Dockerfile`.
- `wavebreak-core/.dockerignore`.
- `wavebreak-core/Makefile`.

### wavebreak-node

Реализован отдельный Go node agent:

- `cmd/wavebreak-node`: entrypoint.
- `internal/config`: env config.
- `internal/agent`: enroll + heartbeat loop.

Behavior:

- Requires `WAVEBREAK_NODE_ENROLLMENT_TOKEN` for first enrollment or `WAVEBREAK_NODE_API_TOKEN` after enrollment.
- Calls Core:
  - `POST /v1/nodes/enroll`
  - `POST /v1/nodes/{nodeID}/heartbeat`
- Does not talk to Laravel directly.

Docker:

- `wavebreak-node/Dockerfile`.
- `wavebreak-node/.dockerignore`.
- `wavebreak-node/Makefile`.

### wavebreak-web

Laravel app skeleton was created with Composer, then customized.

Added:

- `app/Services/CoreClient.php`: Core HTTP client.
- `app/Http/Controllers/WebController.php`: web flow.
- `routes/web.php`: public/user cabinet routes.
- `resources/views/layout.blade.php`
- `resources/views/home.blade.php`
- `resources/views/dashboard.blade.php`
- `Dockerfile`
- `.dockerignore`
- `README.md`

Implemented screens/workflows:

- Home page with Core health and plans.
- Login.
- Registration.
- User dashboard.
- Current subscription view/create.
- Nodes list.
- Access grant create/list.

Architectural constraint preserved:

- Laravel Web calls Core API only.
- It does not migrate or mutate Core PostgreSQL tables directly.

### wavebreak-admin

Laravel app skeleton was created with Composer, then customized.

Added:

- `app/Services/CoreClient.php`: Core HTTP client.
- `app/Http/Controllers/AdminController.php`: admin flow.
- `routes/web.php`: admin routes.
- `resources/views/layout.blade.php`
- `resources/views/login.blade.php`
- `resources/views/dashboard.blade.php`
- `Dockerfile`
- `.dockerignore`
- `README.md`

Implemented screens/workflows:

- Admin login.
- Core health display.
- Admin role check via Core JWT claims.
- Plans view.
- Nodes table.
- Node enroll form.

Architectural constraint preserved:

- Laravel Admin calls Core API only.
- It does not migrate or mutate Core PostgreSQL tables directly.

### wavebreak-infrastructure

Added Docker Compose MVP stack:

- PostgreSQL 17
- Redis 8
- RabbitMQ 4 management
- `wavebreak-api`
- `wavebreak-worker`
- `wavebreak-web`
- `wavebreak-admin`
- `wavebreak-node` profile
- Prometheus
- Grafana
- Loki
- Tempo
- OpenTelemetry Collector
- Alertmanager
- node_exporter
- cAdvisor

Files:

- `wavebreak-infrastructure/docker-compose.yml`
- `monitoring/prometheus/prometheus.yml`
- `monitoring/prometheus/rules.yml`
- `monitoring/otel/config.yml`
- `monitoring/tempo.yaml`
- `monitoring/alertmanager/alertmanager.yml`
- Grafana datasource/dashboard provisioning
- `nginx/wavebreak.conf.template`
- `scripts/bootstrap-core.sh`
- `scripts/bootstrap-web.sh`
- `scripts/bootstrap-node.sh`
- `scripts/bootstrap-monitoring.sh`
- `README.md`

### docs

Added:

- `docs/database-schema.md`
- `docs/rabbitmq-topology.md`
- `docs/core-api-endpoints.md`
- `docs/deployment.md`
- `docs/backup-restore.md`
- `docs/known-mvp-limitations.md`
- `docs/roadmap.md`
- `docs/results.md`

## Verification Already Run

The following passed locally:

```powershell
cd "C:\Work Folder\WaveBreak\wavebreak-core"
$env:GOMODCACHE='C:\Work Folder\WaveBreak\.gocache\pkg\mod'
$env:GOPATH='C:\Work Folder\WaveBreak\.gocache'
go test ./...
go build ./cmd/wavebreak-api ./cmd/wavebreak-worker
```

```powershell
cd "C:\Work Folder\WaveBreak\wavebreak-node"
$env:GOMODCACHE='C:\Work Folder\WaveBreak\.gocache\pkg\mod'
$env:GOPATH='C:\Work Folder\WaveBreak\.gocache'
go test ./...
go build ./cmd/wavebreak-node
```

```powershell
cd "C:\Work Folder\WaveBreak\wavebreak-web"
php -l app\Services\CoreClient.php
php -l app\Http\Controllers\WebController.php
php -l config\app.php
php -l config\services.php
php -l routes\web.php
```

```powershell
cd "C:\Work Folder\WaveBreak\wavebreak-admin"
php -l app\Services\CoreClient.php
php -l app\Http\Controllers\AdminController.php
php -l config\app.php
php -l config\services.php
php -l routes\web.php
```

```powershell
cd "C:\Work Folder\WaveBreak\wavebreak-infrastructure"
docker compose config --quiet
```

## Known Local Blockers

### Go race tests

`go test -race ./...` is blocked on this Windows host because `gcc` is not installed in `PATH`. Go race detector requires cgo.

Observed error:

```text
cgo: C compiler "gcc" not found
```

Expected fix:

- Install a working C compiler toolchain, or run race tests in Linux/WSL/CI.

### Laravel Composer install

Composer created both Laravel skeletons, but dependency installation failed locally on Windows when Composer fell back to source installs.

Observed error:

```text
error: invalid path 'tests/fixtures/env/nul.env'
```

This comes from a dependency fixture path reserved on Windows, likely while installing `vlucas/phpdotenv` from source.

Expected fix:

- Run Composer in WSL/Linux, or
- Configure GitHub auth / network so Composer uses dist archives reliably, or
- Build Laravel Docker images in Linux Docker context.

Dockerfiles for `wavebreak-web` and `wavebreak-admin` install vendor dependencies inside Linux via a `composer:2` stage.

### Docker image builds

Docker CLI exists, but Docker Desktop Linux engine was not running.

Observed error:

```text
open //./pipe/dockerDesktopLinuxEngine: The system cannot find the file specified
```

Expected fix:

- Start Docker Desktop Linux engine and rerun Docker builds / Compose boot.

## Important Next Steps

1. Run migrations against PostgreSQL:

```bash
cd wavebreak-core
goose -dir migrations postgres "$WAVEBREAK_DATABASE_URL" up
```

2. Boot Compose stack after Docker engine is running:

```bash
cd wavebreak-infrastructure
docker compose up -d postgres redis rabbitmq
docker compose up -d wavebreak-api wavebreak-worker
docker compose up -d prometheus grafana loki tempo otel-collector alertmanager node-exporter cadvisor
```

3. Create/register an admin user.

Current Core registration defaults users to `role = 'user'`. For admin testing, either:

- add a temporary Core endpoint/seed for admin creation, or
- update a test user role in PostgreSQL manually for local MVP testing.

4. Expand Core tests.

Current Go tests are compile/package tests only. Add unit/integration tests for:

- auth/token flows,
- store methods,
- outbox behavior,
- RabbitMQ topology declaration,
- HTTP handlers,
- idempotency handling.

5. Improve production readiness:

- full OpenTelemetry tracing,
- sqlc query generation,
- admin MFA/RBAC,
- real billing adapters,
- real node protocol config sync,
- complete Grafana dashboards,
- backup automation,
- container scanning.

## Notes For The Next Agent

- Preserve the architectural boundary: Core owns business logic and DB schema.
- Do not add Laravel migrations for Core-owned tables.
- Do not let Laravel talk directly to nodes.
- Keep Redis keys under `wavebreak:*` or WAVEBREAK-specific Laravel prefixes.
- Keep Docker services and namespaces named `wavebreak-*`.
- Avoid reintroducing starter Laravel branding in visible docs/views.
- `.gocache/` and Laravel `vendor/` are ignored.
- There may be incomplete local `vendor` directories inside Laravel apps due to the Composer failure; do not rely on them as authoritative.

## Production Readiness Pass 1

Pass 1 was applied on top of the initial MVP without renaming repositories or changing the main architecture.

### Major Findings

- Refresh tokens were reusable and not rotated.
- Core login used bcrypt only; spec asked for Argon2id for admin bootstrap.
- `users.role` only allowed `user/admin`, while the spec requires `support/admin/superadmin`.
- Admin bootstrap required manual SQL role changes.
- Node agent used a user/admin JWT for enrollment and heartbeat.
- Node desired-state sync was missing.
- RabbitMQ published persistent messages but did not wait for publisher confirms.
- Compose did not run Core migrations automatically.
- Monitoring had only the initial overview dashboard and minimal rules.
- Backup/restore existed only as documentation snippets.

### Pass 1 Changes

Core:

- Added `internal/security` with Argon2id password hashing, legacy bcrypt verification, random token generation, and token hashing.
- Updated auth flow:
  - register hashes with Argon2id;
  - login rejects disabled users;
  - refresh token rotation is transactional;
  - refresh token reuse is detected and active sessions for the user are revoked;
  - logout revokes refresh tokens.
- Added RBAC middleware and role set: `user`, `support`, `admin`, `superadmin`.
- Added `wavebreak-cli`:
  - `wavebreak-cli admin create`;
  - `wavebreak-cli admin reset-password`;
  - `wavebreak-cli node token`.
- Added `wavebreak-migrate` to run goose migrations inside the Core image.
- Added node-token based API:
  - `POST /v1/node/enroll`;
  - `POST /v1/node/heartbeat`;
  - `GET /v1/node/state`;
  - `POST /v1/node/state/ack`;
  - `POST /v1/node/state/fail`.
- Added admin desired-state endpoint:
  - `POST /v1/nodes/{nodeID}/desired-state`.
- Added user-visible location endpoint:
  - `GET /v1/locations`.
- Added publisher confirms to RabbitMQ publisher.
- Added production config fail-fast checks for weak/default Core secrets.

Database migration:

- `users` now supports `support/admin/superadmin`, `disabled_at`, and MFA placeholder fields.
- `sessions` now supports revocation reason and `replaced_by_session_id`.
- `nodes` now supports `api_token_hash`, `desired_revision`, `applied_revision`, and `last_sync_error`.
- `config_versions` now supports failed apply reporting.

Node:

- `wavebreak-node` now uses `WAVEBREAK_NODE_ENROLLMENT_TOKEN` or `WAVEBREAK_NODE_API_TOKEN`.
- Added desired-state fetch/apply/ACK/fail loop.
- Added `RuntimeAdapter` interface and a no-op adapter implementation.
- Added exponential reconnect/backoff with jitter.

Laravel:

- Core clients now use safe retries only for idempotent GET requests.
- Core clients propagate/request `X-Request-ID`.
- Web uses `/v1/locations` instead of admin node listing.
- Web logout calls Core refresh-token revocation.
- Admin accepts `admin` and `superadmin` roles.

Infrastructure:

- Added `wavebreak-migrate` service.
- Added healthchecks for Core, Web, Admin, Prometheus, Grafana.
- Added PostgreSQL and Redis exporters.
- Added backup/restore scripts:
  - `scripts/backup-postgres.sh`;
  - `scripts/restore-postgres.sh`.
- Expanded Prometheus alert rules.
- Added provisioned Grafana dashboards for Overview, Core, Nodes, RabbitMQ, PostgreSQL, Redis, and Infrastructure.

CI:

- Go jobs now include `govulncheck`, `golangci-lint`, race tests, and build all Core binaries.
- Laravel jobs include `composer audit`.
- Docker job validates Compose config.

### Pass 1 Tests Added

- `wavebreak-core/internal/security`: Argon2id hash/verify, legacy bcrypt verify, token generation/hash.
- `wavebreak-core/internal/config`: production default validation.
- `wavebreak-core/internal/store`: migration contract assertions for RBAC, refresh rotation, node tokens, desired state.
- `wavebreak-node/internal/agent`: enrollment, heartbeat, desired-state fetch and ACK.

### Verification After Pass 1

Passed locally:

```powershell
cd wavebreak-core
$env:GOMODCACHE='C:\Work Folder\WaveBreak\.gocache\pkg\mod'
$env:GOPATH='C:\Work Folder\WaveBreak\.gocache'
go test ./...
go build ./cmd/wavebreak-api ./cmd/wavebreak-worker ./cmd/wavebreak-cli ./cmd/wavebreak-migrate
```

```powershell
cd wavebreak-node
$env:GOMODCACHE='C:\Work Folder\WaveBreak\.gocache\pkg\mod'
$env:GOPATH='C:\Work Folder\WaveBreak\.gocache'
go test ./...
go build ./cmd/wavebreak-node
```

```powershell
cd wavebreak-infrastructure
docker compose config --quiet
```

Laravel PHP syntax checks passed for the modified CoreClient/controller/routes files in both apps.

Blocked by environment:

- `go test -race ./...` still fails because `gcc` is not in `PATH`.
- Docker image build still fails because Docker Desktop Linux engine is not running.
- Full Laravel tests still depend on a clean Composer install on Linux/WSL or successful dist downloads.

### Remaining High-Priority Work

1. Add Core integration tests with PostgreSQL, Redis, and RabbitMQ.
2. Implement real admin MFA and recovery-code flow.
3. Add RBAC management APIs/screens and audit event review.
4. Replace no-op node runtime adapter with real protocol adapters.
5. Run full Docker Compose boot and migration validation once Docker engine is available.

## Production Readiness Pass 2 - Linux/Docker Integration Validation - 2026-09-03

This pass booted the full WAVEBREAK stack in WSL Ubuntu using the Linux Docker Engine and validated the existing architecture end to end. No UI work or new product features were added.

### Runtime fixes applied

- `wavebreak-infrastructure/docker-compose.yml`
  - Changed unavailable `gcr.io/cadvisor/cadvisor:v0.53.0` to `v0.52.1`.
  - Made Core and Grafana host ports configurable with `WAVEBREAK_API_PORT` and `WAVEBREAK_GRAFANA_PORT`.
  - Made node-agent code/region configurable for isolated E2E runs.
- `wavebreak-infrastructure/.env`
  - Added local port overrides: Core `18080`, Grafana `13000`, avoiding existing host services on `8080` and `3000`.
- `wavebreak-web/Dockerfile` and `wavebreak-admin/Dockerfile`
  - Removed build-time `.env` creation so Compose-provided `APP_KEY` is not shadowed by a baked empty key.
- `wavebreak-node/internal/agent/agent.go`
  - Fixed node self-enrollment payload to send only `code`; Core rejects unknown JSON fields and the previous `region` field caused 400 responses.
- `wavebreak-core/internal/messaging/rabbitmq.go`
  - Fixed DLQ routing so job queues dead-letter to their own routing keys and each DLQ binds only to its matching key.
- `wavebreak-core/internal/httpapi/auth.go`
  - Added JSON tags to `authUser` so `/v1/me` returns `id`, `email`, and `role`, matching Laravel clients.
- `wavebreak-web/app/Services/CoreClient.php`
  - Treated `GET /v1/subscriptions/current` 404 as no active subscription instead of throwing inside the Web dashboard flow.

### Stack state

The full Compose stack is running in Linux Docker:

- PostgreSQL 17, Redis 8, RabbitMQ 4 management.
- Core API on host `18080`.
- Core worker.
- Laravel Web on host `8000`.
- Laravel Admin on host `8002`.
- Node agent.
- Monitoring: Prometheus `9090`, Grafana `13000`, Loki `3100`, Tempo `3200`, Alertmanager `9093`, cAdvisor `8081`, node-exporter, PostgreSQL exporter, Redis exporter, OpenTelemetry Collector.

Migrations ran through `wavebreak-migrate`; latest log shows version `1` with no pending migrations.

### Validation matrix

| Area | Status | Evidence |
| --- | --- | --- |
| Compose boot | PASSED | All required service containers running; Core/Web/Admin/Grafana/Prometheus/cAdvisor healthy. |
| Migrations | PASSED | `wavebreak-migrate` completed; latest log: current version `1`. |
| Core health/readiness | PASSED | `GET /readyz` and `GET /healthz` returned 200. |
| Auth flow | PASSED | Register, login, bad-password reject, refresh rotation, refresh reuse detection, `/v1/me`, logout validated through Core. |
| Subscription flow | PASSED | Plans listed; subscription create/current validated through Core and Laravel Web. |
| Node enrollment | PASSED | CLI token issued; node self-enroll passed; Admin Laravel node enroll form passed. |
| Heartbeat | PASSED | Node agent logs repeated `heartbeat acknowledged`; DB node state online. |
| Desired-state sync and ACK | PASSED | Core desired state created; API state fetch, ACK, fail-report checked; real node-agent logged `desired state applied`. |
| Access grant create/list | PASSED | Core create/list passed; Laravel Web access grant form posted through Core. |
| Access revoke | BLOCKED | Current Core exposes only `GET/POST /v1/access/grants`; no revoke/delete/patch route exists. Not added because this pass forbids new features. |
| RabbitMQ outbox publish | PASSED | Worker published subscription/node/access outbox events. |
| RabbitMQ retry | PASSED | Broker was stopped, worker marked outbox attempt failed, broker restarted, worker later published the same event. |
| RabbitMQ DLQ | PASSED | Rejecting one `access.created` message placed it only in `wavebreak.deadletter.access`; other DLQs remained empty after routing fix. |
| Laravel -> Core flows | PASSED | Web register -> dashboard -> subscription -> access grant and Admin login -> node enroll validated via real HTTP forms, cookies, and CSRF. |
| Monitoring | PASSED | Prometheus active targets all up: cadvisor, node-exporter, otel-collector, postgres, rabbitmq, redis, wavebreak-core. |
| Core Linux race tests | PASSED | Docker/Linux `go test -race ./...` passed for `wavebreak-core`. |
| Node Linux race tests | PASSED | Docker/Linux `go test -race ./...` passed for `wavebreak-node`. |
| Laravel Web tests | PASSED_WITH_WARNING | Composer install completed; `php artisan test` exit code 0, with one existing Feature ExampleTest warning. |
| Laravel Admin tests | PASSED_WITH_WARNING | Composer install completed; `php artisan test` exit code 0, with one existing Feature ExampleTest warning. |

### Useful commands from this pass

```bash
cd "/mnt/c/Work Folder/WaveBreak/wavebreak-infrastructure"
docker compose up -d --build
docker compose ps
docker compose logs wavebreak-migrate wavebreak-node wavebreak-worker
```

Core race tests were run in Linux Docker because WSL has no host Go toolchain installed:

```bash
cd "/mnt/c/Work Folder/WaveBreak/wavebreak-core"
DOCKER_BUILDKIT=1 docker build --progress=plain -f - . <<'EOF'
FROM golang:1.25-alpine
WORKDIR /src
RUN apk add --no-cache build-base
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN go test -race ./...
EOF
```

Node race tests:

```bash
cd "/mnt/c/Work Folder/WaveBreak/wavebreak-node"
DOCKER_BUILDKIT=1 docker build --progress=plain -f - . <<'EOF'
FROM golang:1.25-alpine
WORKDIR /src
RUN apk add --no-cache build-base
COPY go.mod ./
RUN go mod download
COPY . .
RUN go test -race ./...
EOF
```

Laravel tests after Composer install:

```bash
cd "/mnt/c/Work Folder/WaveBreak/wavebreak-web"
DOCKER_BUILDKIT=1 docker build --progress=plain --add-host host.docker.internal:host-gateway -f - . <<'EOF'
FROM composer:2
WORKDIR /app
COPY . .
ENV APP_ENV=testing
ENV APP_KEY=base64:MTIzNDU2Nzg5MDEyMzQ1Njc4OTAxMjM0NTY3ODkwMTI=
ENV WAVEBREAK_CORE_URL=http://host.docker.internal:18080
RUN composer install --prefer-dist --no-interaction --no-progress
RUN php artisan test
EOF
```

Repeat the same command from `wavebreak-admin`.

### Remaining gaps after Pass 2

- Access grant revoke cannot be validated until the architecture has an explicit revoke endpoint or equivalent contract.
- Laravel default Feature ExampleTest emits a warning, but exits 0; it should be cleaned up when adding meaningful Laravel feature tests.
- RabbitMQ consumer semantics are still limited to publisher/outbox/topology/DLQ validation; no domain consumer worker was added in this pass.

## Legacy `app` Style Transfer Pass - 2026-09-03

The user asked to take the old website/admin visual style from the legacy `app` directory and apply it across the current WAVEBREAK Web/Admin projects, excluding old logos and old names. No new product features were added.

### Source files inspected/transferred

Legacy CSS source:

- `app/public/css/landing.css`
- `app/public/css/cabinet.css`
- `app/public/css/auth.css`
- `app/public/css/admin.css`
- `app/public/css/faq.css`
- `app/public/css/public-redesign.css`

Transferred/adapted Web assets:

- `wavebreak-web/public/css/landing.css`
- `wavebreak-web/public/css/cabinet.css`
- `wavebreak-web/public/css/auth.css`
- `wavebreak-web/public/css/faq.css`
- `wavebreak-web/public/css/public-redesign.css`
- `wavebreak-web/public/css/wavebreak-overrides.css`

Transferred/adapted Admin assets:

- `wavebreak-admin/public/css/admin.css`
- `wavebreak-admin/public/css/auth.css`
- `wavebreak-admin/public/css/wavebreak-overrides.css`

Old brand strings were mechanically replaced:

- `Auralith` -> `WAVEBREAK`
- `auralith` -> `wavebreak`
- `Ауралит` -> `WAVEBREAK`

Old logo/image references were removed from the new Web/Admin surface; visual marks are CSS-based `WB` marks instead of copied logo files.

### Templates updated

Web:

- `wavebreak-web/resources/views/layout.blade.php`
- `wavebreak-web/resources/views/home.blade.php`
- `wavebreak-web/resources/views/dashboard.blade.php`

Admin:

- `wavebreak-admin/resources/views/layout.blade.php`
- `wavebreak-admin/resources/views/login.blade.php`
- `wavebreak-admin/resources/views/dashboard.blade.php`

The updated templates preserve the existing Laravel -> Core flows and route/form contracts:

- Web login/register/logout.
- Web subscription create/current.
- Web access grant create/list.
- Admin login/logout.
- Admin node enrollment.

### Validation after style transfer

Blade syntax:

- `php -l` passed for all edited Web/Admin Blade templates.

Docker runtime:

- Rebuilt and recreated `wavebreak-web` and `wavebreak-admin` in the existing Linux Docker Compose stack.
- Web reachable at `http://127.0.0.1:8000`.
- Admin reachable at `http://127.0.0.1:8002`.

Real HTTP form E2E checks:

| Flow | Status |
| --- | --- |
| Web home renders legacy-style landing | PASSED |
| Web HTML has no old logo/name references | PASSED |
| Web register -> styled dashboard | PASSED |
| Web dashboard keeps subscription/node selectors | PASSED |
| Web subscription create flow | PASSED |
| Web access grant create flow | PASSED |
| Admin login page renders legacy auth style | PASSED |
| Admin login HTML has no old logo/name references | PASSED |
| Admin login -> styled dashboard | PASSED |
| Admin node enrollment form | PASSED |

Total: 11 passed, 0 failed.

Laravel tests after Composer install:

- `wavebreak-web`: `php artisan test` exit code 0; 1 existing default Feature ExampleTest warning.
- `wavebreak-admin`: `php artisan test` exit code 0; 1 existing default Feature ExampleTest warning.

Screenshots captured for visual sanity:

- `wavebreak-web-home.png`
- `wavebreak-admin-login.png`

### Notes for next agent

- Do not reintroduce old Auralith logos/names.
- The old visual language is now carried mostly by copied CSS plus small WAVEBREAK override files.
- The transfer intentionally keeps the current product architecture and workflows; it does not restore old legacy `app` features or routes.
- The old CSS is large and selector-heavy. Prefer small override patches over editing the copied legacy files unless a specific visual bug requires it.

### Local dev login accounts

For the currently running local Docker stack:

- Web user: `dev-user@wavebreak.test` / `WaveBreakUser123!`
- Admin user: `admin@wavebreak.test` / `WaveBreakAdmin123!`

Entry points:

- Web: `http://127.0.0.1:8000`
- Admin: `http://127.0.0.1:8002`

Admin has no `GET /login` page; the sign-in screen is served from `/`, and the form posts to `/login`.

## Client Site Redesign Pass - 2026-09-03

The user rejected the legacy-style client site as visually broken and asked for a full client-site redesign in a unified WAVEBREAK style. The Web client was rebuilt around a new dark technical visual system with marker-like line accents, real logo usage, separate public pages, and separate cabinet sections. Core architecture and existing product flows were preserved.

### Web files changed

- `wavebreak-web/public/css/wavebreak-site.css`
- `wavebreak-web/public/images/wavebreak-logo-mark.png`
- `wavebreak-web/resources/views/layout.blade.php`
- `wavebreak-web/resources/views/home.blade.php`
- `wavebreak-web/resources/views/pricing.blade.php`
- `wavebreak-web/resources/views/access.blade.php`
- `wavebreak-web/resources/views/auth.blade.php`
- `wavebreak-web/resources/views/dashboard.blade.php`
- `wavebreak-web/app/Http/Controllers/WebController.php`
- `wavebreak-web/routes/web.php`

### New Web routes

- `GET /`
- `GET /pricing`
- `GET /access`
- `GET /login`
- `GET /register`
- `POST /login`
- `POST /register`
- `POST /logout`
- `GET /dashboard`
- `GET /dashboard/subscription`
- `GET /dashboard/access`
- `GET /dashboard/nodes`
- `POST /subscriptions`
- `POST /access/grants`

### Client UX changes

- Registration/login forms were removed from the bottom of the landing page and moved to dedicated pages.
- `/dashboard` now redirects unauthenticated users to `/login`, so the cabinet button behaves predictably.
- The cabinet now uses real pages for overview, subscription, access, and nodes rather than anchor sections.
- Invalid login/register/Core failures now return form errors instead of surfacing as raw runtime failures.
- Old Web CSS files remain in `public/css`, but the redesigned Web views only load `wavebreak-site.css`.
- The real WAVEBREAK logo is used from `images/wavebreak-logo.png`; old names/logos are not reintroduced.

### Admin fixes applied during the same pass

- Admin sidebar now uses the real PNG logo.
- Admin menu routes were added for `/dashboard`, `/nodes`, `/plans`, and `/enroll`.
- Admin dashboard rendering is section-based.
- Scroll-lock from legacy `admin.css` was overridden in `wavebreak-admin/public/css/wavebreak-overrides.css`.

### Validation after redesign

- PHP syntax passed for all changed Web/Admin controllers, routes, and Blade views.
- Docker rebuilt/recreated `wavebreak-web` and `wavebreak-admin`; both are healthy.
- Web HTTP validation passed for `/`, `/pricing`, `/access`, `/login`, `/register`, `/dashboard`, `/dashboard/subscription`, `/dashboard/access`, and `/dashboard/nodes`.
- Web login form with `dev-user@wavebreak.test` / `WaveBreakUser123!` redirects to `/dashboard`.
- Admin login and section routes passed for `/dashboard`, `/nodes`, `/plans`, and `/enroll`.
- Laravel tests after Composer install:
  - `wavebreak-web`: `php artisan test` exit code 0; 1 existing default Feature ExampleTest warning.
  - `wavebreak-admin`: `php artisan test` exit code 0; 1 existing default Feature ExampleTest warning.

Screenshots captured:

- `wavebreak-web-new-home.png`
- `wavebreak-web-new-home-mobile.png`
- `wavebreak-web-new-login.png`
- `wavebreak-web-new-pricing.png`
- `wavebreak-web-new-access.png`

## Client Copy/Design Polish Pass - 2026-09-04

The user rejected generic SaaS copy and asked for normal, concrete Russian text plus more polished design details. The Web client was tightened around a clearer WAVEBREAK concept: a dark access-control room with a live signal module and a visible route from account to subscription, access grant, desired-state, heartbeat, and ACK.

### Web files changed

- `wavebreak-web/resources/views/home.blade.php`
- `wavebreak-web/resources/views/pricing.blade.php`
- `wavebreak-web/resources/views/access.blade.php`
- `wavebreak-web/resources/views/auth.blade.php`
- `wavebreak-web/resources/views/dashboard.blade.php`
- `wavebreak-web/public/css/wavebreak-site.css`
- `wavebreak-web/.dockerignore`

### What changed

- Replaced AI-sounding mixed Russian/English copy with concise Russian product text.
- Rewrote the rejected hero and route-section copy again after user feedback:
  - Hero now leads with "Приватный доступ без ручной настройки".
  - Route section now explains the actual user/system flow: registration, tariff, access grant, node confirmation.
- Kept technical terms only where they describe real platform behavior: Core API, access grant, desired-state, heartbeat, ACK.
- Reworked plan descriptions so Starter, Plus, and Fleet have distinct positioning even when Core returns codes like `STARTER-MONTHLY`.
- Shortened the access page headline to avoid ugly browser hyphenation.
- Fixed the signal waveform CSS: the old `calc(... % ...)` expression was invalid CSS, so bars now use valid `nth-child` height/opacity rules.
- Fixed route-card staggering so the hidden route line no longer affects which step is offset.
- Added `wb-page-slab` and `wb-note-panel` styling for pricing/access supporting sections.
- Added small interaction and visual polish to buttons, cards, route board, and the signal module.
- Added `bootstrap/cache/*.php` to Web `.dockerignore`; the rebuilt runtime image previously copied local Laravel cache referencing dev-only `Laravel\Pail\PailServiceProvider`, which broke `wavebreak-web` after `composer install --no-dev`.

### Validation

- PHP syntax passed for changed Web Blade files.
- Rebuilt and recreated `wavebreak-web` with Docker Compose using local cached base layers.
- HTTP smoke/E2E passed for `/`, `/pricing`, `/access`, `/login`, `/register`, `/dashboard`, `/dashboard/subscription`, `/dashboard/access`, `/dashboard/nodes`.
- Login E2E with CSRF passed for `dev-user@wavebreak.test` / `WaveBreakUser123!`.
- Laravel tests passed locally with `APP_KEY=base64:14+g+7SB0RMz9Ri0+bS5TLRK6cXaBrS16EcJAjj3PTI=` and `WAVEBREAK_CORE_URL=http://127.0.0.1:18080`: 2 tests, 2 passed.
- Laravel tests also passed in a temporary Linux Docker test copy on the Compose network: 2 tests, 2 passed.
- After the final copy rewrite, HTTP smoke/E2E passed again and `wavebreak-web` is healthy.

Screenshots captured:

- `wavebreak-web-final-copy-home.png`
- `wavebreak-web-final-copy-home-mobile.png`
- `wavebreak-web-final-copy-pricing.png`
- `wavebreak-web-final-copy-access.png`
- `wavebreak-web-copy-rewrite-home.png`
- `wavebreak-web-copy-rewrite-home-mobile.png`
- `wavebreak-web-copy-rewrite-access.png`
