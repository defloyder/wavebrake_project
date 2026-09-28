<?php

namespace App\View\Admin\Rows;

use App\Support\ByteFormatter;
use App\View\Admin\AdminDirectory;
use App\View\Admin\StatusBadge;

/** Per-subscription usage; the row opens the owner's card. */
final readonly class TrafficRow
{
    public function __construct(
        public string $userId,
        public string $user,
        public string $plan,
        public StatusBadge $status,
        public string $up,
        public string $down,
        public string $total,
        public int $totalBytes,
        public string $limit,
        public ?float $usedPercent,
    ) {}

    /** @param array<string, mixed> $row Core /v1/admin/traffic item */
    public static function fromCore(array $row, AdminDirectory $dir): self
    {
        $total = (int) ($row['bytes_total'] ?? 0);
        $limit = isset($row['limit_bytes']) ? (int) $row['limit_bytes'] : null;
        $sub = $dir->subscription($row['subscription_id'] ?? null);

        return new self(
            userId: (string) ($row['user_id'] ?? ''),
            user: $dir->userLabel($row['user_id'] ?? null),
            plan: $sub ? $dir->planName($sub['plan_id'] ?? null, $sub['source'] ?? null) : '—',
            status: StatusBadge::subscription($row['status'] ?? null),
            up: ByteFormatter::format((int) ($row['bytes_up'] ?? 0)),
            down: ByteFormatter::format((int) ($row['bytes_down'] ?? 0)),
            total: ByteFormatter::format($total),
            totalBytes: $total,
            limit: ByteFormatter::format($limit),
            usedPercent: $limit ? min(100.0, round($total / max(1, $limit) * 100, 1)) : null,
        );
    }

    public function search(): string
    {
        return "{$this->user} {$this->plan} {$this->status->label}";
    }
}
