<?php

namespace App\Services\UserAdministration;

use App\Services\Core\CoreApiException;
use App\Services\CoreClient;
use App\Support\ByteFormatter;
use Illuminate\Http\Client\RequestException;

/**
 * Admin use cases for one user (details, forced plan assignment, password
 * reset). Everything goes through Core; nothing here touches Core data
 * directly or computes business numbers.
 */
final class UserAdministrationService
{
    public function __construct(private readonly CoreClient $core) {}

    public function details(string $token, string $userId): UserDetails
    {
        return new UserDetails($this->call(fn () => $this->core->userDetails($token, $userId)));
    }

    public function issueSubscription(string $token, string $userId, string $planId): UserDetails
    {
        return new UserDetails($this->call(fn () => $this->core->issueUserSubscription($token, $userId, $planId)));
    }

    /** @return array<string, mixed> Core ResetResult (status, channel, delivery, expires_at) */
    public function requestPasswordReset(string $token, string $userId): array
    {
        return $this->call(fn () => $this->core->requestPasswordReset($token, $userId));
    }

    /**
     * Plans for the "Issue subscription" select, loaded from Core.
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
        $price = number_format(((int) ($plan['price_minor'] ?? $plan['price_cents'] ?? 0)) / 100, 2, '.', ' ').' '.($plan['currency'] ?? 'USD');
        $term = isset($plan['duration_days']) ? $plan['duration_days'].' дн.' : ($plan['interval'] ?? '');
        $traffic = array_key_exists('traffic_limit_bytes', $plan) && $plan['traffic_limit_bytes'] !== null
            ? ByteFormatter::format((int) $plan['traffic_limit_bytes'])
            : 'безлимит';
        $status = ($plan['is_active'] ?? false) ? '' : ' · неактивен';

        return sprintf('%s — %s · %s · %s · %s устр.%s', $plan['name'] ?? $plan['code'] ?? '?', $price, $term, $traffic, $plan['device_limit'] ?? 1, $status);
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
