# Auralith Core API: единый endpoint синхронизации

Документ для Core API-разработчика. Цель: заменить россыпь отдельных Core endpoint'ов единым контрактом, через который Laravel может мгновенно создавать, обновлять, удалять и получать актуальное состояние сущностей, а Core может мгновенно сообщать Laravel об изменениях со своей стороны.

## Что нужно решить

Сейчас Laravel использует разные Core endpoint'ы:

- `POST /auth/telegram`
- `GET /auth/me`
- `POST /auth/trial`
- `GET /auth/bonus`
- `GET /auth/referral`
- `GET /sub/{token}/status`
- `POST /payments/create`
- `POST /payments/apply_promo`
- `POST /payments/cp/cancel-subscription`
- `GET /admin/stats`
- `GET /admin/users`
- `GET /admin/nodes`
- `GET /admin/orders`
- `GET /admin/cp-orders`
- `POST /admin/subscriptions/{user_id}/extend`
- `POST /admin/users/telegram/{telegram_id}/subscription/extend`
- `POST /webhook/sync-user`
- `POST /admin/promo-codes`
- `POST /admin/promo-codes/{code}/delete`

Также Core сейчас отправляет данные в Laravel разными webhook'ами:

- `POST /api/webhook/sync-user`
- `POST /api/webhook/sync-subscription`
- `POST /api/webhook/telegram-link`
- `POST /api/webhook/password-change-confirm`
- `POST /webhook/telegram-recovery`

Нужно привести это к единой схеме: один Core endpoint для команд из Laravel и один Laravel webhook для событий из Core.

## Предлагаемый контракт

### Core endpoint

```http
POST /api/sync
Content-Type: application/json
X-Admin-Key: <admin_key>
X-Request-Id: <uuid>
```

Если фактический endpoint уже создан под другим путём, оставить путь Core, но сохранить структуру payload/response ниже.

### Laravel webhook для обратной синхронизации

```http
POST https://auralith.ru/api/webhook/core-sync
Content-Type: application/json
X-Core-Signature: <hmac-sha256>
X-Request-Id: <uuid>
```

Laravel потом заменит старые webhook'и на этот единый обработчик.

## Общий формат запроса Laravel -> Core

```json
{
  "version": 1,
  "request_id": "uuid",
  "source": "laravel",
  "resource": "subscriptions",
  "action": "upsert",
  "occurred_at": "2026-05-13T12:00:00+03:00",
  "actor": {
    "type": "admin",
    "id": 1
  },
  "identity": {
    "laravel_user_id": 505,
    "core_user_id": 123,
    "telegram_id": 781726353,
    "token": "user-token",
    "client_uuid": "uuid"
  },
  "payload": {},
  "meta": {
    "reason": "admin_panel",
    "idempotency_key": "uuid"
  }
}
```

Обязательные поля: `version`, `request_id`, `source`, `resource`, `action`, `occurred_at`, `payload`.

Core должен обрабатывать запрос идемпотентно по `request_id` или `meta.idempotency_key`: повтор одного и того же запроса не должен создавать дубль подписки, заказа, пользователя или промокода.

## Общий формат ответа Core -> Laravel

```json
{
  "ok": true,
  "request_id": "uuid",
  "resource": "subscriptions",
  "action": "upsert",
  "result": {
    "created": false,
    "updated": true,
    "deleted": false
  },
  "data": {},
  "sync_events": []
}
```

При ошибке:

```json
{
  "ok": false,
  "request_id": "uuid",
  "error": {
    "code": "VALIDATION_ERROR",
    "message": "plan_id is required",
    "details": {
      "field": "plan_id"
    }
  }
}
```

Laravel будет считать синхронизацию успешной только если HTTP `2xx` и `ok: true`.

## Поддерживаемые resources/actions

### `auth`

Нужно перенести текущую авторизацию через Telegram в единый endpoint.

#### `auth.telegram_login`

Замена `POST /auth/telegram`.

```json
{
  "resource": "auth",
  "action": "telegram_login",
  "payload": {
    "telegram_id": 12345,
    "username": "username"
  }
}
```

Ответ:

