# Новая машина сборки: всё, чтобы выпускать обновления и откаты

Для того, кто впервые собирает и публикует WAVEBREAK (Android + Windows) на своей машине.
После этого документа — `docs/RELEASE-PROCESS.md` (сам порядок сборки, откатов и публикации).

Секретов в этом документе нет: ключ подписи, пароли, SSH-ключи передаются отдельно (раздел 3).

---

## 1. Что лежит в git, а чего там нет

| Что | В git? | Откуда взять |
|---|---|---|
| Исходники приложений, Core, сайта, инфраструктуры | да | `git clone`, ветка `app-main-sync` |
| `wavebreak-mobile/android/app/wavebreak-release.jks` (ключ подписи Android) | **нет** | у владельца, лично (раздел 3) |
| `wavebreak-mobile/android/key.properties` (пароли и алиас ключа) | **нет** | у владельца, вместе с ключом |
| `wavebreak-mobile/android/local.properties` | нет | создаётся сам при первой сборке Flutter |
| `wavebreak-mobile/android/app/libs/hysteria_bridge.aar` | нет | собрать (раздел 4) или взять у владельца |
| `wavebreak-pc/windows/runtime_deps/sing-box.exe` | нет | скачать (раздел 5) |
| `wavebreak-pc/windows/runtime_deps/wintun.dll` | да | — |
| `wavebreak-pc/windows/runtime_deps/cloak-client-proxy.exe` | нет | собрать (раздел 5) |
| Доступ к серверам (TR 45.15.41.3, зеркало RU 135.106.227.90) | — | свой SSH-ключ, добавляет владелец |

`*.jks`, `key.properties`, `*.aar`, `*.exe` исключены в `.gitignore` — положенные на место,
они не попадут в коммит.

## 2. Инструменты (версии, на которых собираются текущие релизы)

| Инструмент | Версия | Зачем |
|---|---|---|
| Flutter | 3.47.2 (Dart 3.13.2) | обе программы |
| JDK | 17 | Android-сборка, gomobile |
| Android SDK | build-tools 35/36, платформа по `flutter doctor` | Android |
| Android NDK | 28.2.13676358 | только для сборки `hysteria_bridge.aar` |
| Go | 1.27 | `.aar`, `cloak-client-proxy.exe`, Core |
| gomobile | `go install golang.org/x/mobile/cmd/gomobile@latest`, затем `gomobile init` | `.aar` |
| Visual Studio 2022 Build Tools, «Desktop development with C++» | — | `flutter build windows` |
| Inno Setup 6 | `%LOCALAPPDATA%\Programs\Inno Setup 6\ISCC.exe` | установщик Windows |
| Git Bash | — | все команды в документах написаны для bash |

Проверка: `flutter doctor` — без ошибок для Android и Windows.

## 3. Ключ подписи Android — самое важное

**Почему без него никак.** Android ставит обновление поверх установленного приложения, только
если оно подписано **тем же** ключом. Релизы WAVEBREAK подписаны ключом владельца
(сертификат `CN=WAVEBREAK, O=WAVEBREAK, Istanbul`). Сборка с debug-ключом или с новым
ключом **не обновит** ни одного пользователя — Android откажет («приложение не установлено»).
Ключ нельзя пересоздать: потерянный или новый ключ = новое приложение, у всех переустановка.

**Как получить.** Владелец передаёт два файла — `wavebreak-release.jks` и `key.properties`:
- архивом 7-Zip с паролем (AES-256, «шифровать имена файлов»);
- архив одним каналом (файл в Telegram), пароль от архива — другим (голосом, другой мессенджер).

**Куда положить** (пути важны — сборка ищет файлы именно там):
```
wavebreak-mobile/android/key.properties
wavebreak-mobile/android/app/wavebreak-release.jks
```
`key.properties` копируется как есть, ничего в нём не менять. Это стандартный файл подписи
Flutter: `storePassword`, `keyPassword`, `keyAlias`, `storeFile` (путь к `.jks` относительно
`android/app`).

**Проверка, что сборка подписана правильно** — после каждой релизной сборки:
```bash
APKSIGNER=$(ls "$ANDROID_HOME"/build-tools/*/apksigner* | tail -1)
"$APKSIGNER" verify --print-certs wavebreak-android-X.Y.Z.apk | grep -E "DN|SHA-256"
```
Должно быть:
- `Signer #1 certificate DN: CN=WAVEBREAK, O=WAVEBREAK, ... Istanbul ...`
- `SHA-256 digest: d0d706bf9211d6a4c50e6a86742a2452eee650f0f3a4db5d5463a24b63cc57b6`

Другой отпечаток (например, `Android Debug`) — **не публиковать**: это значит, что
`key.properties` не найден и Gradle подписал debug-ключом.

