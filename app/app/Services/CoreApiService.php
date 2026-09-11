<?php

namespace App\Services;

use Illuminate\Http\Client\Response;
use Illuminate\Http\Client\Pool;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Str;
use App\Models\Node;
use App\Models\PromoCode;
use App\Models\Subscription;
use App\Models\User;

/**
 * CoreApiService
 *
 * Обёртка над Auralith Core REST API (Python / FastAPI).
 * Базовый URL и ключи берутся из .env через config/services.php.
 */
class CoreApiService
{
    private string $baseUrl;
    private string $adminKey;
    private string $botToken;
    private ?array $lastError = null;

    public function __construct()
    {
        $this->baseUrl  = rtrim(config('services.core.url', ''), '/');
        $this->adminKey = config('services.core.admin_key', '');
        $this->botToken = config('services.core.bot_token', '');
    }

    // ──────────────────────────────────────────────────────────────
    // Auth
    // ──────────────────────────────────────────────────────────────

    /**
     * Регистрация / вход через Telegram ID.
     * POST /auth/telegram
     */
    public function authTelegram(int $telegramId, ?string $username = null): ?array
    {
        $result = $this->syncRequest('auth', 'telegram_login', [
            'telegram_id' => $telegramId,
            'username' => $username,
        ], [
            'telegram_id' => $telegramId,
        ]);

        if ($result !== null) {
            return $result;
        }

        return $this->post('/auth/telegram', [
            'telegram_id' => $telegramId,
            'username'    => $username,
        ]);
    }

    /**
     * Получить данные пользователя по токену.
     * GET /auth/me
     */
    public function getMe(string $token): ?array
    {
        return $this->get('/auth/me', [], $token);
    }

    /**
     * Активировать пробный период.
     * POST /auth/trial
     */
    public function activateTrial(string $token): ?array
    {
        $result = $this->syncRequest('trial', 'activate', [], ['token' => $token], null, $token);

        return $result ?? $this->post('/auth/trial', [], $token);
    }

    /**
     * Бонусный баланс и история начислений/списаний.
     * GET /auth/bonus
     */
    public function getBonus(string $token): ?array
    {
        $result = $this->syncRequest('bonus', 'get_balance', [], ['token' => $token], null, $token);

        return $result ?? $this->get('/auth/bonus', [], $token);
    }

    /**
     * Реферальная программа пользователя.
     * GET /auth/referral
     */
    public function getReferral(string $token): ?array
    {
        $result = $this->syncRequest('referral', 'get', [], ['token' => $token], null, $token);

        return $result ?? $this->get('/auth/referral', [], $token);
    }

    public function createAppLoginToken(int|string $telegramId, ?string $username, string $sessionKey): ?array
    {
        return $this->post('/auth/login-token', [
            'telegram_id' => (int) $telegramId,
            'username' => $username,
            'session_key' => $sessionKey,
        ]);
    }

    // ──────────────────────────────────────────────────────────────
    // Subscription / Config
    // ──────────────────────────────────────────────────────────────

    /**
     * Статус подписки пользователя.
     * GET /sub/{token}/status
     */
    public function getSubStatus(string $token): ?array
    {
        $result = $this->syncRequest('subscriptions', 'get_status', [], ['token' => $token]);

        return $result ?? $this->get("/sub/{$token}/status");
    }

    public function publicGetRaw(string $path): ?Response
    {
        if ($this->baseUrl === '') {
            return null;
        }

        try {
            $response = Http::timeout(8)
                ->get($this->baseUrl . $path);

            if ($response->successful()) {
                $this->lastError = null;
                return $response;
            }

            $this->lastError = [
                'path' => $path,
                'status' => $response->status(),
                'body' => $response->body(),
            ];

            Log::warning("CoreApi public GET {$path} returned {$response->status()}", [
                'body' => $response->body(),
            ]);

            return null;
        } catch (\Throwable $e) {
            $this->lastError = [
                'path' => $path,
                'status' => null,
                'body' => $e->getMessage(),
            ];

            Log::error("CoreApi public GET {$path} failed: " . $e->getMessage());
            return null;
        }
    }

