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

Admin UI overhaul (2026-09-27):

- Every table row that shows a user opens the user card; per-row action buttons are gone. All per-user actions live in the card: edit profile/role/status/password, password reset link, block/unblock, delete (superadmin, not self), issue subscription, issue missing access, edit subscription (plan, status, end date, traffic limit, devices), reset traffic, reissue link, cancel subscription, revoke device, revoke key; each answers with the card re-rendered from Core.
- Tables show emails, plan names, node codes and local day-first dates (Europe/Istanbul, `WAVEBREAK_DISPLAY_TIMEZONE`) instead of Core ids / raw ISO; traffic in binary units labelled ГБ; statuses and roles in Russian; search + segmented filters; tables turn into stacked cards when narrow (container query), modals become bottom sheets on phones. Plan editor takes price in currency units and traffic in ГБ.
- Structure: `AdminPageBuilder` loads only the Core datasets a section shows; presentation rows in `app/View/Admin/Rows`, `StatusBadge`, `AdminDirectory`, `DisplayDate`; sections in `resources/views/admin/sections`, Blade components in `components/adm`, JS in `admin-ui.js` / `admin-user-card.js`. Old per-row admin routes were removed.
- Core: `POST /v1/admin/users/{id}/access` (issue missing key, idempotent); extending a subscription now moves its grants' expiry (previously nodes would drop the key at the old date).
- Tests: `wavebreak-core` `go test ./...` + DB E2E pass (new steps: expiry sync, issue access idempotent/after revoke); `wavebreak-admin` 46/46 (249 assertions).
- Verified in the in-app browser on a local stack (desktop ~800px and 375px phone): users -> card, subscription without key -> "Выдать доступ" -> link issued; subscription edit (devices 2, end date) -> card refreshed; all sections render. Not verified in that browser: QR code (the QR library comes from jsDelivr and external hosts are unreachable there).

Bug 10 (2026-09-27):

- Core: `go test ./...` passes; new unit tests for the lifecycle service; new DB E2E `TestSubscriptionLifecycleE2E` (me/access -> 3 links on one credential; period over -> past_due, key expiry now, `/subscriptions/current` shows `grace_ends_at`, me/access 422; renewal keeps subscription id and credential, key served again, usage 0, second purchase 409; traffic exhausted -> past_due; grace passed -> expired, key revoked, older device revoked, newest kept without subscription, account still works; new purchase gets a new credential; 4 audit events).
- Mobile: `flutter analyze` clean, `flutter test` 43/43 (new `personal_access_test.dart`). PC: new tests pass; the one failing PC test (`connect with an active subscription reaches connected`) fails on the unchanged code too.
- Pilot read-only dry run: nothing would transition today (5 active subscriptions). The subscription holding the shared credential of old APKs ends 2026-10-16; it goes past_due that day unless extended.
- Not verified on a device yet: needs Core deployed to pilot first.
