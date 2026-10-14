# WAVEBREAK для iPhone, iPad и Mac — план (большой этап)

Задача владельца 14.10.2026: сборки под iPhone (старые и новые), iPad и Mac. Код не начат.
Собрать и подписать Apple-сборку на Windows нельзя: нужен Mac с Xcode.

## Что уже есть

- `wavebreak-mobile/ios`: заготовка Flutter (Runner), iOS 15.0. Интерфейс общий с Android:
  экраны, подписки, разбор ссылок, Core API.
- Нет: туннеля (Network Extension), движка Xray и Hysteria2 под iOS, подписи, macOS-проекта.

## Охват устройств

| Устройства | Как |
|---|---|
| iPhone с iOS 15+ (iPhone 6s/SE 1-го поколения и новее, 2015+) | iOS-приложение |
| iPad (все с iPadOS 15+) | то же приложение, универсальное (iPhone + iPad, разметка уже адаптивная) |
| Mac с Apple Silicon (M1+) | то же приложение, «Designed for iPad» на macOS — без отдельной сборки |
| Mac на Intel и отдельное Mac-приложение | `macos/` (Flutter macOS) + Network Extension для macOS — вторым шагом |
| iPhone старше 6s (iOS 12 и ниже) | невозможно: Flutter и нужные API требуют iOS 13+, а VPN-расширение — iOS 15 для нормальной работы |

## Устройство приложения

1. **Packet Tunnel** (`NEPacketTunnelProvider`) — отдельная цель Xcode. Внутри TUN системы,
   tun2socks и движок, как служба `:RunWaveEngine` на Android.
2. **Движок** — тот же Go-код моста, что на Android (`native/hysteria_bridge`):
   `gomobile bind -target ios` даёт `HysteriaBridge.xcframework` (Xray + Hysteria2 + tun2socks +
   закрытие зависших соединений). **Ограничение iOS:** расширению дают около 50 МБ памяти.
   Xray собирается без geodata (правила маршрутизации приходят из Core), лимиты Go GC выставляются в мосте.
3. **Связь с приложением**: App Group (общие настройки, конфиг, счётчики трафика) и
   `NETunnelProviderManager` (подключить/отключить, состояние). Это аналог MethodChannel
   `app.wavebreak/vpn_state` на Android: Dart-адаптер `IosVpnAdapter`.
4. **Возможности iOS**: «VPN по требованию» (On Demand) вместо автозапуска, Siri Shortcuts и
   виджет — потом.
5. **Вход, подписки, метрики, тест скорости** — общий Dart-код без изменений.

## Что нужно от владельца

1. **Mac** (любой с Apple Silicon) с Xcode 16+ — машина сборки. Можно облачный, например
   MacStadium, или раннер GitHub `macos-14` для CI.
2. **Apple Developer Program на организацию** ($99/год). Apple принимает VPN-приложения только
   от организаций, не от частных лиц. Нужен D-U-N-S номер компании (оформляется бесплатно,
   1–2 недели).
3. **Права Network Extension (Packet Tunnel)** для App ID — включаются в аккаунте.
4. **Решение по распространению.** В российском App Store Apple удаляет VPN-приложения по
   требованию РКН. Варианты: App Store других стран (пользователь меняет регион Apple ID),
   TestFlight (до 10 000 тестеров, сборка живёт 90 дней), для Mac — подписанный `.dmg` с сайта
   (нотаризация Apple, без App Store).

## Шаги и оценка

| Шаг | Срок |
|---|---|
| Mac, аккаунт, сертификаты, App ID с Network Extension и App Group | ждёт владельца |
| xcframework моста (`build_xcframework.sh`) и проверка памяти в расширении | 2–3 дня |
| Packet Tunnel: TUN, tun2socks, Xray и Hysteria2, переподключения, проверка туннеля | 3–4 дня |
| `IosVpnAdapter` в Dart: состояние, скорость, метрики | 1–2 дня |
| iPad-разметка, «Designed for iPad» на Mac | 1 день |
| TestFlight, затем App Store | 2–3 дня + проверка Apple (обычно 1–3 дня, VPN-приложения дольше) |
| Отдельное Mac-приложение (Intel) | 3–4 дня, вторым этапом |
| CI: сборка на раннере `macos-14`, выгрузка в TestFlight из пайплайна | 1 день |
