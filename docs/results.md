# WAVEBREAK Build Results

Current verification:

- `wavebreak-core`: `go test ./...` passed in Linux Docker with `golang:1.25.7`.
- `wavebreak-core`: `go test -race ./...` passed in Linux Docker with `golang:1.25.7`.
- `wavebreak-core`: Docker image build passed for API, worker, CLI, and migrate binaries.
- `wavebreak-core`: migration `00002_product_core_completion.sql` applied successfully to live PostgreSQL; Goose schema version is `2`.
- `wavebreak-web`: Composer install passed in Linux Docker; `php artisan test` passed with 2 tests / 2 assertions.
- `wavebreak-admin`: Composer install passed in Linux Docker; `php artisan test` passed with 2 tests / 2 assertions.
- `wavebreak-infrastructure`: default `docker compose up -d` is running PostgreSQL, Redis, RabbitMQ, Core API, worker, Web, Admin, Prometheus, Grafana, Loki, Tempo, OTel Collector, Alertmanager, node-exporter, cAdvisor, and exporters.
- Web smoke passed for `/`, `/pricing`, `/access`, `/login`, `/register`, `/dashboard`, `/dashboard/subscription`, `/dashboard/access`, `/dashboard/nodes`, `/dashboard/devices`.
- Admin smoke passed for `/dashboard`, `/nodes`, `/plans`, `/enroll`, `/users`, `/subscriptions`, `/grants`, `/devices`, `/traffic`, `/audit`.
- Mobile/Desktop API smoke passed against live Docker Core:
  register, refresh, plan list, subscription activation, device creation, location list, device-bound access grant creation, `GET /v1/client/bootstrap`, `GET /v1/access/grants/{grantID}/config`, and grant revoke.
- `wavebreak-web/phpunit.xml` and `wavebreak-admin/phpunit.xml` now define testing `APP_KEY`, so Laravel Feature tests boot without relying on local `.env`.

Product/Core E2E scenario passed:

- Core readiness.
- Admin login and RBAC.
- Node enrollment token issuance.
- Mock node enrollment with node API token.
- User registration.
- Subscription activation with plan limit snapshots.
- Client overview.
- Device creation through Core limit path.
- Telegram account link token plus bot service identify/link flow.
- Access grant creation and desired-state publication.
- Node desired-state fetch and ACK.
- Node monotonic usage report and subscription usage aggregate.
- Grant revoke and second desired-state ACK.
- Admin dashboard/users/plans/subscriptions/devices/traffic/audit/grants reads.

Pass 1 tests added:

- `wavebreak-core/internal/security`: Argon2id hash/verify, legacy bcrypt verification, token generation/hash tests.
- `wavebreak-core/internal/config`: production default secret validation tests.
- `wavebreak-core/internal/store`: migration contract test for RBAC, refresh rotation, node token, and desired-state columns.
- `wavebreak-node/internal/agent`: enroll, heartbeat, desired-state fetch, and ACK loop test.

Admin user management (2026-09-27):

- `wavebreak-core`: `go vet ./...` and `go test ./...` pass (accounts use-case tests with in-memory ports, RBAC/error-shape tests, OpenAPI contract test that checks every emitted JSON field is documented).
- `wavebreak-core`: DB E2E `TestAdminAccountManagementE2E` passes on a fresh PostgreSQL 17 (all 4 migrations from zero): plans list, RBAC (support reads, cannot issue; user forbidden), issue -> subscription/credential/URL, duplicate -> 409 (admin and legacy purchase), node usage report -> traffic, device registration -> devices 1/3 bound to the subscription, reset token hashed-only / one-time / login with new password, audit with request ids and no secrets. Run: `WAVEBREAK_TEST_DATABASE_URL=postgres://... go test ./internal/httpapi -run E2E`.
- Migration `00004` dedupe verified on data with duplicate live subscriptions: only the one with traffic survived; the unique index rejects a new duplicate.
- `wavebreak-admin`: `php artisan test` 26/26 (101 assertions) in `composer:2` (PHP 8.5); 10 new feature tests for the user modal with Core faked over HTTP.
- End-to-end on a local stack (Core API from source + PostgreSQL 17 + Admin via `php artisan serve`), driven in a browser: Users -> open user -> "No active subscription" -> plan select from Core -> issue -> modal refreshed in place (plan, active, dates, masked URL + copy, credential, traffic 0 B / 100 GB, devices 0 / 1) -> node `POST /v1/node/usage` -> traffic 10 GB / 90 GB left / 10% -> device registered -> Devices 1 / 1 -> password reset link created; audit rows `subscription_issued`, `access_created`, `password_reset_requested` with actor, target and request id.
