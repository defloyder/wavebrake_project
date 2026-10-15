# WAVEBREAK Lite — клиент для 32-битной Windows

Полное приложение для ПК (`wavebreak-pc`) на Flutter, а Flutter собирает Windows-приложения
только для x64 и ARM64 — 32-битной сборки у него нет. Lite закрывает 32-битную Windows 10+:
вход по email/паролю (и код подтверждения почты), список серверов из подписки
(`POST /v1/me/access`), подключить/отключить. Весь трафик идёт через sing-box (x86) с
TUN-адаптером wintun — как в полной версии. Нет: редизайна, метрик, теста скорости, своих
серверов и сторонних подписок, Hysteria2 через cloak/pin (Core их Lite не выдаёт —
приложение не объявляет `hysteria-cloak`/`hysteria-pin`).

## Как устроено

- Go, только стандартная библиотека (Win32 через `syscall`), `GOARCH=386`.
- Окно — локальная страница в браузере по умолчанию: `http://127.0.0.1:47613/?t=<токен>`.
  Токен случайный на каждый запуск; API принимает только `POST` с заголовком `X-Lite-Token`
  и `Host` = 127.0.0.1/localhost, без CORS — чужой сайт программой управлять не может
  (тест `server_test.go`).
- Запуск без прав администратора просит UAC и запускает копию с `--serve <токен>`; страница
  открывается через `explorer.exe` от имени обычного пользователя. Повторный запуск при
  работающей программе просто открывает страницу.
- sing-box запускается в Job object с «убить при закрытии»: если Lite завершится как угодно,
  sing-box не останется держать маршруты. Проверка связи каждые 30 с
  (`gstatic.com/generate_204` через туннель), 3 неудачи подряд или падение sing-box —
  переподключение (до 5 попыток).
- Конфиг sing-box — тот же, что у полной версии (`wavebreak_links/lib/src/singbox.dart`):
  TUN, DoH 1.1.1.1, всё через прокси. Проверено `sing-box check` для REALITY, Direct-TLS (ws),
  Hysteria2 (obfs + port hopping).
- Данные: `%LOCALAPPDATA%\WAVEBREAK Lite\` — `state.json` (refresh-токен зашифрован DPAPI
  текущего пользователя Windows, `install_id`, выбранный сервер), `lite.log`.
- Устройство регистрируется с `install_id` (повторный вход не занимает новый слот; старый Core
  отвечает 400 — тогда без него).

## Сборка

```bash
wavebreak-lite/build.sh 1.0.0
```
Тесты, `go vet` (в т.ч. для 386), exe и установщик
`installer/Output/WaveBreak-Lite-Setup-<версия>.exe` (Inno Setup, ставится в Program Files
(x86), Windows 10+).

`runtime_deps/`:
- `wintun.dll` — x86 из `https://www.wintun.net/builds/wintun-0.14.1.zip` (`bin/x86`), подписан
  WireGuard LLC; sha256 `d694fa46ab4cfebcb2632d094c7aa97278eef2f8052438621766d863ae98a931`.
  В git (как и x64-версия у `wavebreak-pc`).
- `sing-box.exe` — **не в git** (`*.exe`), x86 из официального релиза:
  ```bash
  curl -sSL -o /tmp/sb.zip https://github.com/SagerNet/sing-box/releases/download/v1.14.1/sing-box-1.14.1-windows-386.zip
  unzip -o /tmp/sb.zip -d /tmp/sb && cp /tmp/sb/sing-box-1.14.1-windows-386/sing-box.exe wavebreak-lite/runtime_deps/
  ```
  sha256 `c096b2facada2e3502bac69dae399302d30b3dc97e6f6f8d7b0cb6b3cdbc28f6`.

## Состояние

1.0.0 — собран, на настоящей 32-битной Windows **не проверялся** (вход, подключение, UAC).
На сайт не выложен: ссылку и раздачу добавлять после проверки на устройстве. Автообновления нет.
