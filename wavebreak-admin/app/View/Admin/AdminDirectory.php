<?php

namespace App\View\Admin;

/**
 * Resolves the ids Core returns in list endpoints into what an operator
 * recognises: users by email, plans by name, nodes by code. Built once per
 * page from the lists that page already loaded.
 */
final class AdminDirectory
{
    /** Subscriptions issued without a plan (legacy manual form). */
    private const CUSTOM_PLAN_IDS = ['admin-custom'];

    /** @var array<string, array<string, mixed>> */
    private array $users;

    /** @var array<string, array<string, mixed>> */
    private array $plans;

    /** @var array<string, array<string, mixed>> */
    private array $nodes;

    /** @var array<string, array<string, mixed>> */
    private array $subscriptions;

    /**
     * @param  list<array<string, mixed>>  $users
     * @param  list<array<string, mixed>>  $plans
     * @param  list<array<string, mixed>>  $nodes
     * @param  list<array<string, mixed>>  $subscriptions
     */
    public function __construct(array $users = [], array $plans = [], array $nodes = [], array $subscriptions = [])
    {
        $this->users = self::index($users);
        $this->plans = self::index($plans);
        $this->nodes = self::index($nodes);
        $this->subscriptions = self::index($subscriptions);
    }

    /** @return array<string, mixed>|null */
    public function user(?string $id): ?array
    {
        return $id === null ? null : ($this->users[$id] ?? null);
    }

    public function userLabel(?string $id): string
    {
        if ($id === null || $id === '') {
            return '—';
        }
        $user = $this->users[$id] ?? null;
        if ($user === null) {
            return self::shortId($id);
        }

        return ($user['email'] ?? '') ?: (($user['username'] ?? '') ?: self::shortId($id));
    }

    public function planName(?string $planId, ?string $source = null): string
    {
        if ($planId === null || $planId === '' || in_array($planId, self::CUSTOM_PLAN_IDS, true) || $source === 'admin_manual') {
            return 'Индивидуальная';
        }
        $plan = $this->plans[$planId] ?? null;

        return $plan === null ? 'Тариф удалён' : (string) ($plan['name'] ?? $plan['code'] ?? 'Тариф');
    }

    public function nodeLabel(?string $nodeId): string
    {
        if ($nodeId === null || $nodeId === '') {
            return '—';
        }
        $node = $this->nodes[$nodeId] ?? null;

        return $node === null ? self::shortId($nodeId) : (string) ($node['code'] ?? self::shortId($nodeId));
    }

    /** @return array<string, mixed>|null */
    public function subscription(?string $id): ?array
    {
        return $id === null ? null : ($this->subscriptions[$id] ?? null);
    }

    public static function shortId(string $id): string
    {
        return strlen($id) > 8 ? substr($id, 0, 8).'…' : $id;
    }

    /**
     * @param  list<array<string, mixed>>  $rows
     * @return array<string, array<string, mixed>>
     */
    private static function index(array $rows): array
    {
        $out = [];
        foreach ($rows as $row) {
            if (isset($row['id'])) {
                $out[(string) $row['id']] = $row;
            }
        }

        return $out;
    }
}
