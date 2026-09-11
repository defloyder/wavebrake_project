<?php

namespace App\Http\Controllers;

use App\Models\Subscription;
use App\Models\Plan;
use App\Models\User;
use App\Models\PromoCode;
use App\Models\Node;
use App\Models\PasswordChangeRequest;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Str;

class SyncWebhookController extends Controller
{
    /**
     * Unified Core event webhook.
     * POST /api/webhook/core-sync
     */
    public function coreSync(Request $request): JsonResponse
    {
        if (! $this->hasValidCoreSignature($request)) {
            return response()->json([
                'ok' => false,
                'error' => ['code' => 'UNAUTHORIZED', 'message' => 'Invalid Core signature.'],
            ], 401);
        }

        $event = $request->validate([
            'version' => ['required', 'integer'],
            'event_id' => ['required', 'string'],
            'source' => ['nullable', 'string'],
            'resource' => ['required', 'string'],
            'action' => ['required', 'string'],
            'occurred_at' => ['nullable', 'string'],
            'identity' => ['nullable', 'array'],
            'payload' => ['nullable', 'array'],
        ]);

        $eventId = (string) $event['event_id'];
        if (! Cache::add('core-sync-event:'.$eventId, true, now()->addDay())) {
            return response()->json(['ok' => true, 'event_id' => $eventId, 'duplicate' => true]);
        }

        try {
            $identity = $event['identity'] ?? [];
            $payload = $event['payload'] ?? [];
            $action = (string) $event['action'];

            match ((string) $event['resource']) {
                'users' => $this->applyUnifiedUser($identity, $payload, $action),
                'subscriptions' => $this->applyUnifiedSubscription($identity, $payload, $action),
                'promo_codes' => $this->applyUnifiedPromoCode($payload, $action),
                'nodes' => $this->applyUnifiedNode($payload, $action),
                'password_change' => $this->applyPasswordChange($payload, $action),
                default => Log::info('Core unified webhook ignored resource', [
                    'event_id' => $eventId,
                    'resource' => $event['resource'],
                    'action' => $action,
                ]),
            };
        } catch (\Throwable $e) {
            Cache::forget('core-sync-event:'.$eventId);
            Log::error('Core unified webhook failed', [
                'event_id' => $eventId,
                'resource' => $event['resource'] ?? null,
                'action' => $event['action'] ?? null,
                'error' => $e->getMessage(),
            ]);

            return response()->json([
                'ok' => false,
                'event_id' => $eventId,
                'error' => ['code' => 'SYNC_FAILED', 'message' => $e->getMessage()],
            ], 500);
        }

        return response()->json(['ok' => true, 'event_id' => $eventId]);
    }

    /**
     * Sync subscription from Core API to Laravel.
     * POST /api/webhook/sync-subscription
     */
    public function syncSubscription(Request $request): JsonResponse
    {
        $data = $request->validate([
            'telegram_id' => ['required', 'integer'],
            'token'       => ['required', 'string'],
            'client_uuid' => ['required', 'string'],
            'username'    => ['nullable', 'string'],
            'plan_id'     => ['nullable', 'integer'],
            'expires_at'  => ['nullable', 'string'],
            'is_unlimited' => ['nullable', 'boolean'],
            'status'      => ['required', 'string'],
        ]);

        // Find or create user
        $user = User::query()->where('telegram_id', $data['telegram_id'])->first();

        if (! $user) {
            $username = $data['username'] ?? 'user' . $data['telegram_id'];
            // Ensure unique username
            $baseUsername = $username;
            $counter = 1;
            while (User::query()->where('username', $username)->exists()) {
                $username = $baseUsername . '_' . $counter++;
            }

            $user = User::query()->create([
                'name'        => $username,
                'username'    => $username,
                'email'       => $username . '@auralith.local',
                'password'    => Hash::make(Str::random(32)),
                'telegram_id' => $data['telegram_id'],
                'token'       => $data['token'],
                'client_uuid' => $data['client_uuid'],
            ]);
        }

        $planId = $data['plan_id'] ?? Plan::query()->orderBy('duration_months')->value('id') ?? 1;

        // Sync subscription
        Subscription::query()->updateOrCreate(
            ['user_id' => $user->id],
            [
                'plan_id'      => $planId,
                'status'       => $data['status'],
                'ends_at'      => ($data['is_unlimited'] ?? false) ? null : ($data['expires_at'] ?? null),
                'starts_at'    => now(),
                'last_sync_at' => now(),
            ]
        );

        return response()->json(['ok' => true]);
    }

