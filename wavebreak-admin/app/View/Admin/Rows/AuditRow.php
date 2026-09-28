<?php

namespace App\View\Admin\Rows;

use App\Support\DisplayDate;
use App\View\Admin\AdminDirectory;

/** A Core audit event in operator language. */
final readonly class AuditRow
{
    private const ACTIONS = [
        'user.created' => 'Создан пользователь',
        'user.updated' => 'Изменён пользователь',
        'user.role_updated' => 'Изменена роль',
        'user.disabled' => 'Пользователь заблокирован',
        'user.enabled' => 'Пользователь разблокирован',
        'user.delete_requested' => 'Пользователь удалён',
        'plan.created' => 'Создан тариф',
        'plan.updated' => 'Изменён тариф',
        'plan.deleted' => 'Удалён тариф',
        'subscription.created' => 'Создана подписка',
        'subscription.created_manual' => 'Создана подписка вручную',
        'subscription.edited' => 'Изменена подписка',
        'subscription.status_updated' => 'Изменён статус подписки',
        'subscription.usage_reset' => 'Сброшен трафик',
        'subscription.link_reissued' => 'Перевыпущена ссылка',
        'subscription.deleted' => 'Подписка отменена',
        'subscription_issued' => 'Выдана подписка',
        'access_created' => 'Выдан доступ',
        'access_grant.revoked' => 'Отозван ключ доступа',
        'device.revoked' => 'Отозвано устройство',
        'password_reset_requested' => 'Запрошен сброс пароля',
        'password_reset_completed' => 'Пароль изменён по ссылке',
    ];

    private const TARGETS = [
        'user' => 'Пользователь',
        'plan' => 'Тариф',
        'subscription' => 'Подписка',
        'access_grant' => 'Ключ',
        'device' => 'Устройство',
        'node' => 'Нода',
    ];

    public function __construct(
        public string $action,
        public string $actionCode,
        public string $target,
        public string $actor,
        public ?string $userId,
        public string $createdAt,
        public string $createdSort,
    ) {}

    /** @param array<string, mixed> $event Core audit event */
    public static function fromCore(array $event, AdminDirectory $dir): self
    {
        $type = (string) ($event['target_type'] ?? '');
        $targetId = $event['target_id'] ?? null;
        $metadata = is_array($event['metadata'] ?? null) ? $event['metadata'] : [];
        $userId = $event['target_user_id'] ?? ($type === 'user' ? $targetId : ($metadata['user_id'] ?? null));
        $userId = $userId !== null && $dir->user((string) $userId) !== null ? (string) $userId : null;

        $target = self::TARGETS[$type] ?? ($type ?: '—');
        if ($type === 'user' && $targetId) {
            $target .= ' · '.$dir->userLabel((string) $targetId);
        } elseif ($type === 'access_grant' && $targetId) {
            $target .= ' · '.GrantRow::label((string) $targetId);
        } elseif ($userId !== null) {
            $target .= ' · '.$dir->userLabel($userId);
        }

        return new self(
            action: self::ACTIONS[$event['action'] ?? ''] ?? (string) ($event['action'] ?? '—'),
            actionCode: (string) ($event['action'] ?? ''),
            target: $target,
            actor: empty($event['actor_user_id']) ? 'Система' : $dir->userLabel((string) $event['actor_user_id']),
            userId: $userId,
            createdAt: DisplayDate::dateTime($event['created_at'] ?? null),
            createdSort: DisplayDate::sortKey($event['created_at'] ?? null),
        );
    }

    public function search(): string
    {
        return "{$this->action} {$this->actionCode} {$this->target} {$this->actor}";
    }
}
