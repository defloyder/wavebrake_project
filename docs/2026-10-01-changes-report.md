# Отчёт об изменениях — 29.09–01.10.2026

Ветка: `app-main-sync` (всё запушено, последний коммит — см. `git log`). Отчёт для коллеги:
что менялось, где и зачем, что изменено на серверах вне git, как откатить.
Секреты (пароли, ключи, токены) здесь не приводятся — только имена переменных.

---

## 1. Приложения (Android `wavebreak-mobile`, Windows `wavebreak-pc`)

| Коммит | Что | Где | Зачем |
|---|---|---|---|
| `8d85ca2`, `ebc996e` | H1: короткое пропадание **той же** сети (< 3 с) не перезапускает VPN; новая сеть или долгий обрыв — перезапуск как раньше. Kotlin-тест (JUnit, только тесты) | `android/.../WaveEngineVpnService.kt`, новый `NetworkChangePolicy.kt`, `android/app/build.gradle.kts`, `android/app/src/test/...` | В логах «native engine reconnecting: network changed» рвал рабочие соединения на ровном месте |
| `468935d` | H1 для Windows: полное пропадание сети больше не сбрасывает «базовую» сеть, возврат той же сети за < 3 с не перезапускает sing-box | `wavebreak-pc/lib/services/vpn/windows_vpn_adapter.dart`, новый `network_change_policy.dart` + тест | То же на ПК |
| `b073d84`, `061ca91`, `797f92c`, `912aa2f`, `c0deb17` | H2: состояние **«Нет трафика»** и кнопка **«Попробовать другой протокол»** (только по нажатию, только та же страна). Проверка через туннель; мгновенный отказ (< 1,5 с) считается «движок не готов», а не промахом; ~11 с до надписи | `lib/services/vpn/connection_manager.dart`, новые `protocol_fallback.dart`, `traffic_check.dart`, `lib/features/home/home_screen.dart`, `lib/core/i18n/app_strings.dart` (7 языков) + тесты | Приложение показывало «Подключено», когда данные не шли (REALITY на мобильных сетях) |
| `797f92c` | Выход из аккаунта отключает VPN (с отзывом доступа, если сессия жива; локально — если Core уже завершил сессию) | `lib/core/auth/session_controller.dart`, `connection_manager.dart` (`stopForSignOut`) + тест | После выхода VPN продолжал работать; после входа подхватывалось старое время |
| `cfcd458`, `912aa2f` | Главный экран и список локаций не прыгают при смене локации: данные на время перезагрузки не пропадают (`valueOrNull` вместо `asData`), пустая строка статуса держит высоту | `home_screen.dart`, `locations_screen.dart`, `subscription_screen.dart`, `connection_manager.dart` | Визуальные прыжки; заодно проверка трафика и smart routing иногда не узнавали «свою» локацию |
| `a761b89` | В логе проверки трафика — страна и сеть: `hysteria2 (TR, mobile YOTA): 338 ms` | новый `android/.../NetworkLabel.kt`, `MainActivity.kt`, `connection_manager.dart` | Понимать, какой протокол работает у какого оператора |
| `65a9f86` | На откатной сборке экран обновлений пишет «установлена откатная версия», а не «у вас последняя версия» | `lib/services/update/update_service.dart`, `lib/features/settings/updates_screen.dart` (оба приложения) | Вводило в заблуждение после отката |
| `9e2bf55` | «О приложении» → политика и соглашение открывают страницы сайта `wavebreak.com.tr` (`/privacy`, `/terms`; `/tr`, `/en` по языку). Строка почты в аккаунте: длинный адрес обрезается, «Подтвердить» под ним | `lib/features/settings/about_screen.dart`, `account_screen.dart`, `core_api/models.dart`, `app_strings.dart` (оба приложения) + тест | Старые ссылки вели на мёртвый `wavebreak.app`; вёрстка ехала |
| `cbe154d`, `7f359c7` | **cloak** (автор — коллега, из его ветки `wt-cloak`): маскировка формы трафика Hysteria2 | `wavebreak-shared/cloak/*`, `native/hysteria_bridge/bridge.go`, `go.mod`, `docs/2026-09-30-hysteria-investigation-and-cloak.md` | Обрывы Hysteria на мобильных сетях (Альфа) |
| `c9cfc6e` | Ссылки `hysteria2://…&cloak=1` идут через клиент apernet в мосте (там cloak), остальные Hysteria2 — через Xray, как раньше | `lib/services/vpn/native_vpn_adapter.dart` (`usesCloak`) + тест | Без этого cloak молча не включался: Hysteria2 в приложении идёт через Xray, который `cloak=1` игнорирует |
| `4336bf1` | Приложение сообщает Core `hysteria-cloak` (Android) | `lib/core/api/api_client.dart` | Core отдаёт cloak-ссылку только тем, кто её умеет |
| `d62279a` | Шаги VPN-движка в диагностическом логе (`engine: …`) — поведение не меняется | `WaveEngineVpnService.kt` (`trace`), `native_vpn_adapter.dart` | Один раз после обновления переключение Hysteria → Direct зависло; повторить не удалось. Следующий раз лог покажет шаг |

Нативная библиотека моста (`android/app/libs/hysteria_bridge.aar`, в git не хранится) пересобрана с cloak
(`native/hysteria_bridge/build_aar.sh`). Сборки 1.2.4+ содержат её, откат 1.2.3 — старую.

## 2. Core (`wavebreak-core`)

