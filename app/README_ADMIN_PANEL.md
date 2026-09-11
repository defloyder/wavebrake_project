# Auralith Admin Panel README

Актуальная техническая документация по админ-панели `Auralith` с учетом последних изменений.

## 1) Назначение

Админ-панель реализует:

- изолированную авторизацию в контуре `/admin/*`;
- dashboard с операционной статистикой и мониторингом нод;
- CRUD/просмотр основных доменных сущностей;
- основу для дальнейшей интеграции с Core API.

Важно: вход через пользовательский `/login` не дает доступ в `/admin`.

---

## 2) Стек

- `Laravel 13`
- UI: `Bootstrap 5`, `Chart.js`, `Simple-DataTables`
- DB (локально): `SQLite`
- Auth: custom session (`admin_id`) + middleware alias `admin`

---

## 3) Роуты админки

Префикс всех маршрутов: `/admin`.

### Auth

- `GET /admin/login`
- `POST /admin/login`
- `POST /admin/logout`

### Dashboard

- `GET /admin`

### Ресурсы

- `GET /admin/{resource}` — список записей
- `GET /admin/{resource}/{id}` — **просмотр записи** (кнопка `Просмотреть`)
- `GET /admin/{resource}/create` — создание (если разрешено)
- `POST /admin/{resource}` — сохранение новой записи
- `GET /admin/{resource}/{id}/edit` — редактирование (если разрешено)
- `PUT /admin/{resource}/{id}` — обновление
- `DELETE /admin/{resource}/{id}` — удаление

Поддерживаемые ресурсы:

- `users`
- `plans`
- `nodes`
- `subscriptions`
- `orders`

---

## 4) Политика редактирования по ресурсам

Логика задается в `AdminPanelController::RESOURCES`.

### `subscriptions`

- редактирование разрешено;
- статус задается через `select` со значениями:
  - `active`
  - `inactive`
  - `expiring_soon` (статус для уведомления за 3 дня до конца подписки).

### `orders`

- редактирование отключено (`editable: false`);
- создание отключено (`creatable: false`);
- доступны просмотр и удаление.

---

## 5) UX в списках записей

- В `resource-index` используется кнопка `Просмотреть` для перехода на отдельную страницу записи (`/admin/{resource}/{id}`).
- Выезжающая панель (drawer) полностью удалена из реализации.
- Кнопка `Edit` из списков убрана; редактирование — через страницу просмотра (`Редактировать`), если ресурс редактируемый.

---

## 6) Мониторинг в хедере админки

В `admin/layout` добавлен верхний блок мониторинга:

- alive/total нод;
- средняя загрузка (`Avg Load`);
- чипы по каждой ноде (`name`, `status`, `load%`).

Данные формируются методом `serverHealth()` в `AdminPanelController`.

---

## 7) Изоляция авторизации

Админ-контур использует:

- таблицу `admins`;
- `AdminAuthController` для входа/выхода;
- `AdminOnly` middleware;
- сессионные ключи `admin_id`, `admin_name`.

Тестовый доступ:

- `username: admin`
- `password: admin123`

Seeder: `database/seeders/AdminSeeder.php`.

---

## 8) Основные файлы

### Backend

- `app/Http/Controllers/AdminAuthController.php`
- `app/Http/Controllers/AdminPanelController.php`
- `app/Http/Middleware/AdminOnly.php`
- `app/Models/Admin.php`
- `routes/web.php`
- `bootstrap/app.php`

### Views

- `resources/views/admin/login.blade.php`
- `resources/views/admin/layout.blade.php`
- `resources/views/admin/dashboard.blade.php`
- `resources/views/admin/resource-index.blade.php`
- `resources/views/admin/resource-show.blade.php`
- `resources/views/admin/resource-form.blade.php`

### DB

- `database/migrations/2026_04_22_102621_create_admins_table.php`
- `database/seeders/AdminSeeder.php`
- `database/seeders/DatabaseSeeder.php`

---

## 9) Локальный запуск

```bash
cd "c:\Work Folder\auralith\app"
php artisan migrate:fresh --seed
php artisan serve --host=127.0.0.1 --port=8082
```

Админка:

- `http://127.0.0.1:8082/admin/login`

---

## 10) Что важно доработать дальше

Рекомендуемый следующий этап:

1. Вынести операции админки в сервисный слой (`AdminStatsService`, `SubscriptionAdminService`, `NodeAdminService`).
2. Добавить строгую валидацию через `FormRequest` на create/update по каждому ресурсу.
3. Добавить RBAC (роли `super_admin`, `operator`, `readonly`).
4. Добавить audit-log (кто/когда/что изменил).
5. Добавить автоматическую установку `expiring_soon` (scheduled command по `ends_at`).
