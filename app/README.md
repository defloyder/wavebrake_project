# Auralith Web Platform

Общий README по текущему состоянию проекта: сайт, профиль пользователя, подписки, mock subscription API и админ-панель.

## 1) Что входит в проект

Проект построен на `Laravel 13` и включает:

- публичный лендинг `Auralith`;
- пользовательский контур с логином и профилем;
- оформление/продление подписки;
- тестовый платежный flow (заказы);
- mock endpoint'ы подписки (`/sub/{token}` и `/sub/{token}/status`);
- отдельную админ-панель на `/admin` с dashboard и CRUD.

---

## 2) Стек

- Backend: `Laravel 13`, `Eloquent ORM`
- Frontend: Blade templates + custom CSS/JS
- Admin UI: `Bootstrap 5`, `Chart.js`, `Simple-DataTables`
- DB (локально): `SQLite`

---

## 3) Основные страницы и сценарии

### Публичная часть

- `/` — лендинг

### Пользовательский контур

- `/login` — вход пользователя (email/password)
- `/profile` — профиль пользователя (требует auth)
  - текущая подписка, срок действия, метрики;
  - трафик и узел маршрутизации;
  - создание тестового заказа на продление;
  - удаление заказа из истории.

### Admin-контур

- `/admin/login` — вход администратора
- `/admin` — dashboard админ-панели
- `/admin/{resource}` — список записей
- `/admin/{resource}/{id}` — просмотр записи (`Просмотреть`)
- `/admin/{resource}/{id}/edit` — редактирование (если разрешено)

> Вход пользователя и вход администратора изолированы.

---

## 4) Роуты (сводка)

### Пользовательские

- `GET /` -> `home`
- `GET /login`, `POST /login`, `POST /logout`
- `GET /profile`
- `POST /subscribe`
- `POST /profile/payments/create`
- `POST /profile/orders/{id}/cancel`

### Админские

- `GET /admin/login`, `POST /admin/login`, `POST /admin/logout`
- `GET /admin` -> dashboard
- `GET /admin/{resource}`
- `GET /admin/{resource}/{id}` -> show
- `GET /admin/{resource}/create` -> create
- `POST /admin/{resource}` -> store
- `GET /admin/{resource}/{id}/edit` -> edit
- `PUT /admin/{resource}/{id}` -> update
- `DELETE /admin/{resource}/{id}` -> destroy

### Mock Subscription API

- `GET /sub/{token}` — base64 subscription content
- `GET /sub/{token}/status` — статус подписки

---

## 5) Компоненты backend

### Контроллеры

- `AuthController` — пользовательская авторизация
- `CabinetController` — профиль, подписка, платежи, удаление заказа
- `AdminAuthController` — вход/выход администратора
- `AdminPanelController` — dashboard и CRUD-операции админки

### Middleware

- `admin` (`AdminOnly`) — доступ к `/admin/*` только при `admin_id` в сессии

### Основные модели

- `User`
- `Admin`
- `Plan`
- `Subscription`
- `Node`
- `FkOrder`

---

## 6) Компоненты frontend (views)

### Публичные/пользовательские

- `resources/views/landing.blade.php`
- `resources/views/auth/login.blade.php`
- `resources/views/cabinet.blade.php`

### Админские

- `resources/views/admin/login.blade.php`
- `resources/views/admin/layout.blade.php`
- `resources/views/admin/dashboard.blade.php`
- `resources/views/admin/resource-index.blade.php`
- `resources/views/admin/resource-show.blade.php`
- `resources/views/admin/resource-form.blade.php`

---

## 7) Политика редактирования в админке

Конфигурация ресурсов задается в `AdminPanelController::RESOURCES`.

- `subscriptions`:
  - editable: `true`
  - status select:
    - `active`
    - `inactive`
    - `expiring_soon` (для уведомления о продлении)
- `orders`:
  - editable: `false`
  - creatable: `false`
  - доступен просмотр и удаление

---

## 8) Тестовые данные (seed)

`DatabaseSeeder` запускает:

- `AdminSeeder`
- `PlanSeeder`
- `NodeSeeder`
- `DemoUserSeeder`

### Тестовый пользователь

- email: `demo@auralith.test`
- password: `demo12345`

### Тестовый админ

- username: `admin`
- password: `admin123`

---

## 9) Локальный запуск

```bash
cd "c:\Work Folder\auralith\app"
php artisan migrate:fresh --seed
php artisan serve --host=127.0.0.1 --port=8082
```

URL:

- сайт: `http://127.0.0.1:8082`
- профиль: `http://127.0.0.1:8082/profile`
- админка: `http://127.0.0.1:8082/admin/login`

---

## 10) Полезные команды

Очистка кешей:

```bash
php artisan optimize:clear
php artisan config:clear
php artisan route:clear
php artisan view:clear
php artisan cache:clear
```

---

## 11) Документация по админке

Детальная документация по admin-контурy:

- `README_ADMIN_PANEL.md`

---

## 12) Дальнейшая доработка

Рекомендуемые шаги:

1. Вынести бизнес-логику из контроллеров в сервисы.
2. Добавить строгие `FormRequest` для CRUD.
3. Добавить RBAC (`super_admin`, `operator`, `readonly`).
4. Добавить audit-log изменений.
5. Реализовать scheduler для авто-статуса `expiring_soon` и уведомлений.
