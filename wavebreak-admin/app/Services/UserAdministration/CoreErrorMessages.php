<?php

namespace App\Services\UserAdministration;

use App\Services\Core\CoreApiException;

/**
 * Maps Core domain error codes to messages an operator can act on, so the
 * UI never shows a raw exception.
 */
final class CoreErrorMessages
{
    private const MESSAGES = [
        'USER_NOT_FOUND' => 'Пользователь не найден.',
        'PLAN_NOT_FOUND' => 'Тариф не найден.',
        'PLAN_INACTIVE' => 'Тариф неактивен — выберите активный тариф.',
        'SUBSCRIPTION_ALREADY_ACTIVE' => 'У пользователя уже есть активная подписка.',
        'SUBSCRIPTION_CREATE_FAILED' => 'Не удалось создать подписку. Попробуйте ещё раз.',
        'NO_NODE_AVAILABLE' => 'Нет доступной ноды для выдачи доступа.',
        'PASSWORD_RESET_CHANNEL_UNAVAILABLE' => 'У пользователя нет email — ссылку для восстановления отправить некуда.',
        'PASSWORD_RESET_FAILED' => 'Не удалось создать ссылку для восстановления пароля.',
        'DEVICE_LIMIT_REACHED' => 'Достигнут лимит устройств.',
        'VALIDATION_FAILED' => 'Проверьте заполнение формы.',
        'INTERNAL_ERROR' => 'Внутренняя ошибка Core. Повторите попытку позже.',
    ];

    public function for(CoreApiException $e): string
    {
        if ($e->isUnauthenticated()) {
            return 'Сессия истекла, войдите снова.';
        }
        if ($e->status === 403) {
            return 'Недостаточно прав для этого действия.';
        }

        $message = self::MESSAGES[$e->errorCode] ?? 'Не удалось выполнить действие.';

        return $e->requestId ? "{$message} (request {$e->requestId})" : $message;
    }
}