```json
{
  "ok": true,
  "data": {
    "core_user_id": 123,
    "telegram_id": 12345,
    "username": "username",
    "token": "user-token",
    "client_uuid": "uuid",
    "trial_used": false,
    "has_active_subscription": true,
    "subscription": {}
  }
}
```

Важно: если пользователь уже есть, возвращать существующего пользователя, а не создавать дубль.

### `users`

Нужны действия:

- `get`
- `list`
- `upsert`
- `delete`
- `unlink_telegram`
- `set_password_state`

#### `users.upsert`

Используется при создании/редактировании пользователя в Laravel и при привязке Telegram.

```json
{
  "resource": "users",
  "action": "upsert",
  "identity": {
    "laravel_user_id": 505,
    "telegram_id": 781726353,
    "token": "token",
    "client_uuid": "uuid"
  },
  "payload": {
    "name": "deniz",
    "username": "deniz",
    "telegram_id": 781726353,
    "token": "token",
    "client_uuid": "uuid",
    "trial_used": false,
    "has_password": true,
    "receives_payment_notifications": true
  }
}
```

Core должен:

- искать пользователя по `telegram_id`, `token`, `core_user_id` или `laravel_user_id`;
- обновлять существующего;
- создавать нового только если совпадений нет;
- возвращать `core_user_id`, `token`, `client_uuid`, актуальный `trial_used`.

#### `users.delete`

```json
{
  "resource": "users",
  "action": "delete",
  "identity": {
    "laravel_user_id": 505,
    "core_user_id": 123,
    "telegram_id": 781726353
  },
  "payload": {
    "delete_subscriptions": true,
    "delete_orders": false
  }
}
```

Удаление должно быть предсказуемым: либо soft-delete, либо hard-delete, но Core должен вернуть финальное состояние. Если hard-delete невозможен из-за заказов, вернуть `ok:false` с `CONFLICT`.

### `subscriptions`

Критичный раздел. Именно здесь сейчас появляются рассинхроны между админкой, ботом, профилем и subscription URL.

Нужны действия:

- `get_status`
- `upsert`
- `extend`
- `cancel`
- `delete`
- `list`

#### `subscriptions.get_status`

Замена `GET /sub/{token}/status`.

```json
{
  "resource": "subscriptions",
  "action": "get_status",
  "identity": {
    "token": "user-token"
  },
  "payload": {}
}
```

Ответ должен поддерживать безлимитную подписку:

```json
{
  "ok": true,
  "data": {
    "is_active": true,
    "is_unlimited": true,
    "expires_at": null,
    "days_left": null,
    "plan_id": null,
    "plan_name": "Advanced",
    "node_name": "NL1",
    "subscription_url": "https://auralith.ru/sub/token",
    "client_uuid": "uuid"
  }
}
```

Если подписки нет: HTTP `200`, `ok:true`, `data.is_active:false`. Не надо отдавать `404` для нормального состояния "нет подписки".

#### `subscriptions.upsert`

Используется при выдаче подписки из админки Laravel.

```json
{
  "resource": "subscriptions",
  "action": "upsert",
  "identity": {
    "laravel_user_id": 505,
    "core_user_id": 123,
    "telegram_id": 781726353,
    "token": "user-token"
  },
  "payload": {
    "laravel_subscription_id": 777,
    "plan_id": 3,
    "plan_duration_months": 3,
    "status": "active",
    "starts_at": "2026-05-13T12:00:00+03:00",
    "ends_at": "2026-08-13T12:00:00+03:00",
    "is_unlimited": false,
    "node_id": null,
    "source": "admin_panel"
  }
}
```

Для безлимитной:

```json
{
  "status": "active",
  "ends_at": null,
  "is_unlimited": true
}
```

Core должен:

- найти пользователя;
- если пользователя нет, создать/вернуть ошибку с понятным кодом `USER_NOT_FOUND`;
- создать или обновить активную подписку;
- не ломаться при `ends_at: null`;
- вернуть актуальную подписку, `subscription_url`, `client_uuid`, `token`.

#### `subscriptions.extend`

Замена:

- `POST /admin/subscriptions/{user_id}/extend`
- `POST /admin/users/telegram/{telegram_id}/subscription/extend`
- `POST /admin/subscriptions/telegram/{telegram_id}/extend`