    // ──────────────────────────────────────────────────────────────
    // Payments
    // ──────────────────────────────────────────────────────────────

    /**
     * Создать платёж через CloudPayments.
     * POST /payments/cp/create
     */
    public function createPayment(string $token, int $planId, int $paymentMethod, ?string $promocode = null): ?array
    {
        $payload = [
            'token'          => $token,
            'plan_id'        => $planId,
            'payment_method' => $paymentMethod,
        ];
        if ($promocode) {
            $payload['promocode'] = $promocode;
        }

        $result = $this->syncRequest('payments', 'create', $payload, ['token' => $token], null, $token);

        return $result
            ?? $this->post('/payments/cp/create', $payload)
            ?? $this->post('/payments/create', $payload);
    }

    /**
     * Применить промокод типа free_days.
     * POST /payments/apply_promo
     */
    public function applyPromo(string $token, string $code): ?array
    {
        $payload = [
            'token' => $token,
            'code'  => $code,
        ];

        $result = $this->syncRequest('promo_codes', 'apply', $payload, ['token' => $token], null, $token);

        return $result ?? $this->post('/payments/apply_promo', $payload);
    }

    // ──────────────────────────────────────────────────────────────
    // Admin
    // ──────────────────────────────────────────────────────────────

    /**
     * Статистика.
     * GET /admin/stats
     */
    public function cancelCloudPaymentsSubscription(string $token): ?array
    {
        $result = $this->syncRequest('subscriptions', 'cancel', [
            'cancel_provider_subscription' => true,
            'reason' => 'user_request',
        ], ['token' => $token]);

        if ($result !== null) {
            return $result;
        }

        try {
            $response = Http::timeout(8)
                ->acceptJson()
                ->asJson()
                ->withHeaders(['X-Bot-Token' => $this->botToken])
                ->post($this->baseUrl . '/payments/cp/cancel-subscription', [
                    'token' => $token,
                ]);

            return $this->handle($response, '/payments/cp/cancel-subscription');
        } catch (\Throwable $e) {
            Log::error('CoreApi cancel CloudPayments subscription failed: ' . $e->getMessage());
            return null;
        }
    }

    public function adminStats(): ?array
    {
        return $this->adminGet('/admin/stats');
    }

    /**
     * Traffic summary for dashboard cards.
     * GET /admin/traffic/summary
     */
    public function adminTrafficSummary(): ?array
    {
        return $this->adminGet('/admin/traffic/summary');
    }

    /**
     * Force Core to refresh traffic snapshots.
     * POST /admin/traffic/refresh
     */
    public function adminRefreshTraffic(): ?array
    {
        return $this->adminPost('/admin/traffic/refresh');
    }

    /**
     * Remove old traffic snapshots in Core.
     * DELETE /admin/traffic/snapshots/old
     */
    public function adminDeleteOldTrafficSnapshots(): ?array
    {
        return $this->adminDelete('/admin/traffic/snapshots/old');
    }

    /**
     * Public release metadata hosted on Core, for example /downloads/windows/latest.json.
     */
    public function clientLatestJson(?string $path): ?array
    {
        foreach ($this->clientLatestJsonUrls($path) as $url) {
            $cacheKey = 'core-client-latest-json:'.sha1($url);
            $cached = Cache::get($cacheKey);
            if (is_array($cached)) {
                return $cached;
            }

            try {
                $response = Http::timeout(4)
                    ->acceptJson()
                    ->get($url);

                if (! $response->successful()) {
                    $this->lastError = [
                        'path' => $url,
                        'status' => $response->status(),
                        'body' => $response->body(),
                    ];

                    Log::warning('Core latest.json returned non-success status', [
                        'url' => $url,
                        'status' => $response->status(),
                    ]);

                    continue;
                }

                $json = $response->json();
                if (is_array($json)) {
                    Cache::put($cacheKey, $json, now()->addSeconds(60));
                    return $json;
                }
            } catch (\Throwable $e) {
                $this->lastError = [
                    'path' => $url,
                    'status' => null,
                    'body' => $e->getMessage(),
                ];

                Log::warning('Core latest.json fetch failed: '.$e->getMessage(), [
                    'url' => $url,
                ]);

                continue;
            }
        }

        return null;
    }

