# Окно входа (V5): что сделано, что осталось и что нужно от вас

Дата: 05.10.2026. Ветка: `app-main-sync`. Для владельца и коллеги.

## 1. Что уже есть в приложении (Android)

| Что | Где | Состояние |
|---|---|---|
| Экран приветствия V5: звёзды, волны, логотип-надпись, «Регистрация», «Войти» | `wavebreak-mobile/lib/features/auth/welcome_screen.dart` | работает |
| Кнопки Google / Telegram | там же, `_SocialButton(... note: s.comingSoon)` | показаны неактивными, с подписью «Скоро» |
| Кнопка «Почта» | там же, ведёт на `/login` | работает (вход по почте и паролю) |
| «Продолжить со своей ссылкой» | там же | работает без нашего сервера |
| Вход, регистрация, подтверждение почты кодом | `login_screen.dart`, `register_screen.dart`, `verify_email_screen.dart` | работают, Core `/v1/auth/*` |
| Клиент Core | `wavebreak-mobile/lib/services/core_api/core_api.dart`, `core_gateway.dart` | `login`, `register`, `refresh` |
| Строки на 7 языках | `wavebreak-mobile/lib/core/i18n/app_strings.dart` (`welcome*`, `orContinueWith`, `authEmail`, `comingSoon`) | есть |

Как включить кнопку, когда сервер будет готов: в `welcome_screen.dart` убрать у
`_SocialButton` параметр `note:` и передать `onTap:` с вызовом нового метода из
`core_gateway.dart`. Остальной экран менять не нужно.

## 2. Что уже есть в Core (Go, `wavebreak-core`)

- Таблица `user_identities (provider, provider_user_id, user_id, …)`, уникальная пара
  `(provider, provider_user_id)` — миграция `00002_product_core_completion.sql`. Подходит
  для Google и Telegram без изменений.
- Пользователь без почты и пароля уже допустим: `UpsertTelegramIdentity` в
  `internal/store/product.go` создаёт пользователя только с `username`.
- Telegram через бота: `POST /v1/bot/telegram/identify` (ключ бота) находит или создаёт
  пользователя по Telegram ID; привязка к существующему аккаунту — через
  `POST /v1/me/identities/telegram/link` (токен на 15 минут, таблица `account_link_tokens`).
- Письма: Brevo SMTP подключён, коды подтверждения почты уже отправляются
  (`/v1/auth/email/verify`, `/v1/auth/email/resend`).
- Маршруты — `internal/httpapi/server.go`.

## 3. Чего не хватает, по способам входа

### 3.1 Google — нужно от владельца

Я не могу сам: настройка в Google Cloud идёт под вашей учётной записью, а для Android
нужен отпечаток ключа подписи, которого нет в git (и не должно быть).

1. Google Cloud Console → новый проект «WAVEBREAK» → «OAuth consent screen»
   (тип External, название приложения, почта поддержки, ссылка на политику).
2. Credentials → Create OAuth client ID → **Android**:
   - Package name: `com.wavebreak.wavebreak`
   - SHA-1 релизного ключа. Получить у себя на машине с ключом:
     `keytool -list -v -keystore <файл ключа> -alias <alias из key.properties>`
     (в чат и git не присылать ничего, кроме строки SHA-1 — она не секрет).
3. Ещё один OAuth client ID → **Web application** (по нему сервер проверяет вход).
   Прислать мне **Web client ID** (вида `…apps.googleusercontent.com`) — он публичный.
   Client secret не нужен и не присылать.
4. Дать «ок» на две вещи (по нашим правилам без этого не делаю):
   - зависимость `google_sign_in` в мобильном приложении;
   - деплой Core с новым методом.

Что сделаю после этого: в Core — `POST /v1/auth/google {id_token}`: проверка подписи
токена по ключам Google, `aud` = Web client ID, создание или поиск пользователя через
`user_identities(provider='google')`, ответ — та же пара токенов, что у `/auth/login`.
В приложении — кнопка Google, вызов `google_sign_in`, отправка `id_token` в Core.
Миграция базы не нужна.

### 3.2 Telegram — нужно от коллеги (бот) и владельца

Код бота не лежит в этом репозитории (крутится в контейнере на сервере), поэтому бот
меняет тот, у кого его исходники. Токен бота мне не нужен и использовать его я не буду.

Схема входа (без браузера, через уже работающего бота):

1. Приложение: `POST /v1/auth/telegram/start` → Core выдаёт одноразовый `login_token`
   (5 минут) и ссылку `https://t.me/<бот>?start=login_<login_token>`.
