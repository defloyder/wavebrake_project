<?php

namespace App\View\Admin;

/**
 * A status as the UI shows it: a Russian label and a tone (ok, warn, bad,
 * muted, info) that maps to .adm-badge--{tone}. Unknown values fall back
 * to the raw value with a muted tone instead of breaking the page.
 */
final readonly class StatusBadge
{
    private const SUBSCRIPTION = [
        'active' => ['Активна', 'ok'],
        'trialing' => ['Пробная', 'info'],
        'past_due' => ['Ожидает оплаты', 'warn'],
        'pending' => ['Ожидает', 'warn'],
        'suspended' => ['Приостановлена', 'warn'],
        'cancelled' => ['Отменена', 'bad'],
        'expired' => ['Истекла', 'bad'],
    ];

    private const NODE = [
        'online' => ['Онлайн', 'ok'],
        'offline' => ['Офлайн', 'bad'],
        'pending' => ['Ожидает', 'warn'],
        'draining' => ['Выводится', 'warn'],
    ];

    private const GRANT = [
        'active' => ['Активен', 'ok'],
        'revoked' => ['Отозван', 'bad'],
        'expired' => ['Истёк', 'muted'],
    ];

    private const ROLE = [
        'user' => ['Пользователь', 'muted'],
        'support' => ['Поддержка', 'info'],
        'admin' => ['Админ', 'info'],
        'superadmin' => ['Суперадмин', 'warn'],
    ];

    /** Statuses Core accepts from the admin subscription editor, in menu order. */
    public const SUBSCRIPTION_STATUSES = ['active', 'suspended', 'pending', 'cancelled', 'expired'];

    public const ROLES = ['user', 'support', 'admin', 'superadmin'];

    public function __construct(public string $label, public string $tone) {}

    public static function subscription(?string $status): self
    {
        return self::from(self::SUBSCRIPTION, $status);
    }

    public static function node(?string $status): self
    {
        return self::from(self::NODE, $status);
    }

    public static function grant(?string $status): self
    {
        return self::from(self::GRANT, $status);
    }

    public static function role(?string $role): self
    {
        return self::from(self::ROLE, $role ?: 'user');
    }

    /** @param array<string, mixed> $user Core user (status + disabled_at) */
    public static function user(array $user): self
    {
        $blocked = ! empty($user['disabled_at']) || ($user['status'] ?? 'active') === 'disabled';

        return $blocked ? new self('Заблокирован', 'bad') : new self('Активен', 'ok');
    }

    public static function device(?string $revokedAt, ?string $status = null): self
    {
        $revoked = ! empty($revokedAt) || $status === 'revoked';

        return $revoked ? new self('Отозвано', 'bad') : new self('Активно', 'ok');
    }

    public static function plan(bool $active): self
    {
        return $active ? new self('Активен', 'ok') : new self('Скрыт', 'muted');
    }

    public static function subscriptionLabel(string $status): string
    {
        return self::SUBSCRIPTION[$status][0] ?? $status;
    }

    public static function roleLabel(string $role): string
    {
        return self::ROLE[$role][0] ?? $role;
    }

    /** @param array<string, array{0: string, 1: string}> $map */
    private static function from(array $map, ?string $value): self
    {
        $value = (string) $value;
        [$label, $tone] = $map[$value] ?? [$value !== '' ? $value : '—', 'muted'];

        return new self($label, $tone);
    }
}