    /**
     * Список нод.
     * GET /admin/nodes
     */
    public function adminNodes(): ?array
    {
        $result = $this->syncRequest('nodes', 'list', [], [], ['type' => 'admin', 'id' => session('admin_id')]);

        return $result ?? $this->adminGet('/admin/nodes');
    }

    public function adminNodeServerConfig(int $nodeId): ?array
    {
        return $this->adminGet("/admin/nodes/{$nodeId}/server-config");
    }

    public function adminNodeXrayConfig(int $nodeId): ?array
    {
        return $this->adminGet("/admin/nodes/{$nodeId}/xray-config");
    }

    public function adminNodeApiPing(int $nodeId): ?array
    {
        return $this->adminGet("/admin/nodes/{$nodeId}/api-ping");
    }

    public function adminCreateNode(Node $node): ?array
    {
        return $this->adminPost('/admin/nodes', $this->nodePayload($node));
    }

    public function adminUpdateNode(Node $node): ?array
    {
        return $this->adminPut("/admin/nodes/{$node->getKey()}", $this->nodePayload($node));
    }

    public function adminDeleteNode(Node $node): ?array
    {
        return $this->adminDelete("/admin/nodes/{$node->getKey()}");
    }

    /**
     * Список пользователей.
     * GET /admin/users
     */
    public function adminUsers(): ?array
    {
        $result = $this->syncRequest('users', 'list', [], [], ['type' => 'admin', 'id' => session('admin_id')]);

        return $result ?? $this->adminGet('/admin/users');
    }

    public function adminUserOverview(int $userId): ?array
    {
        return $this->adminGet("/admin/users/{$userId}/overview");
    }

    /**
     * Fetch user overviews concurrently so the users page does not wait for
     * one Core request after another.
     *
     * @param  array<int, int>  $userIds
     * @return array<int, array|null>
     */
    public function adminUserOverviews(array $userIds): array
    {
        $userIds = array_values(array_unique(array_filter(array_map('intval', $userIds))));
        if ($userIds === [] || $this->baseUrl === '') {
            return [];
        }

        try {
            $responses = Http::pool(function (Pool $pool) use ($userIds): array {
                return array_map(
                    fn (int $userId) => $pool
                        ->as((string) $userId)
                        ->timeout(5)
                        ->acceptJson()
                        ->withHeaders(['X-Admin-Key' => $this->adminKey])
                        ->get($this->baseUrl."/admin/users/{$userId}/overview"),
                    $userIds,
                );
            });
        } catch (\Throwable $e) {
            Log::error('CoreApi Admin user overviews failed: '.$e->getMessage());

            return [];
        }

        $result = [];
        foreach ($userIds as $userId) {
            $response = $responses[(string) $userId] ?? null;
            if ($response instanceof Response && $response->successful()) {
                $payload = $response->json();
                $result[$userId] = is_array($payload) ? $payload : null;
                continue;
            }

            $result[$userId] = null;
            if ($response instanceof Response) {
                Log::warning("CoreApi Admin GET /admin/users/{$userId}/overview returned {$response->status()}", [
                    'body' => $response->body(),
                ]);
            }
        }

        return $result;
    }

    public function adminUserDevices(int $userId): ?array
    {
        return $this->adminGet("/admin/users/{$userId}/devices");
    }

    public function adminDeactivateUserDevice(int $userId, int $deviceId): ?array
    {
        return $this->adminDelete("/admin/users/{$userId}/devices/{$deviceId}");
    }

    public function adminReactivateUserDevice(int $userId, int $deviceId): ?array
    {
        return $this->adminPost("/admin/users/{$userId}/devices/{$deviceId}/reactivate");
    }

    public function adminUserActiveSessions(int $userId): ?array
    {
        return $this->adminGet("/admin/users/{$userId}/active-sessions")
            ?? $this->adminGet("/admin/users/{$userId}/sessions");
    }

