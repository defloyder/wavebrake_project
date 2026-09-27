<?php

namespace App\Services\UserAdministration;

use App\Services\Core\CoreApiException;
use App\Services\CoreClient;
use App\Support\ByteFormatter;
use App\Support\DisplayDate;
use Carbon\CarbonImmutable;
use Illuminate\Http\Client\RequestException;

/**
 * Admin use cases for one user — everything the user card can do. Each
 * action goes through Core and returns the refreshed card, so the modal
 * always shows what Core now holds. Nothing here touches Core data
 * directly or computes business numbers.
 */
final class UserAdministrationService
{
    public function __construct(private readonly CoreClient $core) {}

    /** @return array<string, mixed> the signed-in admin (Core /v1/me) */
    public function viewer(string $token): array
    {
        return $this->call(fn () => $this->core->me($token));
    }

    public function details(string $token, string $userId): UserDetails
    {
        return new UserDetails($this->call(fn () => $this->core->userDetails($token, $userId)));
    }

    public function issueSubscription(string $token, string $userId, string $planId): UserDetails
    {
        return new UserDetails($this->call(fn () => $this->core->issueUserSubscription($token, $userId, $planId)));
    }

    /** Issues the missing credential of the live subscription (idempotent). */
    public function issueAccess(string $token, string $userId): UserDetails
    {
        return new UserDetails($this->call(fn () => $this->core->issueUserAccess($token, $userId)));
    }

    /** @param array{email: string, username: string, password: string, role: string, status: string} $profile */
    public function updateProfile(string $token, string $userId, array $profile): UserDetails
    {
        return $this->then($token, $userId, fn () => $this->core->updateUser($token, $userId, $profile));
    }

    public function setBlocked(string $token, string $userId, bool $blocked): UserDetails
    {
        return $this->then($token, $userId, fn () => $blocked
            ? $this->core->disableUser($token, $userId)
            : $this->core->enableUser($token, $userId));
    }

    public function delete(string $token, string $userId): void
    {
        $this->call(fn () => $this->core->deleteUser($token, $userId));
    }

    /**
     * @param  array{plan_id?: ?string, status?: ?string, expires_on?: ?string, traffic_unlimited?: bool, traffic_limit_gb?: ?float, device_limit?: ?int}  $changes
     */
    public function editSubscription(string $token, string $userId, string $subscriptionId, array $changes): UserDetails
    {
        $payload = [
            'plan_id' => $changes['plan_id'] ?? null,
            'status' => $changes['status'] ?? null,
            'expires_at' => $this->endOfDay($changes['expires_on'] ?? null),
            'traffic_unlimited' => (bool) ($changes['traffic_unlimited'] ?? false),
            'traffic_limit_gb' => $changes['traffic_limit_gb'] ?? null,
            'device_limit' => $changes['device_limit'] ?? null,
        ];

        return $this->then($token, $userId, fn () => $this->core->editSubscription($token, $subscriptionId, $payload));
    }

    public function resetTraffic(string $token, string $userId, string $subscriptionId): UserDetails
    {
        return $this->then($token, $userId, fn () => $this->core->resetSubscriptionUsage($token, $subscriptionId));
    }

    /** Revokes the current key and issues a new one; the old link stops working. */
    public function reissueAccess(string $token, string $userId, string $subscriptionId): UserDetails
    {
        return $this->then($token, $userId, fn () => $this->core->reissueSubscription($token, $subscriptionId));
    }

    public function cancelSubscription(string $token, string $userId, string $subscriptionId): UserDetails
    {
        return $this->then($token, $userId, fn () => $this->core->deleteSubscription($token, $subscriptionId));
    }

    public function revokeDevice(string $token, string $userId, string $deviceId): UserDetails
    {
        return $this->then($token, $userId, fn () => $this->core->revokeDevice($token, $deviceId));
    }

    public function revokeGrant(string $token, string $userId, string $grantId): UserDetails
    {
        return $this->then($token, $userId, fn () => $this->core->revokeGrant($token, $grantId, 'admin'));
    }

    /** @return array<string, mixed> Core ResetResult (status, channel, delivery, expires_at) */
    public function requestPasswordReset(string $token, string $userId): array
    {
        return $this->call(fn () => $this->core->requestPasswordReset($token, $userId));
    }

    /**
     * Plans for the plan selects, loaded from Core.
     *
     * @return list<array{id: string, label: string, is_active: bool}>
     */
    public function planOptions(string $token): array
    {
        $plans = $this->call(fn () => $this->core->adminPlans($token));
        $options = [];
        foreach ($plans as $plan) {
            if (! empty($plan['deleted_at'])) {
                continue;
            }
            $options[] = [
                'id' => (string) $plan['id'],
                'label' => $this->planLabel($plan),
                'is_active' => (bool) ($plan['is_active'] ?? false),
            ];
        }

        return $options;
    }

    /** @param array<string, mixed> $plan */
    private function planLabel(array $plan): string
    {
        $price = number_format(((int) ($plan['price_minor'] ?? $plan['price_cents'] ?? 0)) / 100, 2, ',', ' ').' '.($plan['currency'] ?? 'USD');
        $term = isset($plan['duration_days']) ? $plan['duration_days'].' дн.' : (($plan['interval'] ?? 'month') === 'year' ? 'год' : 'месяц');
        $traffic = ByteFormatter::format(isset($plan['traffic_limit_bytes']) ? (int) $plan['traffic_limit_bytes'] : null);
        $status = ($plan['is_active'] ?? false) ? '' : ' · неактивен';

        return sprintf('%s — %s · %s · %s · %s устр.%s', $plan['name'] ?? $plan['code'] ?? '?', $price, $term, $traffic, $plan['device_limit'] ?? 1, $status);
    }

    /** A date picked in the operators' timezone means "until the end of that day". */
    private function endOfDay(?string $date): ?string
    {
        if ($date === null || trim($date) === '') {
            return null;
        }

        return CarbonImmutable::parse($date, DisplayDate::timezone())->endOfDay()->utc()->toRfc3339String();
    }

    /** Runs a Core action, then returns the refreshed card. */
    private function then(string $token, string $userId, callable $action): UserDetails
    {
        $this->call($action);

        return $this->details($token, $userId);
    }

    /**
     * @template T
     *
     * @param  callable(): T  $request
     * @return T
     */
    private function call(callable $request): mixed
    {
        try {
            return $request();
        } catch (RequestException $e) {
            throw CoreApiException::fromRequestException($e);
        }
    }
}
