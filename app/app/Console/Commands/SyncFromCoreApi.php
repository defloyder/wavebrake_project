<?php

namespace App\Console\Commands;

use App\Models\Plan;
use App\Models\Subscription;
use App\Models\User;
use App\Services\CoreApiService;
use Illuminate\Console\Command;
use Illuminate\Support\Arr;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Str;

class SyncFromCoreApi extends Command
{
    protected $signature = 'core:sync';
    protected $description = 'Pull all users and subscriptions from Core API into Laravel DB';

    public function handle(CoreApiService $core): int
    {
        Log::info('core:sync started');

        $response = $core->adminUsers();

        if (! $response) {
            Log::error('core:sync: failed to fetch users from Core API');
            return self::FAILURE;
        }

        $userList = $this->extractCoreUsers($response);

        if (empty($userList)) {
            Log::warning('core:sync: empty user list', ['response' => $response]);
            return self::SUCCESS;
        }

        $synced  = 0;
        $created = 0;

        foreach ($userList as $coreUser) {
            if (! is_array($coreUser)) {
                continue;
            }

            $telegramId = Arr::get($coreUser, 'telegram_id');
            $coreUserId = Arr::get($coreUser, 'id') ?? Arr::get($coreUser, 'user_id') ?? Arr::get($coreUser, 'core_user_id');
            $token      = Arr::get($coreUser, 'token');
            $username   = Arr::get($coreUser, 'username') ?? Arr::get($coreUser, 'name');
            $trialUsed  = (bool) Arr::get($coreUser, 'trial_used', false);

            $user = $this->findLocalUser($coreUser);

            if (! $user) {
                if (! $coreUserId && ! $telegramId && ! $token) {
                    continue;
                }

                $uname = $username ?? 'user' . ($telegramId ?: $coreUserId);
                $base  = $uname;
                $i     = 1;
                while (User::query()->where('username', $uname)->exists()) {
                    $uname = $base . '_' . $i++;
                }

                // If token already taken by another user — skip to avoid conflict
                if ($token && User::query()->where('token', $token)->exists()) {
                    continue;
                }

                $createPayload = [
                    'name'        => $uname,
                    'username'    => $uname,
                    'password'    => Hash::make(Str::random(32)),
                    'core_user_id' => $coreUserId,
                    'telegram_id' => $telegramId,
                    'token'       => $token,
                    'client_uuid' => (string) Str::uuid(),
                    'trial_used'  => $trialUsed,
                ];

                $user = User::query()->create(array_filter(
                    $createPayload,
                    fn ($value, $field) => $value !== null && Schema::hasColumn('users', $field),
                    ARRAY_FILTER_USE_BOTH,
                ));
                $created++;
            } else {
                $updates = [
                    'core_user_id' => $coreUserId,
                    'trial_used' => $trialUsed,
                ];

                if ($telegramId && ! User::query()->where('telegram_id', $telegramId)->whereKeyNot($user->id)->exists()) {
                    $updates['telegram_id'] = $telegramId;
                }

                if ($token && ! User::query()->where('token', $token)->whereKeyNot($user->id)->exists()) {
                    $updates['token'] = $token;
                }

                if (
                    $username
                    && (! $user->username || str_starts_with((string) $user->username, 'user'))
                    && ! User::query()->where('username', $username)->whereKeyNot($user->id)->exists()
                ) {
                    $updates['username'] = $username;
                    $updates['name'] = $username;
                }

                foreach ($updates as $field => $value) {
                    if ($value !== null && Schema::hasColumn('users', $field)) {
                        $user->{$field} = $value;
                    }
                }

                if ($user->isDirty()) {
                    $user->save();
                }
            }

            $sub = Arr::get($coreUser, 'subscription');
            $sub = is_array($sub) ? $sub : $coreUser;
            $existingSubscription = Subscription::query()->where('user_id', $user->id)->first();
            $snapshot = $this->normalizeSubscriptionSnapshot($coreUser, $sub, $trialUsed);

            if ($snapshot['has_subscription_data']) {
                $localPlanId = $this->resolveCorePlanId(array_merge($coreUser, $sub))
                    ?? $existingSubscription?->plan_id
                    ?? Plan::query()->orderBy('id')->value('id')
                    ?? 1;

                $startsAt = Arr::get($sub, 'starts_at')
                    ?? Arr::get($sub, 'started_at')
                    ?? Arr::get($sub, 'created_at')
                    ?? $existingSubscription?->starts_at;

                $payload = [
                    'plan_id'      => $localPlanId,
                    'status'       => $snapshot['status'],
                    'ends_at'      => $snapshot['is_unlimited'] ? null : $snapshot['expires_at'],
                    'starts_at'    => $startsAt,
                    'last_sync_at' => now(),
                ];

                $trafficUsed = $this->trafficGb($sub);
                if ($trafficUsed !== null) {
                    $payload['traffic_used_gb'] = $trafficUsed;
                }

                Subscription::query()->updateOrCreate(
                    ['user_id' => $user->id],
                    $payload
                );

                $synced++;
            } elseif ($existingSubscription) {
                $existingSubscription->forceFill([
                    'status' => 'inactive',
                    'last_sync_at' => now(),
                ])->save();
            }
        }

        Log::info("core:sync done. users_created={$created} subscriptions_synced={$synced}");

        // Mark expired subscriptions
        $expired = Subscription::query()
            ->whereIn('status', ['active', 'trial'])
            ->where('ends_at', '<', now())
            ->update(['status' => 'expired']);

        if ($expired > 0) {
            Log::info("core:sync: marked {$expired} subscriptions as expired");
        }

        return self::SUCCESS;
    }