    public function adminUserTraffic(int $userId): ?array
    {
        return $this->adminGet("/admin/users/{$userId}/traffic");
    }

    public function adminAppClients(): ?array
    {
        return $this->adminGet('/admin/app-clients');
    }

    public function adminAppClient(string $supportCode): ?array
    {
        return $this->adminGet('/admin/app-clients/'.rawurlencode($supportCode));
    }

    public function adminRequestAppClientDiagnostics(string $supportCode): ?array
    {
        return $this->adminPost('/admin/app-clients/'.rawurlencode($supportCode).'/request-diagnostics');
    }

    public function adminAppClientDiagnostics(string $supportCode): ?array
    {
        return $this->adminGet('/admin/app-clients/'.rawurlencode($supportCode).'/diagnostics');
    }

    public function sendPasswordChangeConfirmation(int|string $telegramId, string $pwdToken): ?array
    {
        return $this->syncRequest('telegram', 'password_change_send', [
            'pwd_token' => $pwdToken,
        ], [
            'telegram_id' => (int) $telegramId,
        ], null, null, 'password_change:'.$pwdToken.':send');
    }

    /**
     * Список заказов из Core API.
     * GET /admin/orders
     */
    public function adminOrders(int $limit = 200, int $offset = 0): ?array
    {
        $result = $this->syncRequest('orders', 'list', [
            'limit' => $limit,
            'offset' => $offset,
        ], [], ['type' => 'admin', 'id' => session('admin_id')]);

        return $result ?? $this->adminGet("/admin/orders?limit={$limit}&offset={$offset}");
    }

    /**
     * CloudPayments orders from Core.
     * GET /admin/cp_orders
     */
    public function adminCpOrders(int $limit = 500, int $offset = 0): ?array
    {
        foreach ([
            "/admin/cp_orders?limit={$limit}&offset={$offset}",
            "/admin/cp-orders?limit={$limit}&offset={$offset}",
        ] as $path) {
            $orders = $this->adminGet($path);
            if ($orders !== null) {
                return $orders;
            }
        }

        return null;
    }


    /**
     * Продлить подписку пользователя.
     * POST /admin/subscriptions/{user_id}/extend
     */
    public function adminExtendSubscription(int $userId, int $days): ?array
    {
        return $this->adminPost("/admin/subscriptions/{$userId}/extend", ['days' => $days]);
    }

    public function adminExtendUserSubscription(User $user, int $days): ?array
    {
        $this->syncUserToCore($user);

        $ids = array_values(array_unique(array_filter([
            $user->core_user_id ? (int) $user->core_user_id : null,
            (int) $user->id,
        ])));

        foreach ($ids as $id) {
            $result = $this->adminExtendSubscription($id, $days);
            if ($result !== null) {
                return $result;
            }
        }

        if ($user->telegram_id) {
            foreach ([
                "/admin/users/telegram/{$user->telegram_id}/subscription/extend",
                "/admin/subscriptions/telegram/{$user->telegram_id}/extend",
            ] as $path) {
                $result = $this->adminPost($path, ['days' => $days]);
                if ($result !== null) {
                    return $result;
                }
            }
        }

        return null;
    }

