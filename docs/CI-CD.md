# CI/CD WAVEBREAK

Решение владельца 14.10.2026: работать по стандарту CI/CD. Каждое изменение проходит проверку
в GitHub Actions. Выпуск и выкладка идут из пайплайна, а не с ноутбука вручную.

## CI — уже работает (`.github/workflows/wavebreak-ci.yml`, на каждый push и PR)

| Задача | Что проверяет |
|---|---|
| `core`, `node` | `go test`, `-race`, `govulncheck`, `golangci-lint`, сборка |
| `laravel` | сайт и админка: `php artisan test`, `pint`, `composer audit` |
| `docker` | сборка образов Core и ноды, проверка compose |
| `flutter` (с 14.10) | Android и Windows: `flutter analyze`, `flutter test` |
| `links` (с 14.10) | общий пакет ссылок: `dart test` |
| `launcher` (с 14.10) | тесты, сборка `WAVEBREAK-Launcher.exe` (артефакт задачи) |
| `bridge` (с 14.10) | нативный мост Android: `go vet`, тест закрытия зависших соединений |

**Правило:** выпуск и выкладка — только с зелёного CI на `app-main-sync`. Красный CI → сначала
исправить.

## CD — что сделать (нужны секреты, их добавляет владелец)

Окружение GitHub `production` с ручным подтверждением владельцем (Settings → Environments →
Required reviewers). Без его кнопки ни одна выкладка не идёт.

| Пайплайн | Запуск | Шаги | Секреты |
|---|---|---|---|
| `deploy-node` | вручную, после зелёного CI | сборка образа ноды → на сервер по SSH → `up -d --no-deps wavebreak-node` → проверка: агент применил состояние, Xray и Hysteria живы | `DEPLOY_SSH_KEY` (отдельный ключ только для выкладки), `DEPLOY_HOST` |
| `deploy-web` | вручную | то же для сайта: проверка во временном контейнере → подмена | те же |
| `release-android` | тег `android/*` | сборка с 4 боевыми `--dart-define`, подпись, загрузка на зеркало и сайт, манифест последним | `ANDROID_KEYSTORE` (base64), `ANDROID_KEY_PASSWORD`, `ANDROID_STORE_PASSWORD` + SSH |
| `release-windows` | тег `windows/*` (раннер Windows) | сборка Flutter, Inno Setup, загрузка, манифест | SSH |
| `release-tv` | тег `tv/*` | `tv.ps1`-эквивалент + `tv-publish.sh` | ключ Android + SSH |

**Что изменится в работе:**
- **Выкладка ноды и сайта** — запуск пайплайна (кнопка Run workflow), а не копирование файлов на сервер.
- **Выпуск приложений** — тег, `release.sh` готовит номера и CHANGELOG, а собирает и выкладывает пайплайн. Проверка на телефоне остаётся: файлы сначала идут во `incoming-…`.
- **Ключ подписи Android** хранится в секретах GitHub, а не на ноутбуке. Это решение владельца: доступ к нему получат все администраторы репозитория.

## Порядок

1. ~~Владелец создаёт окружение `production` и секреты~~ — сделано 14.10: ревьюеры владелец и коллега, self-review запрещён, обход для админов выключен, только ветка `app-main-sync`; `DEPLOY_SSH_KEY` (ключ `wavebreak-deploy@github-actions` у root), `DEPLOY_HOST`.
2. **Готово (14.10):** `.github/workflows/deploy.yml` — Actions → Deploy → Run workflow → node или web. Тесты компонента → подтверждение второго человека → `tools/deploy/remote.sh` на сервере: копия файлов и образа, сборка, для сайта проверка во временном контейнере, замена, проверка, при сбое откат. Журнал выкладок — `/root/deploy-log.txt`, копии — `/root/deploy-backups/`. Папка загрузок сайта в выкладку не входит (её ведёт `release.sh`). Ключ сервера закреплён в пайплайне.
3. Затем `release-*` — после решения по ключу подписи.