    private function extractCoreUsers(array $response): array
    {
        if (array_is_list($response)) {
            return $response;
        }

        foreach (['users', 'data', 'items', 'results'] as $key) {
            $value = Arr::get($response, $key);
            if (is_array($value)) {
                return $value;
            }
        }

        return [];
    }

    private function findLocalUser(array $coreUser): ?User
    {
        $telegramId = Arr::get($coreUser, 'telegram_id');
        $coreUserId = Arr::get($coreUser, 'id') ?? Arr::get($coreUser, 'user_id') ?? Arr::get($coreUser, 'core_user_id');
        $token = Arr::get($coreUser, 'token');

        return User::query()
            ->when($coreUserId && Schema::hasColumn('users', 'core_user_id'), fn ($query) => $query->orWhere('core_user_id', $coreUserId))
            ->when($telegramId, fn ($query) => $query->orWhere('telegram_id', $telegramId))
            ->when($token, fn ($query) => $query->orWhere('token', $token))
            ->first();
    }

    private function resolveCorePlanId(array $payload): ?int
    {
        $localPlanId = Arr::get($payload, 'laravel_plan_id')
            ?? Arr::get($payload, 'local_plan_id');

        if (is_numeric($localPlanId)) {
            $planId = Plan::query()->whereKey((int) $localPlanId)->value('id');
            if ($planId) {
                return (int) $planId;
            }
        }

        $duration = (int) (
            Arr::get($payload, 'duration_months')
            ?? Arr::get($payload, 'months')
            ?? Arr::get($payload, 'period_months')
            ?? Arr::get($payload, 'plan_months')
            ?? 0
        );

        if ($duration > 0) {
            $planId = Plan::query()->where('duration_months', $duration)->value('id');
            if ($planId) {
                return (int) $planId;
            }
        }

        $amount = Arr::get($payload, 'amount')
            ?? Arr::get($payload, 'price_rub')
            ?? Arr::get($payload, 'price')
            ?? Arr::get($payload, 'paid_amount');

        if (is_numeric($amount)) {
            $planId = Plan::query()->where('price_rub', (int) round((float) $amount))->value('id');
            if ($planId) {
                return (int) $planId;
            }
        }

        $name = Arr::get($payload, 'plan_name')
            ?? Arr::get($payload, 'tariff')
            ?? Arr::get($payload, 'tariff_name');

        if (is_string($name) && trim($name) !== '') {
            $name = trim($name);
            $planId = Plan::query()
                ->where('name', $name)
                ->orWhere('headline', $name)
                ->value('id');
            if ($planId) {
                return (int) $planId;
            }
        }

        $corePlanId = Arr::get($payload, 'plan_id');
        if (filter_var(env('CORE_PLAN_IDS_ARE_LOCAL', false), FILTER_VALIDATE_BOOL) && is_numeric($corePlanId)) {
            return Plan::query()->whereKey((int) $corePlanId)->value('id');
        }

        return null;
    }