```json
{
  "resource": "subscriptions",
  "action": "extend",
  "identity": {
    "telegram_id": 781726353,
    "token": "user-token"
  },
  "payload": {
    "days": 30,
    "plan_id": 1,
    "source": "cloudpayments"
  }
}
```

Ответ должен вернуть финальную дату, а не только `ok`.

#### `subscriptions.cancel`

Замена `POST /payments/cp/cancel-subscription`.

```json
{
  "resource": "subscriptions",
  "action": "cancel",
  "identity": {
    "token": "user-token"
  },
  "payload": {
    "cancel_provider_subscription": true,
    "reason": "user_request"
  }
}
```

Core должен отменить recurring-подписку CloudPayments, если она есть, и вернуть локальное состояние подписки.

#### `subscriptions.delete`

Используется при удалении подписки в админке. Core должен удалить/деактивировать запись и мгновенно отправить событие обратно в Laravel.

### `plans`

Нужны действия:

- `list`
- `upsert`
- `delete`

Laravel управляет тарифами: `name`, `duration_months`, `price_rub`, `headline`, `is_highlighted`, `features`.

```json
{
  "resource": "plans",
  "action": "upsert",
  "payload": {
    "laravel_plan_id": 3,
    "name": "3 месяца",
    "duration_months": 3,
    "price_rub": 449,
    "headline": "Оптимальный план",
    "features": ["Безлимитный трафик"],
    "is_highlighted": true,
    "is_active": true
  }
}
```

Core должен хранить связь `laravel_plan_id` <-> `core_plan_id` или использовать `duration_months` как стабильный ключ, если Core так устроен.

### `nodes`

Нужны действия:

- `list`
- `upsert`
- `delete`
- `health`

Замена `GET /admin/nodes` и будущих CRUD-операций нод.

```json
{
  "resource": "nodes",
  "action": "upsert",
  "payload": {
    "laravel_node_id": 1,
    "name": "NL1",
    "ip": "1.2.3.4",
    "port": 443,
    "api_port": 8443,
    "api_secret": "secret",
    "status": "online",
    "latency": 28,
    "load": 0.31,
    "errors": 0,
    "is_active": true
  }
}
```

### `orders`

Нужны действия:

- `list`
- `get`
- `upsert`
- `mark_paid`
- `mark_failed`
- `delete`

Замена `GET /admin/orders`, `GET /admin/cp-orders`, частично CloudPayments/Freekassa синхронизации.

```json
{
  "resource": "orders",
  "action": "upsert",
  "identity": {
    "telegram_id": 781726353,
    "token": "user-token"
  },
  "payload": {
    "invoice_id": "CP-123",
    "transaction_id": "tx_123",
    "provider": "cloudpayments",
    "user_id": 505,
    "plan_id": 3,
    "promo_code": "SALE10",
    "amount": 449,
    "discount_amount": 50,
    "original_amount": 499,
    "currency": "RUB",
    "payment_method": "cloudpayments",
    "status": "paid",
    "paid_at": "2026-05-13T12:00:00+03:00",
    "failed_at": null,
    "raw_payload": {}
  }
}
```

При смене статуса заказа Core должен отправить Laravel обратное событие `orders.updated`, чтобы админка и статистика обновлялись мгновенно.

### `promo_codes`

Нужны действия:

- `list`
- `upsert`
- `delete`
- `apply`

Замена:

- `POST /admin/promo-codes`
- `POST /admin/promocodes`
- `POST /admin/promos`
- `POST /admin/promo-codes/{code}/delete`
- `POST /payments/apply_promo`

```json
{
  "resource": "promo_codes",
  "action": "upsert",
  "payload": {
    "code": "SALE10",
    "type": "percent",
    "value": 10,
    "is_active": true,
    "starts_at": "2026-05-13T00:00:00+03:00",
    "expires_at": "2026-06-13T00:00:00+03:00",
    "max_uses": 100,
    "used_count": 0
  }
}
```

Для удаления:

```json
{
  "resource": "promo_codes",
  "action": "delete",
  "payload": {
    "code": "SALE10"
  }
}
```

### `payments`

Нужны действия:

- `create`
- `apply_promo`
- `cancel_recurring`
- `get_status`