    /**
     * Sync user from Core API to Laravel.
     * POST /api/webhook/sync-user
     */
    public function syncUser(Request $request): JsonResponse
    {
        $data = $request->validate([
            'telegram_id' => ['required', 'integer'],
            'token'       => ['nullable', 'string'],
            'client_uuid' => ['nullable', 'string'],
            'username'    => ['nullable', 'string'],
        ]);

        $username = $data['username'] ?? 'user' . $data['telegram_id'];

        $user = User::query()->firstOrNew(['telegram_id' => $data['telegram_id']]);

        if (! $user->exists) {
            $baseUsername = $username;
            $counter = 1;
            while (User::query()->where('username', $username)->exists()) {
                $username = $baseUsername . '_' . $counter++;
            }

            $user->name = $username;
            $user->username = $username;
            $user->email = $username . '@auralith.local';
            $user->password = Hash::make(Str::random(32));
        }

        if (! empty($data['token'])) {
            $user->token = $data['token'];
        }

        if (! empty($data['client_uuid'])) {
            $user->client_uuid = $data['client_uuid'];
        }

        $user->save();

        return response()->json(['ok' => true]);
    }

    private function hasValidCoreSignature(Request $request): bool
    {
        $secret = (string) config('services.core.webhook_secret', '');
        if ($secret === '') {
            return true;
        }

        $signature = (string) $request->header('X-Core-Signature', '');
        if ($signature === '') {
            return false;
        }

        $signature = Str::startsWith($signature, 'sha256=')
            ? Str::after($signature, 'sha256=')
            : $signature;

        return hash_equals(hash_hmac('sha256', $request->getContent(), $secret), $signature);
    }

    private function applyUnifiedUser(array $identity, array $payload, string $action): void
    {
        $user = $this->findUserByIdentity($identity, $payload);

        if (in_array($action, ['deleted', 'delete'], true)) {
            $user?->delete();
            return;
        }

        $telegramId = $payload['telegram_id'] ?? $identity['telegram_id'] ?? null;
        $username = trim((string) ($payload['username'] ?? $payload['name'] ?? ($telegramId ? 'user'.$telegramId : 'user')));

        if (! $user) {
            $user = new User();
            $user->password = Hash::make(Str::random(32));
        }

        $user->forceFill([
            'core_user_id' => $payload['core_user_id'] ?? $identity['core_user_id'] ?? $user->core_user_id,
            'name' => $payload['name'] ?? $username,
            'username' => $this->uniqueUsername($username, $user->id),
            'telegram_id' => $telegramId,
            'token' => $payload['token'] ?? $identity['token'] ?? $user->token,
            'client_uuid' => $payload['client_uuid'] ?? $identity['client_uuid'] ?? $user->client_uuid,
            'trial_used' => (bool) ($payload['trial_used'] ?? $user->trial_used ?? false),
            'has_password' => (bool) ($payload['has_password'] ?? $user->has_password ?? false),
            'receives_payment_notifications' => (bool) ($payload['receives_payment_notifications'] ?? $user->receives_payment_notifications ?? true),
        ])->save();
    }

    private function applyUnifiedSubscription(array $identity, array $payload, string $action): void
    {
        $user = $this->findUserByIdentity($identity, $payload);
        if (! $user) {
            $this->applyUnifiedUser($identity, $payload['user'] ?? $payload, 'updated');
            $user = $this->findUserByIdentity($identity, $payload);
        }

        if (! $user) {
            throw new \RuntimeException('User not found for subscription event.');
        }

        if (in_array($action, ['deleted', 'delete', 'cancelled', 'canceled'], true)) {
            Subscription::query()->where('user_id', $user->id)->update([
                'status' => 'expired',
                'last_sync_at' => now(),
            ]);
            return;
        }

        $planId = $payload['plan_id'] ?? Plan::query()->orderBy('duration_months')->value('id') ?? 1;
        $isUnlimited = (bool) ($payload['is_unlimited'] ?? false);

        Subscription::query()->updateOrCreate(
            ['user_id' => $user->id],
            [
                'plan_id' => $planId,
                'node_id' => $payload['node_id'] ?? null,
                'status' => $payload['status'] ?? 'active',
                'starts_at' => $payload['starts_at'] ?? now(),
                'ends_at' => $isUnlimited ? null : ($payload['ends_at'] ?? $payload['expires_at'] ?? null),
                'last_sync_at' => now(),
            ],
        );
    }

