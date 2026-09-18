# WAVEBREAK — актуальный handoff по проекту

Дата обновления: 2026-09-16

Этот документ нужен следующему агенту или разработчику, чтобы быстро понять текущее состояние проекта и не откатить важные рабочие решения.

## Коротко о состоянии

WAVEBREAK — это единая платформа доступа/VPN с отдельными частями:

- `wavebreak-core` — Go Core API и worker. Это единственный владелец бизнес-логики, PostgreSQL, подписок, устройств, access grants, node desired-state и API для приложений.
- `wavebreak-node` — Go node-agent, который получает desired-state из Core и применяет runtime-конфиги на VPN-ноде.
- `wavebreak-web` — Laravel публичный сайт и личный кабинет пользователя. Работает только через Core API.
- `wavebreak-admin` — Laravel админка. Работает только через Core API.
- `wavebreak-infrastructure` — Docker Compose, pilot/staging/prod окружение, мониторинг и инфраструктурные шаблоны.
- `docs` — документация для API, деплоя, мобильного/десктопного разработчика и VPN-контракта.

Репозиторий:

```text
git@github.com:defloyder/wavebrake_project.git
```

Текущая основная ветка:

```text
main
```

Отдельная ветка для dev-среды:

```text
dev
```

## Важные правила

- Мобильное и десктопное приложения общаются только с `wavebreak-core`.
- Laravel Web/Admin не должны напрямую менять PostgreSQL-таблицы Core.
- `wavebreak-node` не должен сам придумывать подписки, пользователей или grants. Он только применяет состояние, которое пришло из Core.
- Не возвращать проект к старому варианту "один VLESS REALITY и все". Текущая рабочая линия пилота — Direct VLESS over WS/TLS + Hysteria2.
- Не публиковать обратно XHTTP как основной транспорт: ранее он ломал живые сессии Telegram.
- Не ломать `network_mode: host` для Xray/Hysteria в pilot compose без отдельной проверки. Это было сделано из-за проблем с Docker bridge, TCP/QUIC и Telegram.
- Секреты, приватные ключи, реальные grant-ссылки и пароли не класть в markdown и публичные логи.

## Текущий VPN runtime

На пилотной ноде сейчас используется мульти-транспортная схема. В коде поддерживается несколько транспортов, но в рабочей публикации для клиента сейчас основной акцент на двух подключениях:

1. Direct VLESS over WebSocket + TLS
   - домен: `direct.wavebreak.com.tr`
   - порт: `443`
   - путь: `/wvb-dt`
   - TLS/SNI: `direct.wavebreak.com.tr`
   - назначение: стабильный прямой TCP/TLS транспорт без Cloudflare/CDN-прослойки.

2. Hysteria2 over QUIC
   - endpoint: `91.149.241.52:443`
   - SNI: `hy2.wavebreak.com.tr`
   - ALPN: `h3`
   - назначение: быстрый UDP/QUIC транспорт с реальным сертификатом.

В коде также остаются реализации/заготовки для:

- VLESS REALITY;
- VLESS CDN WS;
- VLESS CDN XHTTP;
- Trojan CDN WS;
- VLESS CDN gRPC;
- Shadowsocks.

Эти варианты нельзя удалять без отдельного решения, но и нельзя хаотично включать в клиентскую подписку, если они не проверены на Telegram/браузинг/мобильных сетях.

## Где формируется конфиг для приложений

Основная точка для приложений:

```http
GET /v1/access/grants/{grantID}/config
```

Ожидаемая логика клиента:

1. Пользователь регистрируется или входит.
2. Приложение сохраняет `access_token` и `refresh_token`.
3. Приложение вызывает `GET /v1/client/bootstrap`.
4. Пользователь выбирает тариф/локацию.
5. Приложение регистрирует устройство через `POST /v1/me/devices`.
6. Приложение создает grant через `POST /v1/access/grants`.
7. Приложение забирает конфиг через `GET /v1/access/grants/{grantID}/config`.
8. Если node-agent еще не подтвердил применение, приложение повторяет запрос через несколько секунд.
9. При отключении доступа приложение вызывает revoke endpoint.

Документы для разработчика мобильного/десктопного приложения:

```text
MOBILE_DESKTOP_DEVELOPER_HANDOFF.md
docs/mobile-desktop-api.md
docs/mobile-desktop-pilot-testing.md
docs/vpn-config-contract.md
wavebreak-core/api/openapi.yaml
```

## Пилотный сервер

Пилотная машина:

```text
91.149.241.52
```

Проект на сервере развернут отдельно от других проектов. Рабочий путь, который использовался в текущем pilot deployment:

```text
/home/wavebreakdeploy/wavebreak-pilot/current
```