    public function adminUpsertSubscription(Subscription $subscription): ?array
    {
        $user = $subscription->user()->first();
        if (! $user) {
            $this->lastError = [
                'path' => '/api/sync',
                'status' => null,
                'body' => 'Subscription user not found',
            ];

            return null;
        }

        $userSync = $this->syncUserToCore($user);
        if ($userSync === null) {
            return null;
        }

        $user = $user->fresh() ?? $user;
        $plan = $subscription->plan()->first();
        $requestId = (string) Str::uuid();
        $isUnlimited = $subscription->ends_at === null && $subscription->status === 'active';

        $payload = [
            'version' => 1,
            'request_id' => $requestId,
            'source' => 'laravel',
            'resource' => 'subscriptions',
            'action' => 'upsert',
            'occurred_at' => now()->toIso8601String(),
            'actor' => [
                'type' => 'admin',
                'id' => session('admin_id'),
            ],
            'identity' => $this->identityPayload($user),
            'payload' => [
                'laravel_subscription_id' => $subscription->id,
                'laravel_user_id' => $user->id,
                'plan_id' => $subscription->plan_id,
                'plan_duration_months' => $plan?->duration_months,
                'status' => $subscription->status,
                'starts_at' => $subscription->starts_at?->toIso8601String() ?? now()->toIso8601String(),
                'ends_at' => $subscription->ends_at?->toIso8601String(),
                'is_unlimited' => $isUnlimited,
                'node_id' => $subscription->node_id,
                'source' => 'admin_panel',
            ],
            'meta' => [
                'reason' => 'admin_panel',
                'idempotency_key' => 'subscription:'.$subscription->id.':upsert',
            ],
        ];

        $result = $this->adminSync($payload, $requestId);
        if ($result !== null) {
            return $result;
        }

        return null;
    }

    public function syncUserToCore(User $user): ?array
    {
        $user = $this->ensureUserSyncIdentity($user);

        if (! $user->telegram_id) {
            return $this->adminSync([
                'version' => 1,
                'request_id' => (string) Str::uuid(),
                'source' => 'laravel',
                'resource' => 'users',
                'action' => 'upsert',
                'occurred_at' => now()->toIso8601String(),
                'identity' => $this->identityPayload($user),
                'payload' => [
                    'name' => $user->name,
                    'username' => $user->username,
                    'telegram_id' => null,
                    'token' => $user->token,
                    'client_uuid' => $user->client_uuid,
                    'trial_used' => (bool) $user->trial_used,
                    'has_password' => (bool) $user->has_password,
                    'receives_payment_notifications' => (bool) $user->receives_payment_notifications,
                ],
                'meta' => ['reason' => 'admin_panel'],
            ]);
        }

        $legacyResult = $this->post('/webhook/sync-user', [
            'telegram_id' => (int) $user->telegram_id,
            'username'    => $user->name ?? $user->username,
            'token'       => $user->token,
            'client_uuid' => $user->client_uuid,
        ]);

        if ($legacyResult !== null) {
            $this->applyUserSyncResult($user, $legacyResult);
            return $legacyResult;
        }

        $result = $this->adminSync([
            'version' => 1,
            'request_id' => (string) Str::uuid(),
            'source' => 'laravel',
            'resource' => 'users',
            'action' => 'upsert',
            'occurred_at' => now()->toIso8601String(),
            'identity' => $this->identityPayload($user),
            'payload' => [
                'name' => $user->name,
                'username' => $user->username,
                'telegram_id' => $user->telegram_id ? (int) $user->telegram_id : null,
                'token' => $user->token,
                'client_uuid' => $user->client_uuid,
                'trial_used' => (bool) $user->trial_used,
                'has_password' => (bool) $user->has_password,
                'receives_payment_notifications' => (bool) $user->receives_payment_notifications,
            ],
            'meta' => ['reason' => 'admin_panel'],
        ]);

        if ($result !== null) {
            $this->applyUserSyncResult($user, $result);
        }

        return $result;
    }

    public function lastErrorMessage(): ?string
    {
        if (! $this->lastError) {
            return null;
        }

        $status = $this->lastError['status'] ?? 'no-status';
        $path = $this->lastError['path'] ?? 'Core API';
        $body = trim((string) ($this->lastError['body'] ?? ''));

        if ($body !== '') {
            $decoded = json_decode($body, true);
            if (is_array($decoded)) {
                $message = data_get($decoded, 'error.message')
                    ?? data_get($decoded, 'detail')
                    ?? data_get($decoded, 'message')
                    ?? $body;
            } else {
                $message = $body;
            }

            return "{$path} вернул {$status}: {$message}";
        }

        return "{$path} вернул {$status}";
    }

