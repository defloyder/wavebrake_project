# Отчёт об изменениях — 29.09–01.10.2026

Ветка: `app-main-sync` (всё запушено, последний коммит — см. `git log`). Отчёт для коллеги:
что менялось, где и зачем, что изменено на серверах вне git, как откатить.
Секреты (пароли, ключи, токены) здесь не приводятся — только имена переменных.
Как собирать и публиковать обновления и откаты — `docs/RELEASE-PROCESS.md`.

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

## 6а. 01.10 (вечер) — Windows cloak, проверки

- **Windows cloak** (`683137b` — коллега, ветка `wt-cloak-pc`; `3c9bfba` — доработка):
  `wavebreak-shared/cloak/cmd/cloak-client-proxy` (новый .exe рядом с приложением),
  `wavebreak-pc/lib/services/vpn/windows_vpn_adapter.dart`, `share_link.dart` (поля cloak),
  `windows/runner/CMakeLists.txt`. Доработка: IP сервера резолвится заранее и идёт мимо туннеля
  (`route.rules` → `direct`), иначе трафик прокси зацикливался бы в TUN; Windows сообщает Core
  `hysteria-cloak`. Конфиг проверен `sing-box check` (1.14.1). Сборка 1.0.8 (17), откат 1.0.7 (18) —
  **не опубликованы**, ждут проверки на ПК без другого VPN.
- **Core** (`498eabb`, не выкачено): вход отклоняется, если состояние почты не прочиталось (раньше —
  пропускался). Обхода подтверждения почты в базе не найдено: неподтверждённые аккаунты ни разу не
  входили.
- **Новые пользователи и Hysteria «authentication error 404»**: уже исправлено на сервере (агент
  пересоздан коллегой 01.10 ~09:55 UTC) — список пользователей Hysteria совпадает со всеми
  активными доступами TR.
- **Замечание коллеги про `hyclient.NewClient` в Android-мосте** не подтвердилось: в `app-main-sync`
  с 27.09 (`17ff4f0`) используется `NewReconnectableClient`.

## 6б. 01.10 ~15:20 — Hysteria на TR выдавалась с неверным портом

- Коллега около 10:19 UTC перенёс Hysteria за cloak-relay на внутренний порт 44100 и для этого
  дописал в `.env.pilot` вторую строку `WAVEBREAK_HYSTERIA_PORT=44100`. Эта же переменная задаёт
  порт **в ссылке** Core → все клиенты (Android 1.2.4, Windows 1.0.8) с этого момента шли на
  `45.15.41.3:44100` мимо relay, а Kolan снаружи пропускает только UDP 443 — Hysteria не работала.
- Исправлено на сервере: порты разделены — `WAVEBREAK_HYSTERIA_PORT=443` (публичный, в ссылке),
  новая `WAVEBREAK_HYSTERIA_LISTEN_PORT=44100` (где слушает Hysteria за relay, читает агент);
  compose: `WAVEBREAK_HYSTERIA_LISTEN_PORT: ${WAVEBREAK_HYSTERIA_LISTEN_PORT:-${WAVEBREAK_HYSTERIA_PORT:-0}}`.
  Пересоздан только `wavebreak-api` (без пересборки), агент и Hysteria не трогались.
  Копии: `.env.pilot.bak-before-hyport-*`, `docker-compose.pilot.yml.bak-before-hyport-*`.
- **Правки коллеги в Core, сделанные прямо на сервере (не были в git), перенесены в репозиторий**:
  `internal/httpapi/product.go` (публичная `/v1/sub` без Hysteria — сторонним клиентам она без cloak
  бесполезна; зеркала в конфиге приложения; «total» для шкалы трафика в Happ; ссылка подписки для
  бота), `internal/store/product.go` (`ActiveGrantID`, `Mirrors`). Без этого следующая выкатка Core
  из git затёрла бы их. Образ Core на сервере собран коллегой 01.10 13:07 MSK из этих исходников.

## 6в. 01.10 ~16:40 — Android 1.2.4.2 (47) опубликована

- Вылет на Android 10: `MainActivity.isSystemVpnActive` вызывал `NetworkCapabilities.getOwnerUid()` (API 30) при проверке `>= Q` → `NoSuchMethodError` сразу после подъёма VPN. Причина найдена по отчёту MIUI (`*#*#284#*#*`, `am_crash`). Исправлено (`>= R`), заодно `Notification.Builder(context, channel)` (API 26) при minSdk 24. Lint: NewApi — 0.
- Опубликовано на зеркале и сайте (файлы на сайт перенесены с зеркала сервер-сервер, суммы сверены), откат 1.2.4.1 (48). Windows 1.0.8 не публиковалась — ждёт подтверждения Hysteria на ПК.
- Также на ПК: выбранная локация держит устаревшую ссылку, если ссылка на сервере изменилась (сегодня — порт 44100 → 443); обход — заново выбрать локацию в списке. Исправление — открытый вопрос.

## 6г. 01.10 вечер — Android 1.2.4.3 (49) и проверка совместимости

