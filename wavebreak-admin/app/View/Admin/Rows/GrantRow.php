<?php

namespace App\View\Admin\Rows;

use App\Support\DisplayDate;
use App\View\Admin\AdminDirectory;
use App\View\Admin\StatusBadge;

/** An issued access key (grant); the row opens its owner's card. */
final readonly class GrantRow
{
    public function __construct(
        public string $id,
        public string $label,
        public string $userId,
        public string $user,
        public string $node,
        public string $protocol,
        public StatusBadge $status,
        public string $kind,
        public string $createdAt,
        public string $createdSort,
        public string $expiresAt,
        public int $revision,
    ) {}

    /** @param array<string, mixed> $grant Core access grant */
    public static function fromCore(array $grant, AdminDirectory $dir): self
    {
        $id = (string) $grant['id'];

        return new self(
            id: $id,
            label: self::label($id),
            userId: (string) ($grant['user_id'] ?? ''),
            user: $dir->userLabel($grant['user_id'] ?? null),
            node: (string) (($grant['node_code'] ?? '') ?: $dir->nodeLabel($grant['node_id'] ?? null)),
            protocol: (string) ($grant['protocol'] ?? '—'),
            status: StatusBadge::grant($grant['status'] ?? null),
            kind: empty($grant['device_id']) ? 'Подписка' : 'Устройство',
            createdAt: DisplayDate::dateTime($grant['created_at'] ?? null),
            createdSort: DisplayDate::sortKey($grant['created_at'] ?? null),
            expiresAt: DisplayDate::date($grant['expires_at'] ?? null),
            revision: (int) ($grant['desired_revision'] ?? 0),
        );
    }

    /** Short human handle for a grant id, e.g. WVB-9C1D2E3F. */
    public static function label(string $grantId): string
    {
        return 'WVB-'.strtoupper(substr(str_replace('-', '', $grantId), 0, 8));
    }

    public function search(): string
    {
        return "{$this->user} {$this->label} {$this->node} {$this->protocol} {$this->status->label}";
    }
}
