# Сборка и публикация обновлений и откатов (Android, Windows)

Что делается по команде владельца «собери и выкати обновление» — по шагам, в том порядке,
в котором это реально выполняется. Секретов здесь нет: ключ подписи и пароли лежат только на
машине сборки и на серверах, в git их не кладём и в чат/логи не выводим.

Связанные документы: `docs/RELEASE-PROCESS.md` (как собирать и публиковать), `CHANGELOG.md` (что в каждой версии), `docs/2026-10-01-changes-report.md`
(отчёт об изменениях), `docs/pilot-vps-deployment.md` (сервер).

---

## 0. Правила (обязательно)

- Публикация пользователям — **только после явного «публикуй»** владельца.
- Ветка: работаем и пушим **только** в `origin/app-main-sync`. `main` не трогаем (его ведёт коллега).
- Каждое изменение — коммит + пуш, запись в `CHANGELOG.md`; правки на серверах — копией в репо
  (без секретов) и в отчёт `docs/`.
- Номер сборки (versionCode / build) **никогда не переиспользуется** — даже у тестовых сборок.
- Android-сборка для реального устройства — **только с 4 продакшн-`--dart-define`** (иначе
  приложение уходит в мок-режим: фейковые серверы, VPN не поднимается).
- Каждый релиз публикуется **вместе с откатом** на предыдущую рабочую версию.
- Сначала проверка (тесты, при возможности — телефон через adb), потом публикация.
  Опыт 1.2.2: непроверенная на устройстве сборка сломала Hysteria у всех.

## 1. Нумерация

Android: `versionName` (1.2.4, 1.2.4.1 …) + `versionCode` (целое, растёт всегда).
Windows: версия (1.0.7) + build number (растёт всегда).

- Релиз N и откат N+1: откат — это **предыдущая версия, пересобранная с номером выше** релиза
  (Android не ставит меньший versionCode поверх большего; на Windows откат со старым номером сразу
  предлагал бы обновиться обратно). Каждый релиз с откатом тратит **два** номера.
- **Windows: версия только из трёх чисел** (`1.0.9`, не `1.0.8.1`): Flutter на Windows молча ставит в exe `1.0.0` без номера сборки, приложение видит сборку 0 и бесконечно предлагает обновиться. Проверять: свойства exe → `X.Y.Z+<build>`.
- «Подверсия» (патч): имя `x.y.z.N`, собирается с `--build-name=x.y.z.N`, в `pubspec.yaml`
  при этом стоит `x.y.z+<код>`.
- Тестовые сборки (adb на телефон владельца, тест коллеге) тоже занимают номер.

Занято на 01.10.2026 (актуальный список — в конце `CHANGELOG.md`/отчёта; перед сборкой проверить
опубликованный `version.json`):
- Android: … 36 = 1.2.2, 37 = откат 1.2.1, 38 тест, 39 = 1.2.3, 40 = откат 1.2.1, 41 тест,
  42 = 1.2.4, 43 = откат 1.2.3, 44 тест, 45 = 1.2.4.1, 46 = откат 1.2.4, 47 = 1.2.4.2,
  48 = откат 1.2.4.1, 49 = 1.2.4.3, 50 = откат 1.2.4.2, 51 = 1.2.4.4, 52 = откат 1.2.4.3 → **следующий ≥ 53**.
- Windows: … 13 = 1.0.6, 14 = откат 1.0.5, 15 = 1.0.7, 16 = откат 1.0.5, 17 = 1.0.8,
  18 = откат 1.0.7, 19 = 1.0.8, 20 = откат 1.0.7, 21 = 1.0.9, 22 = откат 1.0.8, 23 = 1.0.10, 24 = откат 1.0.9 → **следующий ≥ 25**.

## 2. Подготовка

1. `git status` чистый, ветка `app-main-sync`, всё запушено.
2. Номер: в `wavebreak-mobile/pubspec.yaml` → `version: X.Y.Z+<код>`;
   в `wavebreak-pc/pubspec.yaml` → `version: X.Y.Z+<build>`; в
   `wavebreak-pc/windows/installer/wavebreak.iss` → `#define MyAppVersion "X.Y.Z"`
   (установщик версию из pubspec не читает).