    public function adminUpsertPromoCode(PromoCode $promoCode): ?array
    {
        $payload = [
            'code' => $promoCode->code,
            'type' => $promoCode->type,
            'value' => $promoCode->value,
            'is_active' => (bool) $promoCode->is_active,
            'starts_at' => $promoCode->starts_at?->toIso8601String(),
            'expires_at' => $promoCode->expires_at?->toIso8601String(),
            'max_uses' => $promoCode->max_uses,
            'used_count' => $promoCode->used_count,
        ];

        $result = $this->syncRequest('promo_codes', 'upsert', $payload, [], [
            'type' => 'admin',
            'id' => session('admin_id'),
        ], null, 'promo_code:'.$promoCode->id.':upsert');

        if ($result !== null) {
            return $result;
        }

        foreach (['/admin/promocodes', '/admin/promos', '/admin/promo-codes'] as $path) {
            $result = $this->adminPost($path, $payload);
            if ($result !== null) {
                return $result;
            }
        }

        return null;
    }

    public function adminPromoCodes(int $limit = 500, int $offset = 0): ?array
    {
        $result = $this->syncRequest('promo_codes', 'list', [
            'limit' => $limit,
            'offset' => $offset,
        ], [], ['type' => 'admin', 'id' => session('admin_id')]);

        if ($result !== null) {
            return $result;
        }

        foreach ([
            "/admin/promocodes?limit={$limit}&offset={$offset}",
            "/admin/promos?limit={$limit}&offset={$offset}",
            "/admin/promo-codes?limit={$limit}&offset={$offset}",
        ] as $path) {
            $result = $this->adminGet($path);
            if ($result !== null) {
                return $result;
            }
        }

        return null;
    }

    public function adminDeletePromoCode(PromoCode $promoCode): ?array
    {
        $result = $this->syncRequest('promo_codes', 'delete', [
            'code' => $promoCode->code,
        ], [], ['type' => 'admin', 'id' => session('admin_id')]);

        if ($result !== null) {
            return $result;
        }

        foreach ([
            "/admin/promocodes/{$promoCode->code}/delete",
            "/admin/promos/{$promoCode->code}/delete",
            "/admin/promo-codes/{$promoCode->code}/delete",
        ] as $path) {
            $result = $this->adminPost($path, []);
            if ($result !== null) {
                return $result;
            }
        }

        return null;
    }

    // ──────────────────────────────────────────────────────────────
    // HTTP helpers
    // ──────────────────────────────────────────────────────────────

    private function get(string $path, array $query = [], ?string $bearerToken = null): ?array
    {
        try {
            $req = Http::timeout(8)->acceptJson();
            if ($bearerToken) {
                $req = $req->withToken($bearerToken);
            }
            $response = $req->get($this->baseUrl . $path, $query);
            return $this->handle($response, $path);
        } catch (\Throwable $e) {
            Log::error("CoreApi GET {$path} failed: " . $e->getMessage());
            return null;
        }
    }

    private function post(string $path, array $data = [], ?string $bearerToken = null): ?array
    {
        try {
            $req = Http::timeout(8)->acceptJson()->asJson();
            if ($bearerToken) {
                $req = $req->withToken($bearerToken);
            }
            $response = $req->post($this->baseUrl . $path, $data);
            return $this->handle($response, $path);
        } catch (\Throwable $e) {
            Log::error("CoreApi POST {$path} failed: " . $e->getMessage());
            return null;
        }
    }

    private function adminGet(string $path): ?array
    {
        try {
            $response = Http::timeout(8)
                ->acceptJson()
                ->withHeaders(['X-Admin-Key' => $this->adminKey])
                ->get($this->baseUrl . $path);
            return $this->handle($response, $path);
        } catch (\Throwable $e) {
            Log::error("CoreApi Admin GET {$path} failed: " . $e->getMessage());
            return null;
        }
    }

    public function resolveCoreUrl(?string $path): ?string
    {
        $path = trim((string) $path);
        if ($path === '') {
            return null;
        }

        if (Str::startsWith($path, ['http://', 'https://'])) {
            return $path;
        }

        if ($this->baseUrl === '') {
            return null;
        }

        return $this->baseUrl.'/'.ltrim($path, '/');
    }