**Хранение.** Ключ и пароли не коммитить, не пересылать в открытых чатах, не выкладывать на
серверы. Держать резервную копию в надёжном месте (зашифрованный архив).

## 4. Нативная библиотека Android: `hysteria_bridge.aar`

Содержит Xray-core и клиент Hysteria2 (с cloak). Без неё Android-сборка падает.

```bash
bash wavebreak-mobile/native/hysteria_bridge/build_aar.sh
```
Нужны Go, gomobile, JDK 17, Android SDK + NDK (пути — переменные в начале скрипта:
`JAVA_HOME`, `ANDROID_HOME`, `ANDROID_NDK_HOME`; поправить под свою машину). Результат
копируется в `wavebreak-mobile/android/app/libs/hysteria_bridge.aar`.

Проверка, что в библиотеке есть cloak (нужно с 1.2.4):
```bash
unzip -p wavebreak-android-X.Y.Z.apk lib/arm64-v8a/libhysteriabridge.so | grep -c wavebreak.app/cloak   # > 0
```
Для **откатной** сборки нужна та `.aar`, с которой собиралась та версия. Пока мост не
менялся (последнее изменение — cloak, 1.2.4), подходит текущая.

## 5. Файлы Windows: `sing-box.exe`, `cloak-client-proxy.exe`

`sing-box.exe` (сейчас 1.14.1) — скачать по `wavebreak-pc/windows/runtime_deps/README.md`.

`cloak-client-proxy.exe`:
```bash
cd wavebreak-shared/cloak
GOOS=windows GOARCH=amd64 CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" \
  -o ../../wavebreak-pc/windows/runtime_deps/cloak-client-proxy.exe ./cmd/cloak-client-proxy
```
Без любого из трёх файлов (`sing-box.exe`, `wintun.dll`, `cloak-client-proxy.exe`)
`flutter build windows` падает.

Подписи кода у Windows-установщика нет — ключ для Windows не нужен.

## 6. Обязательные параметры сборки

Любая сборка для реальных пользователей — **только** с четырьмя параметрами, иначе приложение
уходит в демо-режим (фейковые серверы, VPN не поднимается):
```bash
D="--dart-define=FLAVOR=production --dart-define=CORE_BASE_URL=https://core.wavebreak.com.tr --dart-define=USE_MOCK_API=false --dart-define=ACCESS_PROTOCOL=vless"
```

## 7. Первая проверочная сборка

```bash
cd wavebreak-mobile && flutter pub get && flutter test
flutter build apk --release --target-platform android-arm64 $D
# проверить подпись (раздел 3)

cd ../wavebreak-pc && flutter pub get && flutter test
flutter build windows --release $D
# в build/windows/x64/runner/Release/ должны быть sing-box.exe, wintun.dll, cloak-client-proxy.exe, data/app.so
```
Проверочную сборку **не публиковать** и не ставить пользователям: номер версии у неё —
из `pubspec.yaml`, а номера не переиспользуются.

## 8. Доступ к серверам для публикации

- **TR-PILOT-01** `45.15.41.3` — сайт `wavebreak.com.tr/downloads` (папка на хосте
  `/home/wavebreakdeploy/wavebreak-pilot/current/wavebreak-web/public/downloads` **и** контейнер
  `wavebreak_pilot-wavebreak-web-1`, образ не пересобирается), Core.
- **RU-MSK-01** `135.106.227.90` — зеркало `dl.wavebreak.com.tr` (`/var/www/dl/downloads`).
- Свой SSH-ключ; владелец добавляет публичную часть в `authorized_keys` на обоих серверах.

## 9. Дальше — выпуск

`docs/RELEASE-PROCESS.md`: нумерация (номер никогда не повторяется, следующий свободный —
в разделе 1 того документа), сборка релиза и отката, проверка, загрузка на оба сервера,
манифесты последними, проверка ссылок, запись в `CHANGELOG.md`.

Короткий чек-лист перед публикацией:
- [ ] номер версии больше опубликованного, не использовался раньше (включая тестовые);
- [ ] Windows: версия из **трёх** чисел (`1.0.11`, не `1.0.10.1`) — иначе exe получит `1.0.0`
      без номера сборки и приложение будет бесконечно предлагать обновление;
- [ ] Android: подпись с отпечатком `d0d706bf…57b6` (раздел 3);
- [ ] собран откат (предыдущая рабочая версия с номером релиз+1);
- [ ] все 4 `dart-define`;
- [ ] тесты прошли, по возможности проверено на устройстве;
- [ ] файлы на зеркале и сайте сверены по sha256, манифесты заменены последними,
      старые файлы сохранены как `.bak-before-…`;
- [ ] запись в `CHANGELOG.md`, коммит и пуш в `app-main-sync`.
