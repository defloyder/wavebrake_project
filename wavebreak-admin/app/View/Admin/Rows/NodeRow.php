<?php

namespace App\View\Admin\Rows;

use App\Support\DisplayDate;
use App\View\Admin\StatusBadge;

final readonly class NodeRow
{
    public function __construct(
        public string $code,
        public string $region,
        public StatusBadge $status,
        public int $desired,
        public int $applied,
        public bool $inSync,
        public string $heartbeat,
        public string $heartbeatAgo,
        public string $heartbeatSort,
        public ?string $syncError,
    ) {}

    /** @param array<string, mixed> $node Core node */
    public static function fromCore(array $node): self
    {
        $desired = (int) ($node['desired_revision'] ?? 0);
        $applied = (int) ($node['applied_revision'] ?? 0);

        return new self(
            code: (string) ($node['code'] ?? '—'),
            region: (string) ($node['region'] ?? '—'),
            status: StatusBadge::node($node['status'] ?? null),
            desired: $desired,
            applied: $applied,
            inSync: $desired === $applied,
            heartbeat: DisplayDate::dateTime($node['last_heartbeat_at'] ?? null, 'нет'),
            heartbeatAgo: DisplayDate::relative($node['last_heartbeat_at'] ?? null),
            heartbeatSort: DisplayDate::sortKey($node['last_heartbeat_at'] ?? null),
            syncError: ($node['last_sync_error'] ?? null) ?: null,
        );
    }

    public function search(): string
    {
        return "{$this->code} {$this->region} {$this->status->label}";
    }
}
