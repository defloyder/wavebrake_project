<?php

namespace App\Services\UserAdministration;

use App\Support\ByteFormatter;

/**
 * Read model of GET /v1/admin/users/{id} for the user modal. Only
 * presentation helpers live here; every number is computed by Core.
 */
final readonly class UserDetails
{
    /** @param array<string, mixed> $data */
    public function __construct(private array $data) {}

    /** @return array<string, mixed> */
    public function user(): array
    {
        return $this->data['user'] ?? [];
    }

    /** @return array<string, mixed>|null */
    public function subscription(): ?array
    {
        return $this->data['subscription'] ?? null;
    }

    public function hasSubscription(): bool
    {
        return $this->subscription() !== null;
    }

    /** @return array<string, mixed>|null */
    public function plan(): ?array
    {
        return $this->subscription()['plan'] ?? null;
    }

    /** @return array<string, mixed> */
    public function access(): array
    {
        return $this->data['access'] ?? ['grants' => [], 'active_grants' => 0];
    }

    /** @return array<string, mixed>|null */
    public function traffic(): ?array
    {
        return $this->data['traffic'] ?? null;
    }

    /** @return array<string, mixed> */
    public function devices(): array
    {
        return $this->data['devices'] ?? ['registered' => 0, 'limit' => null, 'items' => []];
    }

    public function activeConnections(): ?int
    {
        $active = $this->data['connections']['active'] ?? null;

        return is_int($active) ? $active : null;
    }

    public function trafficUsed(): string
    {
        return ByteFormatter::format((int) ($this->traffic()['bytes_total'] ?? 0));
    }

    public function trafficLimit(): string
    {
        $limit = $this->traffic()['limit_bytes'] ?? null;

        return $limit === null ? 'Безлимит' : ByteFormatter::format((int) $limit);
    }

    public function trafficRemaining(): string
    {
        $remaining = $this->traffic()['remaining_bytes'] ?? null;

        return $remaining === null ? '—' : ByteFormatter::format((int) $remaining);
    }

    public function usedPercent(): ?float
    {
        $pct = $this->traffic()['used_percent'] ?? null;

        return $pct === null ? null : (float) $pct;
    }

    public function devicesLabel(): string
    {
        $devices = $this->devices();
        $limit = $devices['limit'] ?? null;

        return ($devices['registered'] ?? 0).' / '.($limit === null ? '—' : $limit);
    }

    /** Masked for display; the full value is only copied on explicit action. */
    public function maskedSubscriptionUrl(): string
    {
        $url = (string) ($this->access()['subscription_url'] ?? '');
        if ($url === '') {
            return '';
        }
        $slash = strrpos($url, '/');
        if ($slash === false) {
            return '••••';
        }
        $credential = substr($url, $slash + 1);

        return substr($url, 0, $slash + 1).substr($credential, 0, 4).'••••'.substr($credential, -4);
    }

    /** @return array<string, mixed> */
    public function toArray(): array
    {
        return $this->data;
    }
}