3. Тесты и анализ:
   ```bash
   cd wavebreak-mobile && flutter analyze lib test && flutter test
   cd wavebreak-pc && flutter analyze lib test && flutter test
   ```
   Изменения в Core — `go test ./...` в `wavebreak-core` (интеграционные — с тестовой БД,
   `WAVEBREAK_TEST_DATABASE_URL`).
4. Если менялся Go-мост (`wavebreak-mobile/native/hysteria_bridge/*`, `wavebreak-shared/cloak`):
   пересобрать нативную библиотеку (в git её нет):
   ```bash
   bash wavebreak-mobile/native/hysteria_bridge/build_aar.sh
   ```
   Результат — `wavebreak-mobile/android/app/libs/hysteria_bridge.aar`. **Сохранить копию
   предыдущей `.aar`** — она нужна для откатной сборки, если откат на версию до изменения моста.
5. Коммит «Android X (код), Windows Y (build): …» + пуш.

## 3. Сборка Android

Подпись: `wavebreak-mobile/android/key.properties` + `android/app/wavebreak-release.jks`
(только на машине сборки, в git нет). Продакшн-параметры:

```bash
D="--dart-define=FLAVOR=production --dart-define=CORE_BASE_URL=https://core.wavebreak.com.tr --dart-define=USE_MOCK_API=false --dart-define=ACCESS_PROTOCOL=vless"
cd wavebreak-mobile
flutter build apk --release $D                                  # общий APK (~100 МБ)
flutter build apk --release --target-platform android-arm64 $D  # arm64 (~40 МБ)
flutter build apk --release --target-platform android-arm $D    # armv7 (~40 МБ)
```
После каждой команды копировать `build/app/outputs/flutter-apk/app-release.apk` под именем:
`wavebreak-android-X.Y.Z.apk`, `wavebreak-android-X.Y.Z-arm64-v8a.apk`,
`wavebreak-android-X.Y.Z-armeabi-v7a.apk` (все три — один и тот же versionCode).
Для подверсии добавить `--build-name=X.Y.Z.N --build-number=<код>`.

Проверка каждого APK:
```bash
aapt dump badging <apk> | grep versionCode        # нужный код и имя
apksigner verify --print-certs <apk>               # SHA-256 сертификата = как у прошлого релиза
```
Если в релизе есть мост с cloak: `unzip -p <apk> lib/arm64-v8a/libhysteriabridge.so | grep -c wavebreak.app/cloak` > 0.

## 4. Сборка Windows

```bash
cd wavebreak-pc
flutter build windows --release $D
"%LOCALAPPDATA%\Programs\Inno Setup 6\ISCC.exe" windows\installer\wavebreak.iss
```
Установщик: `windows/installer/Output/WaveBreak-Setup-X.Y.Z.exe` → переименовать в
`wavebreak-windows-X.Y.Z-setup.exe`. Проверить версию exe: свойства файла
`build/windows/x64/runner/Release/wavebreak.exe` → `X.Y.Z+<build>`.
В `Release/` должны лежать `sing-box.exe`, `wintun.dll` и (с 1.0.8) `cloak-client-proxy.exe` —
из `windows/runtime_deps`, в git их нет; без любого из них сборка падает. Прокси собирается так:
```bash
cd wavebreak-shared/cloak
GOOS=windows GOARCH=amd64 CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o ../../wavebreak-pc/windows/runtime_deps/cloak-client-proxy.exe ./cmd/cloak-client-proxy
```
Также проверить, что есть `build/windows/x64/runner/Release/data/app.so` (иногда сборка
молча выходит неполной).

## 5. Откатные сборки

Откат = предыдущая **рабочая** версия из её релизного коммита, с номером релиз+1.

```bash
git -c core.longpaths=true worktree add -f C:/wbrb <коммит предыдущей версии>
```
Короткий путь `C:\wbrb` обязателен (длинные пути ломают удаление worktree на Windows). В копию
положить то, чего нет в git:
- Android: `android/key.properties`, `android/app/wavebreak-release.jks`,
  `android/local.properties`, `android/app/libs/hysteria_bridge.aar` (**та версия .aar, с которой
  собиралась та версия**);
