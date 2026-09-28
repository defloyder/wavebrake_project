<?php

namespace App\Services\UserAdministration;

use App\Support\ByteFormatter;
use App\Support\DisplayDate;
use App\View\Admin\AdminDirectory;
use App\View\Admin\Rows\DeviceRow;
use App\View\Admin\Rows\GrantRow;
use App\View\Admin\StatusBadge;

/**
 * Read model of GET /v1/admin/users/{id} for the user card. Only
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

    public function userId(): string
    {
        return (string) ($this->user()['id'] ?? '');
    }

    public function displayName(): string
    {
        $user = $this->user();

        return (string) (($user['email'] ?? '') ?: (($user['username'] ?? '') ?: $this->userId()));
    }

    public function initial(): string
    {
        return mb_strtoupper(mb_substr($this->displayName(), 0, 1));
    }

    public function isBlocked(): bool
    {
        return StatusBadge::user($this->user())->tone === 'bad';
    }

    public function roleBadge(): StatusBadge
    {
        return StatusBadge::role($this->user()['role'] ?? 'user');
    }

    public function statusBadge(): StatusBadge
    {
        return StatusBadge::user($this->user());
    }

    public function registeredAt(): string
    {
        return DisplayDate::date($this->user()['created_at'] ?? null);
    }

    public function lastLogin(): string
    {
        return DisplayDate::relative($this->user()['last_login_at'] ?? null, 'не входил');
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

    public function subscriptionId(): string
    {
        return (string) ($this->subscription()['id'] ?? '');
    }

    public function subscriptionBadge(): StatusBadge
    {
        return StatusBadge::subscription($this->subscription()['status'] ?? null);
    }

    public function isSubscriptionActive(): bool
    {
        return ($this->subscription()['status'] ?? '') === 'active' && ($this->daysLeft() ?? 1) >= 0;
    }

    /** @return array<string, mixed>|null */
    public function plan(): ?array
    {
        return $this->subscription()['plan'] ?? null;
    }

    public function planName(): string
    {
        $plan = $this->plan();

        return $plan === null ? 'Индивидуальная' : (string) (($plan['name'] ?? '') ?: ($plan['code'] ?? 'Тариф'));
    }

    public function planId(): string
    {
        return (string) ($this->plan()['id'] ?? '');
    }

    public function startedAt(): string
    {
        return DisplayDate::date($this->subscription()['started_at'] ?? null);
    }

    public function expiresAt(): string
    {
        return DisplayDate::date($this->subscription()['expires_at'] ?? null);
    }

    public function expiresInput(): string
    {
        return DisplayDate::inputDate($this->subscription()['expires_at'] ?? null);
    }

    public function daysLeft(): ?int
    {
        return DisplayDate::daysLeft($this->subscription()['expires_at'] ?? null);
    }

    public function daysLeftLabel(): string
    {
        $days = $this->daysLeft();
        if ($days === null) {
            return DisplayDate::isUnlimited($this->subscription()['expires_at'] ?? null) ? 'бессрочно' : '';
        }
        if ($days < 0) {
            return 'истекла';
        }

        return $days === 0 ? 'последний день' : 'осталось '.$days.' '.self::plural($days, 'день', 'дня', 'дней');
    }

    public function deviceLimitInput(): string
    {
        $limit = $this->subscription()['device_limit'] ?? null;

        return $limit === null ? '' : (string) $limit;
    }

    public function trafficLimitInput(): string
    {
        $limit = $this->subscription()['traffic_limit_bytes'] ?? null;

        return ByteFormatter::gigabytesInput($limit === null ? null : (int) $limit);
    }

    /** @return array<string, mixed> */
    public function access(): array
    {
        return $this->data['access'] ?? ['grants' => [], 'active_grants' => 0];
    }

    public function subscriptionUrl(): string
    {
        return (string) ($this->access()['subscription_url'] ?? '');
    }

    public function credentialId(): string
    {
        return (string) ($this->access()['credential_id'] ?? '');
    }

    /** Active subscription without a key: the card offers "Выдать доступ". */
    public function needsAccess(): bool
    {
        return $this->hasSubscription() && $this->credentialId() === '';
    }

    /** @return list<GrantRow> */
    public function grants(): array
    {
        $directory = new AdminDirectory;

        return array_map(fn ($g) => GrantRow::fromCore($g, $directory), $this->access()['grants'] ?? []);
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

    /** @return list<DeviceRow> */
    public function deviceRows(): array
    {
        return array_map(fn ($d) => DeviceRow::fromCore($d), $this->devices()['items'] ?? []);
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

    public function trafficUp(): string
    {
        return ByteFormatter::format((int) ($this->traffic()['bytes_up'] ?? 0));
    }

    public function trafficDown(): string
    {
        return ByteFormatter::format((int) ($this->traffic()['bytes_down'] ?? 0));
    }

    public function trafficLimit(): string
    {
        $limit = $this->traffic()['limit_bytes'] ?? null;

        return ByteFormatter::format($limit === null ? null : (int) $limit);
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

        return ($devices['registered'] ?? 0).' из '.($limit === null ? '—' : $limit);
    }

    /** Masked for display; the full value is only copied on explicit action. */
    public function maskedSubscriptionUrl(): string
    {
        $url = $this->subscriptionUrl();
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

    private static function plural(int $n, string $one, string $few, string $many): string
    {
        $mod10 = $n % 10;
        $mod100 = $n % 100;
        if ($mod10 === 1 && $mod100 !== 11) {
            return $one;
        }
        if ($mod10 >= 2 && $mod10 <= 4 && ($mod100 < 12 || $mod100 > 14)) {
            return $few;
        }

        return $many;
    }
}