    /**
     * Candidate URLs for release metadata. Core is preferred, APP_URL is a fallback
     * for deployments where Nginx serves /downloads next to Laravel.
     */
    private function clientLatestJsonUrls(?string $path): array
    {
        $path = trim((string) $path);
        if ($path === '') {
            return [];
        }

        if (Str::startsWith($path, ['http://', 'https://'])) {
            return [$path];
        }

        $urls = [];
        $appUrl = rtrim((string) config('app.url'), '/');
        if ($appUrl !== '' && Str::startsWith($path, '/downloads/')) {
            $urls[] = $appUrl.'/'.ltrim($path, '/');
        }

        if ($this->baseUrl !== '') {
            $urls[] = $this->baseUrl.'/'.ltrim($path, '/');
        }

        if ($appUrl !== '' && ! Str::startsWith($path, '/downloads/')) {
            $urls[] = $appUrl.'/'.ltrim($path, '/');
        }

        return array_values(array_unique($urls));
    }

    private function adminPost(string $path, array $data = []): ?array
    {
        try {
            $response = Http::timeout(8)
                ->acceptJson()
                ->asJson()
                ->withHeaders(['X-Admin-Key' => $this->adminKey])
                ->post($this->baseUrl . $path, $data);
            return $this->handle($response, $path);
        } catch (\Throwable $e) {
            Log::error("CoreApi Admin POST {$path} failed: " . $e->getMessage());
            return null;
        }
    }

    private function adminPut(string $path, array $data = []): ?array
    {
        try {
            $response = Http::timeout(8)
                ->acceptJson()
                ->asJson()
                ->withHeaders(['X-Admin-Key' => $this->adminKey])
                ->put($this->baseUrl . $path, $data);

            return $this->handle($response, $path);
        } catch (\Throwable $e) {
            Log::error("CoreApi Admin PUT {$path} failed: " . $e->getMessage());
            return null;
        }
    }

    private function adminDelete(string $path): ?array
    {
        try {
            $response = Http::timeout(8)
                ->acceptJson()
                ->withHeaders(['X-Admin-Key' => $this->adminKey])
                ->delete($this->baseUrl . $path);

            return $this->handle($response, $path);
        } catch (\Throwable $e) {
            Log::error("CoreApi Admin DELETE {$path} failed: " . $e->getMessage());
            return null;
        }
    }

    private function nodePayload(Node $node): array
    {
        return [
            'id' => $node->getKey(),
            'name' => $node->name,
            'ip' => $node->ip,
            'country' => $node->country,
            'city' => $node->city,
            'lat' => $node->lat,
            'lng' => $node->lng,
            'port' => $node->port,
            'api_port' => $node->api_port,
            'api_secret' => $node->api_secret,
            'status' => $node->status,
            'latency' => $node->latency,
            'load' => $node->load,
            'errors' => $node->errors,
            'is_active' => (bool) $node->is_active,
            'hidden_on_dashboard' => (bool) $node->hidden_on_dashboard,
        ];
    }

    private function syncRequest(
        string $resource,
        string $action,
        array $payload = [],
        array $identity = [],
        ?array $actor = null,
        ?string $bearerToken = null,
        ?string $idempotencyKey = null,
    ): ?array {
        if ($this->baseUrl === '') {
            return null;
        }

        $requestId = (string) Str::uuid();
        $body = [
            'version' => 1,
            'request_id' => $requestId,
            'source' => 'laravel',
            'resource' => $resource,
            'action' => $action,
            'occurred_at' => now()->toIso8601String(),
            'payload' => $payload,
            'meta' => [
                'reason' => $actor ? 'admin_panel' : 'web',
                'idempotency_key' => $idempotencyKey ?? $requestId,
            ],
        ];

        if ($identity !== []) {
            $body['identity'] = $identity;
        }

        if ($actor !== null) {
            $body['actor'] = $actor;
        }

        try {
            $request = Http::timeout(8)
                ->acceptJson()
                ->asJson()
                ->withHeaders([
                    'X-Admin-Key' => $this->adminKey,
                    'X-Request-Id' => $requestId,
                ]);

            if ($bearerToken) {
                $request = $request->withToken($bearerToken);
            }

            $response = $request->post($this->baseUrl . '/api/sync', $this->normalizeSyncBody($body));
            $result = $this->handle($response, '/api/sync');

            if (! is_array($result)) {
                return null;
            }

            return array_key_exists('data', $result) && is_array($result['data'])
                ? $result['data']
                : $result;
        } catch (\Throwable $e) {
            $this->lastError = [
                'path' => '/api/sync',
                'status' => null,
                'body' => $e->getMessage(),
            ];
            Log::error('CoreApi POST /api/sync failed: ' . $e->getMessage(), [
                'resource' => $resource,
                'action' => $action,
            ]);

            return null;
        }
    }

