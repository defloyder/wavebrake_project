<?php

namespace App\View\Admin\Rows;

use App\Support\DisplayDate;
use App\View\Admin\StatusBadge;

/** One line of the Users table; the whole row opens the user card. */
final readonly class UserRow
{
    public function __construct(
        public string $id,
        public string $email,
        public string $username,
        public StatusBadge $role,
        public StatusBadge $status,
        public ?string $planName,
        public ?StatusBadge $subscription,
        public string $subscriptionEnds,
        public string $lastLogin,
        public string $lastLoginSort,
        public string $createdAt,
        public string $createdSort,
        public string $filter,
    ) {}

    /** @param array<string, mixed> $user Core /v1/admin/users item */
    public static function fromCore(array $user): self
    {
        $sub = $user['subscription'] ?? null;
        $status = StatusBadge::user($user);
        $blocked = $status->tone === 'bad';

        return new self(
            id: (string) $user['id'],
            email: (string) (($user['email'] ?? '') ?: '—'),
            username: (string) ($user['username'] ?? ''),
            role: StatusBadge::role($user['role'] ?? 'user'),
            status: $status,
            planName: $sub ? (string) (($sub['plan_name'] ?? '') ?: 'Тариф') : null,
            subscription: $sub ? StatusBadge::subscription($sub['status'] ?? null) : null,
            subscriptionEnds: $sub ? DisplayDate::date($sub['current_period_end'] ?? null) : '',
            lastLogin: DisplayDate::dateTime($user['last_login_at'] ?? null, 'не входил'),
            lastLoginSort: DisplayDate::sortKey($user['last_login_at'] ?? null),
            createdAt: DisplayDate::date($user['created_at'] ?? null),
            createdSort: DisplayDate::sortKey($user['created_at'] ?? null),
            filter: implode(' ', array_filter([
                $sub ? 'with-sub' : 'no-sub',
                $blocked ? 'blocked' : 'enabled',
                ($user['role'] ?? 'user') !== 'user' ? 'staff' : null,
            ])),
        );
    }

    public function search(): string
    {
        return trim("{$this->email} {$this->username} {$this->id} {$this->planName}");
    }
}
