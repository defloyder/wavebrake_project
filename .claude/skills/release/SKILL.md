---
name: release
description: Build and publish a WAVEBREAK Android/Windows update (release + rollback) with tools/release/release.sh — preflight, build, staging links for the phone check, publish after the owner says «публикуй». Use whenever the owner or colleague asks to build, release, publish or roll out an update.
---

# Выпуск обновления WAVEBREAK

Работаем только через `tools/release/release.sh`. Никаких ручных `flutter build` для пользователей.

## 0. Синхронизация

```bash
git switch app-main-sync && git pull --rebase origin app-main-sync
```
Если есть незакоммиченное — сначала выяснить у человека, что это, закоммитить/запушить или убрать.

## 1. Проверка машины

```bash
tools/release/release.sh check
```
Скрипт остановится и скажет, чего не хватает (ключ подписи, sing-box, SSH, отставание ветки…).
Если не хватает ключа подписи или SSH-ключа — сказать человеку, где это описано
(`docs/BUILD-MACHINE-SETUP.md`), и **не** пытаться обойти.

## 2. Сборка

```bash
tools/release/release.sh build            # или: build android / build windows
```
Скрипт сам: берёт следующие номера (из `tools/release/releases.json` и живых манифестов),
прописывает их в pubspec/iss, гоняет тесты, коммитит и пушит, пересобирает мост `.aar` если
изменились его исходники, собирает релиз и откат (откат — прошлый опубликованный релиз из его
коммита), проверяет подпись и что в сборке боевой адрес Core (не заглушки). Сборка ~20–40 минут —
запускать в фоне. Результат — `.artifacts/release/`.

Своё имя версии Android (например, крупное обновление): `tools/release/release.sh build android 1.3.0`.
Если нужна конкретная версия (например, минорная), сначала посмотреть `check`, а номер версии
менять только через `tools/release/rel.dart next <android|windows> <имя>` — скрипт не даст
четырёхзначную версию Windows.

## 3. Тестовые ссылки

```bash
tools/release/release.sh stage
```
Выкладывает во временную папку на зеркале и сервере сайта (пользователи не видят) и печатает
ссылки. Номера с этого момента считаются занятыми (записываются в `releases.json` и пушатся).
Дать человеку ссылки и попросить проверить на телефоне/ПК: Direct и Hysteria, пара сайтов.

## 4. Публикация — только после «публикуй»

```bash
tools/release/release.sh publish
```
Файлы на зеркало и в папку сайта, манифесты последними, старое — `.bak-before-*`, все ссылки
проверяются, история в `releases.json`, теги `android/<версия>` / `windows/<версия>`, пуш.

Если автоматическая защита Claude Code не даёт выполнить шаг на сервере — не обходить; сказать
человеку и предложить запустить ту же команду самому.

## 5. После

- `CHANGELOG.md`: переименовать раздел «Не выпущено» в «Android X (код) · Windows Y (код) —
  опубликованы ДАТА», указать откаты; коммит, пуш.
- Коротко отчитаться человеку: версии, что вошло, что не проверено на устройстве.
