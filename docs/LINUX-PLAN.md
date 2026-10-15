# WAVEBREAK для Linux — план (отдельный этап)

Черновик 14.10.2026 по задаче владельца «реализовать ПК-версию под Linux». Код ещё не
начат: Linux-приложение на Flutter собирается только на Linux. Машина сборки сейчас — Windows.

## Что переиспользуем

Интерфейс ПК-версии (`wavebreak-pc`) — тот же Flutter-код. Платформенных мест немного:
17 проверок `Platform.isWindows`. Основные:

| Часть | Windows сейчас | Linux |
|---|---|---|
| Туннель | `sing-box.exe` + Wintun (`WindowsVpnAdapter`), бета — `xray.exe` с TUN | `sing-box` (или `xray`) с TUN `auto_route`: тот же конфиг, без Wintun |
| Права | весь процесс от администратора (манифест UAC) | интерфейс от пользователя; TUN поднимает маленькая служба (systemd) с `CAP_NET_ADMIN` — как задумано для Windows (`MICROSERVICES-PLAN.md`, п. 4) |
| Закрытие чужих VPN | `conflicting_vpn_closer.dart` (процессы Windows) | не нужно — предупреждение, если уже есть маршрут по умолчанию через `tun*`/`wg*` |
| Обновление | Inno Setup + `version-windows.json` | `version-linux.json`; пакет `.deb` (Ubuntu/Debian) и AppImage (остальные); `.deb` ставится через `pkexec apt install` |
| Автозапуск, трей | реестр, трей Windows | `~/.config/autostart/*.desktop`, `tray_manager`/AppIndicator |
| Хранилище секретов | `flutter_secure_storage` (DPAPI) | `flutter_secure_storage` (libsecret) |
| Лаунчер | `wavebreak-launcher` (WebView2) | не нужен: ставится пакетом |

## Шаги

1. **Машина сборки:** Ubuntu 22.04 (виртуалка или CI-раннер): Flutter, `clang`, `cmake`, `ninja`,
   `libgtk-3-dev`, `libsecret-1-dev`, `libayatana-appindicator3-dev`.
2. **Каркас:** `flutter create --platforms=linux .` в `wavebreak-pc`. Сборка
   `flutter build linux --release` с теми же 4 боевыми `--dart-define`.
3. **`LinuxVpnAdapter`:**
   - тот же конфиг sing-box, что на Windows (`windows_vpn_adapter.dart` → общий генератор);
   - запуск через службу `wavebreak-tun.service`;
   - команды по локальному сокету: подключить, отключить, состояние, задержка.
4. **Служба:** Go, ~300 строк. Держит sing-box и TUN и слушает unix-сокет в `/run/wavebreak/`
   (доступ группе `wavebreak`). Ставится пакетом вместе с `sing-box`.
5. **Пакеты:**
   - `.deb` (приложение, служба, `sing-box`, ярлык, иконка);
   - AppImage — только интерфейс, служба ставится отдельной командой с `pkexec`.
6. **Выпуск:** `release.sh build linux` на Linux-машине. Номера Linux свои, `version-linux.json`
   на сайте и зеркале, кнопка «Linux» на странице загрузок.
7. **Проверка:** Ubuntu 22.04/24.04, Debian 12, Fedora (AppImage); Wayland и X11;
   Direct, REALITY, Hysteria2.

## Оценка

Каркас и сборка — день. Служба и адаптер туннеля — 2–3 дня. Пакеты и выпуск — день.
Проверка на дистрибутивах — день-два.

Нужно от владельца: машина или CI-раннер с Ubuntu для сборки и проверки.