Core API для тестирования приложений:

```text
http://91.149.241.52:18080
```

Перед production нужно закрыть прямой HTTP и выдать нормальный HTTPS endpoint, например:

```text
https://api.<domain>
```

## Инфраструктура pilot

### Регламентные операции на живом pilot

- PostgreSQL должен резервироваться ежедневно скриптом `wavebreak-infrastructure/scripts/backup-pilot-postgres.sh`. Скрипт делает custom-format dump, сжимает его, проверяет gzip до атомарного переименования и хранит копии 14 дней.
- Старый Docker build-cache очищается скриптом `wavebreak-infrastructure/scripts/maintain-pilot-docker.sh`. Скрипт не удаляет работающие контейнеры, образы или volumes и возвращает ошибку, если после очистки корневой диск всё ещё заполнен на 80% или больше.
- На сервере журналы cron для этих задач находятся в `/home/wavebreakdeploy/wavebreak-pilot/shared/logs/`.
- 18 сентября 2026 года build-cache разросся до 15,4 ГБ и заполнил диск на 92%. После безопасной очистки занятость снизилась до 38%; это причина держать обслуживание включённым постоянно.

Ключевые сервисы:

- PostgreSQL;
- Redis;
- RabbitMQ;
- Core API;
- Core worker;
- Laravel Web;
- Laravel Admin;
- node-agent;
- Xray;
- Hysteria2 sidecar;
- monitoring stack.

Pilot compose использует отдельные настройки для Xray/Hysteria. Важные особенности:

- Xray и Hysteria работают через host networking.
- node-agent генерирует Xray config и Hysteria config.
- node-agent перезапускает runtime-контейнеры после изменения desired-state.
- Hysteria получает per-grant auth через username/password на основе grant id.
- Legacy VLESS REALITY можно выключить через `WAVEBREAK_VLESS_PORT=0`; в этом случае Xray/node не должны занимать лишний TCP-порт под непубликуемый транспорт.
- Для стабильной работы Hysteria2/QUIC на VPS нужен host-level sysctl tuning из `wavebreak-infrastructure/sysctl/99-wavebreak-vpn.conf`.
- RabbitMQ healthcheck в pilot compose специально сделан редким, чтобы Erlang diagnostics не создавал лишние CPU-всплески на маленькой VPS.

## Web/Admin состояние

Коммит коллеги по ребрендингу web/admin уже влит в текущую `main`.

Связанные коммиты:

```text
a858ba2 Rebrand web and admin to match the mobile/desktop app design system
f5f9ae1 Merge origin/main (web/admin rebrand) with XHTTP CDN transport work
```

Эти изменения затрагивали:

- `wavebreak-admin/public/css/admin.css`
- `wavebreak-admin/public/css/auth.css`
- `wavebreak-admin/public/css/wavebreak-overrides.css`
- `wavebreak-admin/resources/views/layout.blade.php`
- `wavebreak-web/public/css/wavebreak-site.css`
- `wavebreak-web/resources/views/layout.blade.php`

Не откатывать их без отдельной причины.

## Проверки, которые уже важны для проекта

Перед серьезным merge/deploy желательно прогонять:

```bash
cd wavebreak-core
go test ./...
go test -race ./...
```

```bash
cd wavebreak-node
go test ./...
go test -race ./...
```

Для Laravel:

```bash
cd wavebreak-web
composer install
php artisan test
```

```bash
cd wavebreak-admin
composer install
php artisan test
```

Для pilot VPN важно проверять не только импорт подписки, но и реальный трафик:

- Telegram;
- обычный браузинг;
- мобильная сеть;
- Wi-Fi;
- переподключение после сна/смены сети;
- revoke доступа;
- повторную выдачу grant.

## Что не считать мусором

Не удалять проектные изображения:

- `wavebreak-web/public/images/*`
- `wavebreak-admin/public/images/*`
- `app/public/images/*`
- `logo_wb.png`, если он используется как исходный брендовый файл.

Удаляемыми артефактами считаются корневые PNG-скриншоты вида:

```text
wavebreak-web-*.png
wavebreak-admin-*.png
```

Они были рабочими скриншотами промежуточного дизайна и не нужны в репозитории.

## Ближайшие задачи

1. Держать `main` чистой и рабочей.
2. Использовать `dev` для dev-среды и интеграционных изменений.
3. Довести приложение до стабильного потребления API-конфига без ручных ссылок.
4. Проверить, что мобильный/десктопный клиент корректно показывает локацию Netherlands/Amsterdam и берет transports из Core.
5. После каждого изменения VPN runtime проверять живой Telegram, а не только успешный импорт ссылки.