    private function applyUnifiedPromoCode(array $payload, string $action): void
    {
        $code = mb_strtoupper(trim((string) ($payload['code'] ?? '')));
        if ($code === '') {
            return;
        }

        if (in_array($action, ['deleted', 'delete'], true)) {
            PromoCode::query()->where('code', $code)->delete();
            return;
        }

        PromoCode::query()->updateOrCreate(
            ['code' => $code],
            [
                'type' => $payload['type'] ?? 'percent',
                'value' => (float) ($payload['value'] ?? $payload['discount'] ?? 0),
                'is_active' => (bool) ($payload['is_active'] ?? $payload['active'] ?? true),
                'starts_at' => $payload['starts_at'] ?? null,
                'expires_at' => $payload['expires_at'] ?? $payload['valid_until'] ?? null,
                'max_uses' => $payload['max_uses'] ?? $payload['usage_limit'] ?? null,
                'used_count' => (int) ($payload['used_count'] ?? $payload['uses'] ?? 0),
            ],
        );
    }

    private function applyUnifiedNode(array $payload, string $action): void
    {
        $name = trim((string) ($payload['name'] ?? ''));
        if ($name === '') {
            return;
        }

        if (in_array($action, ['deleted', 'delete'], true)) {
            Node::query()->where('name', $name)->delete();
            return;
        }

        Node::query()->updateOrCreate(
            ['name' => $name],
            [
                'ip' => $payload['ip'] ?? '',
                'port' => $payload['port'] ?? 443,
                'api_port' => $payload['api_port'] ?? 8443,
                'api_secret' => $payload['api_secret'] ?? '',
                'status' => $payload['status'] ?? 'unknown',
                'latency' => $payload['latency'] ?? null,
                'load' => $payload['load'] ?? 0,
                'errors' => $payload['errors'] ?? 0,
                'is_active' => (bool) ($payload['is_active'] ?? true),
            ],
        );
    }

    private function applyPasswordChange(array $payload, string $action): void
    {
        $pwdToken = (string) ($payload['pwd_token'] ?? '');
        if ($pwdToken === '') {
            return;
        }

        $status = in_array($action, ['confirmed', 'confirm'], true) ? 'confirmed' : 'cancelled';
        $request = PasswordChangeRequest::query()
            ->where('pwd_token', $pwdToken)
            ->whereNull('used_at')
            ->first();

        if (! $request) {
            return;
        }

        $request->forceFill($status === 'confirmed'
            ? ['status' => 'confirmed', 'confirmed_at' => now(), 'cancelled_at' => null, 'expires_at' => now()->addMinutes(10)]
            : ['status' => 'cancelled', 'cancelled_at' => now()]
        )->save();
    }

    private function findUserByIdentity(array $identity, array $payload): ?User
    {
        foreach ([
            ['id', $identity['laravel_user_id'] ?? $payload['laravel_user_id'] ?? null],
            ['core_user_id', $identity['core_user_id'] ?? $payload['core_user_id'] ?? null],
            ['telegram_id', $identity['telegram_id'] ?? $payload['telegram_id'] ?? null],
            ['token', $identity['token'] ?? $payload['token'] ?? null],
            ['client_uuid', $identity['client_uuid'] ?? $payload['client_uuid'] ?? null],
        ] as [$column, $value]) {
            if ($value !== null && $value !== '') {
                $user = User::query()->where($column, $value)->first();
                if ($user) {
                    return $user;
                }
            }
        }

        return null;
    }

    private function uniqueUsername(string $username, ?int $ignoreId = null): string
    {
        $base = Str::of($username)->lower()->replaceMatches('/[^a-z0-9_\-]+/i', '_')->trim('_')->limit(40, '')->toString();
        $base = $base !== '' ? $base : 'user';
        $candidate = $base;
        $counter = 1;

        while (User::query()
            ->where('username', $candidate)
            ->when($ignoreId, fn ($query) => $query->where('id', '!=', $ignoreId))
            ->exists()) {
            $candidate = $base.'_'.$counter++;
        }

        return $candidate;
    }
}
