<?php

namespace App\View\Admin\Rows;

use App\Support\DisplayDate;
use App\View\Admin\AdminDirectory;
use App\View\Admin\StatusBadge;

final readonly class DeviceRow
{
    private const PLATFORMS = [
        'android' => 'Android',
        'ios' => 'iOS',
        'windows' => 'Windows',
        'macos' => 'macOS',
        'linux' => 'Linux',
    ];

    public function __construct(
        public string $id,
        public string $userId,
        public string $user,
        public string $name,
        public string $platform,
        public StatusBadge $status,
        public string $lastSeen,
        public string $lastSeenAgo,
        public string $lastSeenSort,
        public string $createdAt,
    ) {}

    /** @param array<string, mixed> $device Core device */
    public static function fromCore(array $device, ?AdminDirectory $dir = null): self
    {
        $userId = (string) ($device['user_id'] ?? '');

        return new self(
            id: (string) $device['id'],
            userId: $userId,
            user: $dir?->userLabel($userId) ?? '',
            name: (string) (($device['name'] ?? '') ?: 'Устройство'),
            platform: self::platform($device['platform'] ?? null),
            status: StatusBadge::device($device['revoked_at'] ?? null, $device['status'] ?? null),
            lastSeen: DisplayDate::dateTime($device['last_seen_at'] ?? null, 'нет данных'),
            lastSeenAgo: DisplayDate::relative($device['last_seen_at'] ?? null, 'нет данных'),
            lastSeenSort: DisplayDate::sortKey($device['last_seen_at'] ?? null),
            createdAt: DisplayDate::date($device['created_at'] ?? null),
        );
    }

    public static function platform(?string $platform): string
    {
        return $platform ? (self::PLATFORMS[strtolower($platform)] ?? $platform) : '—';
    }

    public function isActive(): bool
    {
        return $this->status->tone === 'ok';
    }

    public function search(): string
    {
        return "{$this->user} {$this->name} {$this->platform}";
    }
}
