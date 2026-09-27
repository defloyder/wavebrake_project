<?php

namespace App\View\Admin\Rows;

use App\Support\ByteFormatter;
use App\Support\DisplayDate;
use App\View\Admin\AdminDirectory;
use App\View\Admin\StatusBadge;

/** One line of the Subscriptions table; the row opens its owner's card. */
final readonly class SubscriptionRow
{
    private const SOURCES = [
        'admin' => 'Админ',
        'admin_manual' => 'Админ',
        'purchase' => 'Покупка',
        'app' => 'Приложение',
        'web' => 'Приложение / сайт',
        'trial' => 'Пробный период',
        'telegram' => 'Telegram',
        'promo' => 'Промокод',
    ];

    public function __construct(
        public string $id,
        public string $userId,
        public string $user,
        public string $plan,
        public StatusBadge $status,
        public string $source,
        public string $used,
        public int $usedBytes,
        public string $limit,
        public ?float $usedPercent,
        public string $devices,
        public string $endsAt,
        public string $endsSort,
        public ?int $daysLeft,
        public bool $hasAccess,
        public string $filter,
    ) {}

    /**
     * @param  array<string, mixed>  $sub  Core /v1/admin/subscriptions item
     * @param  array<string, mixed>|null  $usage  Core /v1/admin/traffic row for it
     */
    public static function fromCore(array $sub, ?array $usage, bool $hasAccess, AdminDirectory $dir): self
    {
        $limit = $sub['traffic_limit_override_bytes'] ?? $sub['traffic_limit_bytes_snapshot'] ?? null;
        $used = (int) ($usage['bytes_total'] ?? 0);
        $devices = $sub['device_limit_override'] ?? $sub['device_limit_snapshot'] ?? null;
        $status = (string) ($sub['status'] ?? '');
        $end = $sub['current_period_end'] ?? null;

        return new self(
            id: (string) $sub['id'],
            userId: (string) ($sub['user_id'] ?? ''),
            user: $dir->userLabel($sub['user_id'] ?? null),
            plan: $dir->planName($sub['plan_id'] ?? null, $sub['source'] ?? null),
            status: StatusBadge::subscription($status),
            source: self::SOURCES[$sub['source'] ?? ''] ?? (string) ($sub['source'] ?? '—'),
            used: ByteFormatter::format($used),
            usedBytes: $used,
            limit: ByteFormatter::format($limit === null ? null : (int) $limit),
            usedPercent: $limit ? min(100.0, round($used / max(1, (int) $limit) * 100, 1)) : null,
            devices: $devices === null ? '—' : (string) $devices,
            endsAt: DisplayDate::date($end),
            endsSort: DisplayDate::sortKey($end),
            daysLeft: DisplayDate::daysLeft($end),
            hasAccess: $hasAccess,
            filter: implode(' ', [
                in_array($status, ['active', 'trialing'], true) ? 'live' : (in_array($status, ['past_due', 'suspended', 'pending'], true) ? 'attention' : 'ended'),
                $hasAccess ? 'with-access' : 'no-access',
            ]),
        );
    }

    public function search(): string
    {
        return "{$this->user} {$this->plan} {$this->status->label} {$this->id}";
    }
}
