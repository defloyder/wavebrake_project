<?php

namespace App\Services\UserAdministration;

use App\Services\Core\CoreApiException;

/**
 * Maps Core errors to messages an operator can act on, so the UI never
 * shows a raw exception. Understands the domain codes of the account API
 * and the plain-text errors of the older admin endpoints.
 */
final class CoreErrorMessages
{
    private const MESSAGES = [
        'USER_NOT_FOUND' => 'Пользователь не найден.',
        'PLAN_NOT_FOUND' => 'Тариф не найден.',
        'PLAN_INACTIVE' => 'Тариф неактивен — выберите активный тариф.',
        'SUBSCRIPTION_ALREADY_ACTIVE' => 'У пользователя уже есть активная подписка.',
        'SUBSCRIPTION_CREATE_FAILED' => 'Не удалось создать подписку. Попробуйте ещё раз.',
        'SUBSCRIPTION_NOT_FOUND' => 'У пользователя нет подписки.',
        'SUBSCRIPTION_NOT_ACTIVE' => 'Доступ выдаётся только для активной, не истёкшей подписки.',
        'ACCESS_ISSUE_FAILED' => 'Не удалось выдать доступ. Попробуйте ещё раз.',
        'NO_NODE_AVAILABLE' => 'Нет доступной ноды для выдачи доступа.',
        'PASSWORD_RESET_CHANNEL_UNAVAILABLE' => 'У пользователя нет email — ссылку для восстановления отправить некуда.',
        'PASSWORD_RESET_FAILED' => 'Не удалось создать ссылку для восстановления пароля.',
        'DEVICE_LIMIT_REACHED' => 'Достигнут лимит устройств.',
        'TRAFFIC_LIMIT_REACHED' => 'Трафик по подписке исчерпан.',
        'VALIDATION_FAILED' => 'Проверьте заполнение формы.',
        'INTERNAL_ERROR' => 'Внутренняя ошибка Core. Повторите попытку позже.',
    ];

    /** Plain-text errors of the older Core admin endpoints. */
    private const LEGACY = [
        'email or username already exists' => 'Пользователь с таким email или username уже существует.',
        'cannot delete current user' => 'Нельзя удалить собственную учётную запись.',
        'only a superadmin can grant the superadmin role' => 'Роль «Суперадмин» может выдать только суперадмин.',
        'invalid role' => 'Недопустимая роль.',
        'invalid subscription status' => 'Недопустимый статус подписки.',
        'user not found' => 'Пользователь не найден.',
        'plan not found' => 'Тариф не найден.',
        'subscription not found' => 'Подписка не найдена.',
        'device not found' => 'Устройство не найдено.',
        'grant not found' => 'Ключ доступа не найден.',
        'subscription has no active grant to reissue' => 'У подписки нет ключа — сначала выдайте доступ.',
        'could not update user' => 'Не удалось сохранить пользователя.',
        'could not create user' => 'Не удалось создать пользователя.',
        'could not update subscription' => 'Не удалось изменить подписку.',
        'could not delete subscription' => 'Не удалось отменить подписку.',
        'could not reissue subscription link' => 'Не удалось перевыпустить ссылку.',
        'could not revoke grant' => 'Не удалось отозвать ключ.',
        'could not create plan' => 'Не удалось создать тариф.',
        'could not update plan' => 'Не удалось сохранить тариф.',
        'code, name, price_minor and device_limit are required' => 'Заполните код, название, цену и лимит устройств.',
        'interval must be month or year' => 'Период тарифа — месяц или год.',
        'could not enroll node' => 'Не удалось зарегистрировать ноду.',
    ];

    public function for(CoreApiException $e): string
    {
        if ($e->isUnauthenticated()) {
            return 'Сессия истекла, войдите снова.';
        }

        $message = self::MESSAGES[$e->errorCode]
            ?? self::LEGACY[$e->errorCode]
            ?? ($e->status === 403 ? 'Недостаточно прав для этого действия.' : 'Не удалось выполнить действие.');

        return $e->requestId ? "{$message} (request {$e->requestId})" : $message;
    }
}