- Windows: `windows/runtime_deps/sing-box.exe`, `wintun.dll`.

Сборка:
```bash
flutter pub get
flutter build apk --release --build-name=<старая версия> --build-number=<релиз+1> $D
flutter build windows --release --build-name=<старая версия> --build-number=<релиз+1> $D  # + ISCC
```
Имена: `wavebreak-android-rollback-<старая версия>.apk`,
`wavebreak-windows-rollback-<старая версия>-setup.exe`. Проверить код и подпись (как в п. 3).
**Сразу удалить worktree** — в нём копия ключа подписи:
```bash
git -c core.longpaths=true worktree remove --force C:/wbrb && git worktree prune
```

## 6. Проверка перед публикацией

- Установить релизный APK на телефон через отладку **поверх** (данные сохраняются, подпись та же):
  `adb install -r wavebreak-android-X.Y.Z-arm64-v8a.apk`, проверить подключение и
  диагностический лог.
- Сетевые изменения (новый протокол, cloak …) — дополнительно прогнать с сервера реальным
  путём (пример 1.2.4: мост с `cloak=1` запускали с московского сервера, 75 с трафика).
- Внимание: при установке поверх с **включённым VPN** старый процесс может ещё жить —
  если что-то не подключается, закрыть приложение принудительно и повторить.

## 7. Публикация (после «публикуй»)

Два места, в обоих: **сначала файлы, потом манифест**; перед заменой — резервные копии
`*.bak-before-<версия>-<время>`.

### 7.1 Загрузка и сверка
- Зеркало (Москва, `135.106.227.90`): во временную папку `/var/www/dl/downloads/incoming-<версия>/`.
- Сайт (Турция, `45.15.41.3`): во временную папку `/root/staging/rel-<версия>/`.
- Сверить `sha256sum` на обоих серверах с локальными файлами.

### 7.2 Зеркало `dl.wavebreak.com.tr` — `/var/www/dl/downloads`
Файлы под версионными именами (`wavebreak-android-X.Y.Z.apk`, `…-arm64-v8a.apk`,
`…-armeabi-v7a.apk`, `wavebreak-android-rollback-<v>.apk`, `wavebreak-windows-X.Y.Z-setup.exe`,
`wavebreak-windows-rollback-<v>-setup.exe`); права 644 (exe — 755). Если имя отката уже занято
старым файлом — старый переименовать в `.bak-before-…`.

### 7.3 Сайт `wavebreak.com.tr/downloads`
Два места одновременно — **хост** `/home/wavebreakdeploy/wavebreak-pilot/current/wavebreak-web/public/downloads`
(для будущих пересборок образа) **и контейнер** `wavebreak_pilot-wavebreak-web-1:/app/public/downloads`
(образ не пересобираем — коллега правит сайт прямо на сервере). Запись через временный файл:
`cp → name.tmp → mv`, в контейнер `docker cp … name.tmp` + `docker exec -u 0 … mv`.
Постоянные имена (на них ссылаются сайт и старые приложения):

| Файл на сайте | Что кладём |
|---|---|
| `wavebreak-android.apk` | общий APK релиза |
| `wavebreak-android-X.Y.Z-arm64-v8a.apk`, `…-armeabi-v7a.apk` | APK под архитектуры |
| `wavebreak-android-rollback.apk` | откатный APK |
| `wavebreak-windows.exe` | установщик релиза |
| `wavebreak-windows-rollback.exe` | откатный установщик |

### 7.4 Манифесты — последними
Приложения читают сначала зеркало, потом сайт:
`https://dl.wavebreak.com.tr/downloads/version.json` (Android),
`…/version-windows.json` (Windows), и то же на `wavebreak.com.tr`.