2. Приложение открывает ссылку в Telegram, пользователь жмёт «Start».
3. **Бот** (правка у коллеги): получив `/start login_<token>`, вызывает уже существующий
   `POST /v1/bot/telegram/identify` с новым полем `login_token` (кроме `provider_user_id`,
   `username`, `display_name`). Core помечает токен как подтверждённый этим пользователем.
   Бот отвечает «Готово, вернитесь в приложение».
4. Приложение раз в 2 секунды спрашивает `POST /v1/auth/telegram/poll {login_token}`
   и получает пару токенов, как после `/auth/login`.

Что нужно:
- коллеге — обработка `start login_…` в боте (пункт 3);
- владельцу — «ок» на **миграцию** (новая таблица одноразовых токенов входа: в
  `account_link_tokens` поле `user_id` обязательное, а у входящего пользователя его ещё
  нет) и на деплой Core;
- мне — имя бота (публичное, `@…`).

Контракт для бота (единственное, что ему нужно знать):

```
POST /v1/bot/telegram/identify   (как сейчас, ключ бота в заголовке)
{
  "provider_user_id": "123456789",
  "username": "user",
  "display_name": "Имя",
  "login_token": "<то, что пришло после start login_>"   // новое, необязательное
}
→ 200 { … пользователь … }        // как сейчас
→ 404 "login token not found"     // токен истёк или уже использован — бот пишет «ссылка устарела, нажмите кнопку в приложении ещё раз»
```

### 3.3 Вход по коду на почту (без пароля) — нужно «ок» владельца

Всё есть, кроме двух методов Core: `POST /v1/auth/email/login-code/request {email}`
и `POST /v1/auth/email/login-code/confirm {email, code}` → пара токенов. Письмо — через
тот же Brevo и шаблон, что у подтверждения почты. Нужно «ок» на деплой Core
(и, возможно, на миграцию для хранения кодов входа — посмотрю, хватит ли таблицы из
`00005_email_verification.sql`). В приложении кнопку «Почта» можно оставить на
обычном входе или переключить на код — решите вы.

### 3.4 Apple — позже

Нужен платный аккаунт Apple Developer. Для Android вход Apple идёт через веб-окно;
отложено, как договорились.

## 4. Земля на экране входа — исходники

Сам этот элемент я не делаю (договорённость по сфере). Всё, что для него есть:

- Макет и ассеты (у владельца): `C:/Users/Asus/Documents/Codex/2026-10-04/new-chat/outputs/`
  - `wavebreak-v5.html`, `wavebreak-app-v5.html` — живой макет, экран входа;
  - `wavebreak-auth-v4.png` / `.svg` — экран входа целиком;
  - `wavebreak-earth-v4.webp`, `wavebreak-earth-v3.png` — текстура Земли;
  - `wavebreak-spec-v5.txt` — спецификация (про вход — строки ~54 и ~213).
- Уже в приложении (сделано второй сессией, работает на главной):
  - `wavebreak-mobile/lib/features/immersive/living_core.dart` — виджет сферы (`LivingCore`,
    `CoreStage`); с сегодняшнего дня перекрашивается в цвет флага;
  - `wavebreak-mobile/shaders/living_sphere.frag` — шейдер;
  - `wavebreak-mobile/assets/textures/earth_surface.webp` — текстура;
  - всё подключено в `pubspec.yaml` (`assets/textures/`, `shaders:`).
- Место на экране: `welcome_screen.dart`, сейчас там `StarField` и `WavebreakWordmark`
  над кнопками. Фон и стекло карточек уже V5 и тоже следуют цвету флага.
- Производительность: рисовать через общие часы `ImmersiveClock` (30 кадров/с), без
  своих `AnimationController..repeat()` — иначе экран перерисовывается на полной
  частоте дисплея (см. CHANGELOG за 05.10, раздел про плавность).

## 5. Коротко: кто что делает

| Шаг | Кто |
|---|---|
| Google Cloud: Android-клиент (SHA-1) и Web-клиент, прислать Web client ID | владелец |
| «ок» на `google_sign_in`, миграцию токенов входа, деплой Core | владелец |
| Имя бота | владелец |
| Бот: обработка `start login_…` и поле `login_token` в identify | коллега |
| Core: `/auth/google`, `/auth/telegram/start|poll`, `/auth/email/login-code/*` | я, после «ок» |
| Приложение: включить кнопки Google и Telegram, экран ожидания подтверждения Telegram | я |
| Земля на экране входа | владелец / другая сессия (исходники в п. 4) |