    private function normalizeSubscriptionSnapshot(array $coreUser, array $subscription, bool $trialUsed): array
    {
        $expiresAt = Arr::get($subscription, 'expires_at')
            ?? Arr::get($subscription, 'ends_at')
            ?? Arr::get($coreUser, 'expires_at')
            ?? Arr::get($coreUser, 'ends_at');
        $isUnlimited = $this->boolOrNull(Arr::get($subscription, 'is_unlimited') ?? Arr::get($coreUser, 'is_unlimited')) === true;
        $explicitActive = $this->boolOrNull(Arr::get($subscription, 'is_active') ?? Arr::get($coreUser, 'is_active'));
        $coreStatus = strtolower((string) (
            Arr::get($subscription, 'status')
            ?? Arr::get($coreUser, 'subscription_status')
            ?? Arr::get($coreUser, 'status')
            ?? ''
        ));

        $expiresCarbon = null;
        if ($expiresAt) {
            try {
                $expiresCarbon = Carbon::parse($expiresAt);
            } catch (\Throwable) {
                $expiresAt = null;
            }
        }

        $hasSubscriptionData = $isUnlimited
            || $explicitActive !== null
            || $expiresAt !== null
            || in_array($coreStatus, ['active', 'trial', 'inactive', 'expired', 'expiring_soon', 'pending'], true)
            || $this->resolveCorePlanId(array_merge($coreUser, $subscription)) !== null;

        if (! $hasSubscriptionData) {
            return [
                'has_subscription_data' => false,
                'is_unlimited' => false,
                'expires_at' => null,
                'status' => 'inactive',
            ];
        }

        if ($isUnlimited) {
            $isActive = true;
        } elseif ($explicitActive !== null) {
            $isActive = $explicitActive;
        } elseif (in_array($coreStatus, ['active', 'trial', 'expiring_soon'], true)) {
            $isActive = true;
        } elseif (in_array($coreStatus, ['inactive', 'expired', 'pending'], true)) {
            $isActive = false;
        } else {
            $isActive = $expiresCarbon?->isFuture() ?? false;
        }

        if (! $isUnlimited && $expiresCarbon?->isPast()) {
            $isActive = false;
        }

        $status = in_array($coreStatus, ['active', 'trial', 'inactive', 'expired', 'expiring_soon', 'pending'], true)
            ? $coreStatus
            : null;

        if ($isActive) {
            if (! in_array($status, ['active', 'trial', 'expiring_soon'], true)) {
                $status = $trialUsed ? 'trial' : 'active';
            }
        } elseif ($expiresCarbon?->isPast()) {
            $status = 'expired';
        } else {
            $status = in_array($status, ['inactive', 'expired', 'pending'], true) ? $status : 'inactive';
        }

        return [
            'has_subscription_data' => true,
            'is_unlimited' => $isUnlimited,
            'expires_at' => $expiresAt,
            'status' => $status,
        ];
    }

    private function boolOrNull(mixed $value): ?bool
    {
        if ($value === null) {
            return null;
        }

        return filter_var($value, FILTER_VALIDATE_BOOL, FILTER_NULL_ON_FAILURE);
    }

    private function trafficGb(array $payload): ?float
    {
        foreach (['traffic_used_gb', 'traffic_gb', 'used_gb', 'total_gb'] as $key) {
            $value = Arr::get($payload, $key);
            if (is_numeric($value)) {
                return round((float) $value, 3);
            }
        }

        foreach (['traffic_used_bytes', 'traffic_bytes', 'used_bytes', 'total_bytes'] as $key) {
            $value = Arr::get($payload, $key);
            if (is_numeric($value)) {
                return round(((float) $value) / 1024 / 1024 / 1024, 3);
            }
        }

        return null;
    }
}