```json
{
  "versionCode": 45,
  "versionName": "1.2.4.1",
  "url": "https://dl.wavebreak.com.tr/downloads/wavebreak-android-1.2.4.1.apk",
  "mirrors": ["https://wavebreak.com.tr/downloads/wavebreak-android.apk"],
  "abis": {
    "arm64-v8a": ["https://dl.wavebreak.com.tr/downloads/wavebreak-android-1.2.4.1-arm64-v8a.apk", "https://wavebreak.com.tr/downloads/wavebreak-android-1.2.4.1-arm64-v8a.apk"],
    "armeabi-v7a": ["https://dl.wavebreak.com.tr/downloads/wavebreak-android-1.2.4.1-armeabi-v7a.apk", "https://wavebreak.com.tr/downloads/wavebreak-android-1.2.4.1-armeabi-v7a.apk"]
  },
  "rollback": {
    "fromVersionCode": 45,
    "versionCode": 46,
    "versionName": "1.2.4",
    "url": "https://dl.wavebreak.com.tr/downloads/wavebreak-android-rollback-1.2.4.apk",
    "mirrors": ["https://wavebreak.com.tr/downloads/wavebreak-android-rollback.apk"]
  }
}
```
Windows (`version-windows.json`) — то же без `abis`. Правила:
- приложение предлагает обновление, если `versionCode` > установленного;
- `rollback` показывается **только** на сборке `fromVersionCode`;
- старые приложения читают только `url` — он должен вести на рабочий общий файл.

Проверить JSON на валидность, записать на зеркало (`version.json.new` → `mv`), затем на сайт
(хост + контейнер, с `.bak-before-…`). Если Windows не выпускается — `version-windows.json` не трогать.

### 7.5 После публикации
```bash
curl -s "https://dl.wavebreak.com.tr/downloads/version.json?t=$RANDOM"    # новая версия
curl -s "https://wavebreak.com.tr/downloads/version.json?t=$RANDOM"
curl -sI <каждая ссылка из манифеста>                                      # 200, размер = файлу
```
Удалить временные папки на серверах. Запись в `CHANGELOG.md` («Release …»), обновить список
занятых номеров (п. 1), коммит + пуш.

## 8. Откат уже опубликованного релиза

Пользователь откатывается сам кнопкой в «Обновлениях» (поле `rollback`). Чтобы откатить **всех**:
вернуть прежний манифест из `version.json.bak-before-<версия>-*` на зеркале и сайте — но
пользователи, уже поставившие новую версию, не получат старую автоматически (меньший код);
для них нужен новый релиз с большим номером.

## 9. Если в релизе есть изменения Core (сервер)

1. Сверить исходники Core на сервере с тем, что выкатываем (пофайловые `sha256`), чтобы не
   выкатить заодно чужие/неготовые изменения.
2. Сверить окружение работающего контейнера с тем, что даст `docker compose config`
   (по хешам значений, без вывода секретов) — коллега мог пересоздать контейнер с другим env.
3. Копии: `.env.pilot.bak-…`, `docker-compose.pilot.yml.bak-…`,
   `tar` прежних исходников в `/root/backups/`.
4. Залить `git archive HEAD wavebreak-core` в `…/current/`, затем
   ```bash
   docker compose -p wavebreak_pilot --env-file .env.pilot -f docker-compose.pilot.yml build wavebreak-api
   docker compose -p wavebreak_pilot --env-file .env.pilot -f docker-compose.pilot.yml up -d --no-deps wavebreak-api
   ```
5. Проверить `healthy`, логи, выдачу `/v1/sub/<grant>` (учётки в выводе маскировать).
6. Правку env/compose повторить в репозитории (`wavebreak-infrastructure/`) и в отчёте.
Миграции БД — только после отдельного «ок».

## 10. Частые ловушки
- Забыли `--dart-define` → мок-режим на телефоне.
- Откат собран с новой `.aar` моста или без `runtime_deps` → сборка не та / не собирается.
- Заменили манифест раньше файлов → приложения скачают несуществующий или старый файл.
- Положили файлы только на хост сайта или только в контейнер → сайт отдаёт старое.
- Переиспользовали номер тестовой сборки → телефон с тестовой версией не увидит обновление.
- Ограничение прав Claude на «выкатку в прод»: публикация идёт только после явного «публикуй».