| Коммит | Что | Где | Зачем |
|---|---|---|---|
| `e04ded5` | При повышении лимита устройств тарифа он поднимается у действующих подписок этого тарифа (никогда не понижается, индивидуальный override не трогается) | `internal/store/product.go` (`UpdatePlan`) + интеграционный тест | У коллеги тариф на 10 устройств, а подписка помнила 1 |
| `6e76397` | Миграция `00007` (массовое поднятие лимитов) **удалена** по решению владельца — существующие лимиты поднимаются вручную | — | — |
| `82a6254` | `HysteriaCloak` (env `WAVEBREAK_HYSTERIA_CLOAK`, по узлу): в ссылке `cloak=1`; `/v1/sub` отдаёт её; `/v1/me/access` — только приложениям с `hysteria-cloak`. Зеркала (Москва) флаг **не наследуют** | `internal/config/config.go`, `internal/httpapi/product.go`, `me_access.go` + тест | Перед Hysteria на TR стоит cloak-relay: без cloak клиент не подключится |

## 3. Инфраструктура в репозитории

| Коммит | Что | Где |
|---|---|---|
| `04476a6` | compose передаёт `WAVEBREAK_HYSTERIA_CLOAK` в Core (как на сервере) | `wavebreak-infrastructure/docker-compose.pilot.yml` |
| `3bc5c98` → `23049fa` | Эксперимент с salamander-Hysteria в Москве добавлен и **полностью откатан** | `wavebreak-infrastructure/ru-msk-01.public.json` (в итоге без изменений) |

## 4. Изменения на серверах, которых нет в git

### TR-PILOT-01 (45.15.41.3)
- `.env.pilot` (`/home/wavebreakdeploy/wavebreak-pilot/current/wavebreak-infrastructure/`):
  - 29.09: `WAVEBREAK_HYSTERIA_PINNED_SNI` очищен — вариант 1.2.2 с «нейтральным SNI» не работал (сервер Hysteria по умолчанию отклоняет SNI вне сертификата, `sniGuard`).
  - 01.10: `WAVEBREAK_HYSTERIA_HOST` снова заполнен (был пуст — Hysteria пропала бы из подписки при следующей стандартной выкатке; работающий Core был пересоздан из `/root/backups/wavebreak-api-recreate2.env`), `WAVEBREAK_HYSTERIA_OBFS_PASSWORD` перенесён из работающего контейнера, добавлен `WAVEBREAK_HYSTERIA_CLOAK=true`.
  - Копии: `.env.pilot.bak-before-cloak-*`, `docker-compose.pilot.yml.bak-before-cloak-*`.
- Core пересобран и перезапущен из `app-main-sync` (только `wavebreak-api`). До выкатки сверено: на сервере отличался лишь `internal/store/product.go` (правка лимита, раньше не выкачена). Копия прежних исходников: `/root/backups/wavebreak-core-before-cloak-*.tgz`.
- Загрузки (зеркало `dl.wavebreak.com.tr` `/var/www/dl/downloads` и сайт — хост + контейнер `wavebreak_pilot-wavebreak-web-1`): опубликованы релизы из раздела 6. Прежние манифесты и файлы — `*.bak-before-<версия>-*`.

### RU-MSK-01 (135.106.227.90)
- Salamander-Hysteria (контейнер, iptables-перенаправление портов, env агента, `public_config` в Core) добавлена 30.09 и **полностью удалена** в тот же вечер: ломала Hysteria в Android-приложении до перезапуска. Узел в исходном состоянии; копии env — `ru-node.env.bak-before-obfs-*`.

### База данных
- Схема не менялась (миграция 00007 отозвана). `nodes.public_config` у RU-MSK-01: поля Obfs добавлены и удалены (итог без изменений).

## 5. Найдено на серверах, сделано не мной (для сверки)
- **cloak-relay** на TR занимает UDP 443, Hysteria перенесена на `127.0.0.1:44100` — обычная Hysteria без cloak на TR больше не работает (старые версии и Windows её не видят — см. п. 2).
- Агент **RU-MSK-01 остановлен вручную** 30.09 около 08:12 UTC — московских локаций в подписке нет.
- Core был пересоздан с отдельным env-файлом (`/root/backups/wavebreak-api-recreate2.env`); в `.env.pilot` Hysteria была снята.
- Контейнер `wavebreak-pilot-hysteria-obfs` на TR (не трогал).
- При старте Core предупреждение RabbitMQ «username or password not allowed» — было и до выкатки (тот же адрес у worker).

## 6. Релизы

| Платформа | Версия (сборка) | Откат (сборка) | Дата |
|---|---|---|---|
| Android | 1.2.3 (39) | 1.2.1 (40) | 30.09 |
| Windows | 1.0.7 (15) | 1.0.5 (16) | 30.09 |
| Android | 1.2.4 (42) — cloak | 1.2.3 (43) | 01.10 |
| Android | 1.2.4.1 (45) — трассировка движка | 1.2.4 (46) | 01.10 |

Не публиковались (заняты): 38, 41, 44 — тестовые сборки. Следующая Android ≥ 47, Windows ≥ 17.
Перед сборкой: 4 обязательных `--dart-define` (см. `docs` / CHANGELOG), подпись — боевой ключ.

## 7. Открытые вопросы
1. Xray держит клиентов Hysteria в глобальном кеше процесса (переживает перезапуск движка) — вероятная причина «после смены сети Hysteria не работает до перезапуска приложения». Не исправлено.
2. Для cloak-Hysteria smart routing (российские сайты напрямую) не применяется — весь трафик через туннель.
3. На Windows cloak нет — турецкой Hysteria в Windows-приложении не будет, пока не появится поддержка.
4. `HysteriaCloak` — флаг узла; если появится второй Hysteria-узел без relay, флаг ему не ставить.
5. REALITY на мобильных сетях (Yota) режется по SNI — оставлен для Wi‑Fi, «Нет трафика» предложит другой протокол.
6. Зависание переключения Hysteria → Direct видели один раз сразу после обновления; в 1.2.4.1 есть трассировка — ждём лог, если повторится.