- Вылет SystemUI на Android 10 при открытии шторки: `res/drawable/notif_bg.xml` — угол градиента 115 → 135 (Android 10 бросает исключение на углах, не кратных 45, при отрисовке уведомления → падает SystemUI → экран блокировки).
- Аудит старых устройств (minSdk 24): lint NewApi/InlinedApi — 0; `MainActivity.startSettingsScreen` открывает системные экраны с запасным вариантом вместо вылета (`ActivityNotFoundException` на урезанных прошивках); `UpdateInstaller` на Android 7 ведёт в `ACTION_SECURITY_SETTINGS`.
- Android 7.0 не знает корневой сертификат ISRG Root X1 (Let's Encrypt) — до Core и зеркала такие телефоны не достучатся. Решение владельца: минимальная версия — 7.1 (`minSdk = 25` в `android/app/build.gradle.kts`; 7.1.0 и 7.1.1 делят API 25, корень появился в 7.1.1).
- Windows: установщик требует Windows 10+ (`MinVersion=10.0`); 64-бит уже требовался.
- Сборки 1.2.4.3 (49) и откат 1.2.4.2 (50) собраны с 4 обязательными dart-define, не опубликованы.

## 7. Открытые вопросы
1. Xray держит клиентов Hysteria в глобальном кеше процесса (переживает перезапуск движка) — вероятная причина «после смены сети Hysteria не работает до перезапуска приложения». Не исправлено.
2. Для cloak-Hysteria smart routing (российские сайты напрямую) не применяется — весь трафик через туннель.
3. На Windows cloak нет — турецкой Hysteria в Windows-приложении не будет, пока не появится поддержка.
4. `HysteriaCloak` — флаг узла; если появится второй Hysteria-узел без relay, флаг ему не ставить.
5. REALITY на мобильных сетях (Yota) режется по SNI — оставлен для Wi‑Fi, «Нет трафика» предложит другой протокол.
6. Зависание переключения Hysteria → Direct видели один раз сразу после обновления; в 1.2.4.1 есть трассировка — ждём лог, если повторится.
7. Android 7.0 больше не поддерживается (minSdk 25) — на сайте стоит указать «Android 7.1 и новее».
8. ПК: выбранная локация держит устаревшую ссылку при смене ссылки на сервере.

## 6д. 01.10 18:15 — Windows 1.0.8: Hysteria через cloak подтверждена

- На ПК владельца с выключенным Happ турецкая Hysteria2 работает через cloak-client-proxy (лог: `wrapping to 45.15.41.3:443`, 54 соединения, 0 таймаутов).
- Причина прежних неудач — Happ: его туннель не пропускает UDP до сервера (tcpdump на TR во время пробы с ПК — ни одного пакета). Цепочка sing-box → cloak-client-proxy → cloak-relay → Hysteria проверена локально на 127.0.0.1 — работает.
- Осталось: пересобрать 1.0.8 с `MinVersion=10.0` (номера 19 и откат 20), опубликовать после «публикуй».

## 6е. 01.10 ~18:50 — опубликованы Android 1.2.4.3 (49) и Windows 1.0.8 (19)

- Откаты: Android 1.2.4.2 (50, из af3d00a), Windows 1.0.7 (20, из e4b06f2).
- Зеркало `dl.wavebreak.com.tr` и сайт (хост + контейнер) — файлы, затем манифесты; старые файлы сохранены как `*.bak-before-<дата-время>`. Все 12 ссылок из манифестов отвечают 200, размеры совпадают.
- Android 1.2.4.3: фикс падения шторки на Android 10, защищённые экраны настроек, minSdk 25 (Android 7.1+). Фикс шторки — не проверено на устройстве (ждём подтверждения с Redmi Note 9 Pro).
- Windows 1.0.8: турецкая Hysteria2 через cloak (подтверждено на ПК владельца без Happ), установщик требует Windows 10+.
- Временные папки на серверах (`/var/www/dl/downloads/incoming-win-1.0.8` с копиями манифестов, `/root/staging/rel-1.2.4.3`, `/root/staging/win-1.0.8`) пока не удалены.

## 6ж. 01.10 ~20:30 — опубликована Windows 1.0.9 (21), откат 1.0.8 (22)

- Отключение через ~8 с на любом протоколе (отзыв коллеги и его друга): проверка «чужого VPN» срабатывала на постоянно стоящие адаптеры (Radmin VPN, OpenVPN, TAP/wintun). Теперь учитываются только появившиеся после подключения.
- При подключении закрываются другие VPN/прокси-клиенты (Happ и служба HappService, v2rayN, Hiddify, NekoBox, Clash и др.), системный прокси на 127.0.0.1 снимается. WireGuard, корпоративные VPN, Radmin/Hamachi/ZeroTier/Tailscale не трогаются.
- Иконка в трее с состоянием и меню (подключить/отключить, локации, открыть, выйти) — Win32 в раннере, без новых зависимостей.
- Версию 1.0.8.1 выпустить нельзя: четырёхзначное имя Flutter на Windows превращает в 1.0.0 без номера сборки (бесконечное предложение обновиться) — выпущена как 1.0.9; правило записано в RELEASE-PROCESS.
- Не проверено на устройстве (закрытие Happ, меню трея).

## 6з. 01.10 ~21:30 — опубликованы Android 1.2.4.4 (51) и Windows 1.0.10 (23)

- Откаты: Android 1.2.4.3 (52, из 022d623), Windows 1.0.9 (24, из 3c7b83e). Все 12 ссылок манифестов — 200, размеры совпадают; подпись APK та же.
- В выпуске: выбранная локация находит свою новую ссылку, если ссылка изменилась на сервере (Android и Windows); в меню трея Windows нет пункта «АВТО».
- Открыто: выкатка фикса входа в Core (498eabb) — ждёт «ок»; временные папки на серверах (incoming-*, /root/staging/*) — не нужны, ждут «ок» на удаление; обычная (не cloak) Hysteria на Android через Xray после смены сети.