Замена `POST /payments/create`, `POST /payments/apply_promo`, `POST /payments/cp/cancel-subscription`.

```json
{
  "resource": "payments",
  "action": "create",
  "identity": {
    "token": "user-token",
    "telegram_id": 781726353
  },
  "payload": {
    "plan_id": 3,
    "payment_method": "cloudpayments",
    "promocode": "SALE10",
    "return_url": "https://auralith.ru/payment/success",
    "fail_url": "https://auralith.ru/payment/fail"
  }
}
```

Ответ:

```json
{
  "ok": true,
  "data": {
    "invoice_id": "CP-123",
    "payment_url": "https://...",
    "amount": 449,
    "currency": "RUB"
  }
}
```

### `trial`

Нужны действия:

- `activate`
- `status`

Замена `POST /auth/trial`.

```json
{
  "resource": "trial",
  "action": "activate",
  "identity": {
    "token": "user-token",
    "telegram_id": 781726353
  },
  "payload": {}
}
```

Core должен вернуть:

- `trial_used`;
- созданную подписку;
- `expires_at`;
- `is_active`;
- `subscription_url`.

### `bonus`

Нужны действия:

- `get_balance`
- `list_history`
- `accrue`
- `spend`

Замена `GET /auth/bonus`.

```json
{
  "resource": "bonus",
  "action": "get_balance",
  "identity": {
    "token": "user-token"
  },
  "payload": {}
}
```

Ответ:

```json
{
  "ok": true,
  "data": {
    "balance": 100,
    "history": [
      {
        "amount": 100,
        "type": "referral",
        "created_at": "2026-05-13T12:00:00+03:00"
      }
    ]
  }
}
```

### `referral`

Нужны действия:

- `get`
- `register_referral`
- `reward`

Замена `GET /auth/referral`.

```json
{
  "resource": "referral",
  "action": "get",
  "identity": {
    "token": "user-token"
  },
  "payload": {}
}
```

Ответ:

```json
{
  "ok": true,
  "data": {
    "referral_link": "https://t.me/auralithaccessbot?start=ref_xxx",
    "invited_count": 2,
    "total_accrued": 150,
    "items": []
  }
}
```

### `telegram`

Нужны действия:

- `link`
- `unlink`
- `login_link`
- `recovery_confirm`
- `password_change_send`
- `password_change_confirm`

#### `telegram.link`

Замена старой связки `POST /api/webhook/telegram-link` и отдельных link-token проверок.

```json
{
  "resource": "telegram",
  "action": "link",
  "payload": {
    "link_token": "uuid",
    "telegram_id": 12345,
    "username": "username"
  }
}
```

Повторная привязка того же `telegram_id` к тому же аккаунту должна возвращать `ok:true`, а не `409`.

#### `telegram.password_change_send`

Замена отдельного `POST /auth/password-change/send`.

```json
{
  "resource": "telegram",
  "action": "password_change_send",
  "identity": {
    "telegram_id": 12345
  },
  "payload": {
    "pwd_token": "uuid"
  }
}
```

Core отправляет сообщение в Telegram с кнопками "Подтвердить" и "Отменить".

#### `telegram.password_change_confirm`

Core должен отправить Laravel событие:

```json
{
  "resource": "password_change",
  "action": "confirmed",
  "payload": {
    "pwd_token": "uuid",
    "action": "confirm"
  }
}
```

Для отмены:

```json
{
  "resource": "password_change",
  "action": "cancelled",
  "payload": {
    "pwd_token": "uuid",
    "action": "cancel"
  }
}
```

## Обратные события Core -> Laravel

Core должен отправлять события на единый Laravel webhook сразу после успешного изменения у себя.

Формат:

```json
{
  "version": 1,
  "event_id": "uuid",
  "source": "core",
  "resource": "subscriptions",
  "action": "updated",
  "occurred_at": "2026-05-13T12:00:00+03:00",
  "identity": {
    "core_user_id": 123,
    "laravel_user_id": 505,
    "telegram_id": 781726353,
    "token": "user-token"
  },
  "payload": {}
}
```

События, которые обязательно нужны:

- `users.created`
- `users.updated`
- `users.deleted`
- `subscriptions.created`
- `subscriptions.updated`
- `subscriptions.cancelled`
- `subscriptions.deleted`
- `plans.created`
- `plans.updated`
- `plans.deleted`
- `nodes.created`
- `nodes.updated`
- `nodes.deleted`
- `orders.created`
- `orders.updated`
- `orders.paid`
- `orders.failed`
- `promo_codes.created`
- `promo_codes.updated`
- `promo_codes.deleted`
- `bonus.updated`
- `referral.updated`
- `telegram.linked`
- `telegram.unlinked`
- `password_change.confirmed`
- `password_change.cancelled`

Laravel должен отвечать:

```json
{
  "ok": true,
  "event_id": "uuid"
}
```

Core должен ретраить событие, если Laravel вернул не `2xx` или `ok:false`.

## Требования к мгновенной синхронизации

1. Любое создание/обновление/удаление в Laravel админке должно идти в Core через `POST /api/sync`.
2. Core должен выполнять операцию в транзакции.
3. Core должен вернуть финальное состояние изменённой сущности.
4. После изменения Core должен отправить обратное событие в Laravel.
5. Если Core не принял операцию, Laravel откатывает локальную запись.
6. Кроны `core:sync`, `orders:sync`, `nodes:sync`, `promo-codes:sync` остаются только как fallback/reconciliation, а не как основной механизм актуальности.

## Ошибки и коды

Нужны стабильные `error.code`:

- `VALIDATION_ERROR`
- `UNAUTHORIZED`
- `FORBIDDEN`
- `NOT_FOUND`
- `USER_NOT_FOUND`
- `SUBSCRIPTION_NOT_FOUND`
- `PLAN_NOT_FOUND`
- `DUPLICATE`
- `CONFLICT`
- `EXTERNAL_PROVIDER_ERROR`
- `TEMPORARY_UNAVAILABLE`

Для временных ошибок Core должен возвращать `503` или `429`, чтобы Laravel понимал, что можно повторить.

## Безопасность

Для Laravel -> Core:

- оставить `X-Admin-Key` для admin/system actions;
- для пользовательских действий можно принимать Bearer token пользователя, но единый endpoint всё равно должен понимать `identity.token`;
- все admin actions должны логироваться в Core.

Для Core -> Laravel:

- добавить `X-Core-Signature`;
- подпись считать как `hash_hmac('sha256', raw_body, CORE_WEBHOOK_SECRET)`;
- Laravel должен проверять подпись и `event_id` на идемпотентность.

## Минимальная очередность реализации на Core

1. `auth.telegram_login` — уже частично готово, привести к общему response.
2. `users.upsert`, `users.delete`, `users.list`.
3. `subscriptions.get_status`, `subscriptions.upsert`, `subscriptions.extend`, `subscriptions.cancel`, `subscriptions.delete`.
4. `plans.list/upsert/delete`.
5. `promo_codes.list/upsert/delete/apply`.
6. `orders.list/upsert/mark_paid/mark_failed`.
7. `nodes.list/upsert/delete/health`.
8. `payments.create/apply_promo/cancel_recurring`.
9. `trial.activate/status`.
10. `bonus.get_balance/list_history`, `referral.get`.
11. `telegram.link/unlink/password_change_send`.
12. Обратные события Core -> Laravel на единый webhook.

## Acceptance criteria

Решение считается готовым, когда:

- Laravel может создать пользователя через единый endpoint и сразу получить `core_user_id`, `token`, `client_uuid`.
- Laravel может выдать подписку из админки, бот сразу видит подписку, профиль сразу показывает подписку, subscription URL не даёт `404`.
- Безлимитная подписка возвращается с `is_unlimited:true`, `expires_at:null`, `days_left:null`.
- Редактирование подписки в Laravel моментально отражается в Core.
- Удаление подписки в Laravel моментально деактивирует её в Core.
- Создание/редактирование/удаление промокода идёт через единый endpoint.
- Заказы и статусы платежей синхронизируются событием, без ожидания минутного крона.
- Ноды и статистика админки могут быть получены через единый endpoint.
- Старые endpoint'ы можно оставить как deprecated adapters, но Laravel должен иметь возможность перейти на единый `/api/sync` без потери функциональности.