    private function adminSync(array $payload, ?string $requestId = null): ?array
    {
        $requestId ??= (string) ($payload['request_id'] ?? Str::uuid());

        try {
            $response = Http::timeout(8)
                ->acceptJson()
                ->asJson()
                ->withHeaders([
                    'X-Admin-Key' => $this->adminKey,
                    'X-Request-Id' => $requestId,
                ])
                ->post($this->baseUrl . '/api/sync', $this->normalizeSyncBody($payload));

            return $this->handle($response, '/api/sync');
        } catch (\Throwable $e) {
            $this->lastError = [
                'path' => '/api/sync',
                'status' => null,
                'body' => $e->getMessage(),
            ];
            Log::error('CoreApi Admin POST /api/sync failed: ' . $e->getMessage());

            return null;
        }
    }

    private function ensureUserSyncIdentity(User $user): User
    {
        $dirty = false;

        if (! $user->token) {
            $user->token = (string) Str::uuid();
            $dirty = true;
        }

        if (! $user->client_uuid) {
            $user->client_uuid = (string) Str::uuid();
            $dirty = true;
        }

        if ($dirty) {
            $user->save();
        }

        return $user;
    }

    private function normalizeSyncBody(array $body): array
    {
        foreach (['identity', 'payload', 'meta', 'actor'] as $field) {
            if (array_key_exists($field, $body) && $body[$field] === []) {
                $body[$field] = (object) [];
            }
        }

        return $body;
    }

    private function identityPayload(User $user): array
    {
        return [
            'laravel_user_id' => $user->id,
            'core_user_id' => $user->core_user_id ? (int) $user->core_user_id : null,
            'telegram_id' => $user->telegram_id ? (int) $user->telegram_id : null,
            'token' => $user->token,
            'client_uuid' => $user->client_uuid,
        ];
    }

    private function applyUserSyncResult(User $user, array $result): void
    {
        $data = $result['data'] ?? $result['user'] ?? $result['result'] ?? $result;
        if (! is_array($data)) {
            return;
        }

        $updates = [];
        foreach ([
            'core_user_id' => ['core_user_id', 'user_id', 'id'],
            'token' => ['token', 'access_token'],
            'client_uuid' => ['client_uuid', 'uuid'],
        ] as $attribute => $keys) {
            foreach ($keys as $key) {
                $value = data_get($data, $key);
                if ($value !== null && $value !== '') {
                    $updates[$attribute] = $value;
                    break;
                }
            }
        }

        if ($updates) {
            $user->forceFill($updates)->save();
        }
    }

    private function handle(Response $response, string $path): ?array
    {
        $this->lastError = null;

        if ($response->successful()) {
            $json = $response->json();
            if (is_array($json) && array_key_exists('ok', $json) && $json['ok'] === false) {
                $this->lastError = [
                    'path' => $path,
                    'status' => $response->status(),
                    'body' => $response->body(),
                ];

                Log::warning("CoreApi {$path} returned ok=false", [
                    'body' => $response->body(),
                ]);

                return null;
            }

            return $json;
        }

        $this->lastError = [
            'path' => $path,
            'status' => $response->status(),
            'body' => $response->body(),
        ];

        Log::warning("CoreApi {$path} returned {$response->status()}", [
            'body' => $response->body(),
        ]);

        return null;
    }
}
