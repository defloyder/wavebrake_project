<?php

namespace App\Services;

use Illuminate\Http\Client\PendingRequest;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Str;

class CoreClient
{
    public function health(): array
    {
        return $this->safe()->get('/healthz')->json() ?? [];
    }

    public function login(string $email, string $password): array
    {
        return $this->base()->post('/v1/auth/login', compact('email', 'password'))->throw()->json();
    }

    public function me(string $token): array
    {
        return $this->auth($token, true)->get('/v1/me')->throw()->json();
    }

    public function plans(): array
    {
        return $this->safe()->get('/v1/plans')->throw()->json('plans') ?? [];
    }

    public function adminPlans(string $token): array
    {
        return $this->auth($token, true)->get('/v1/admin/plans')->throw()->json('plans') ?? [];
    }

    public function createPlan(string $token, array $data): array
    {
        return $this->auth($token)->post('/v1/admin/plans', $data)->throw()->json();
    }

    public function updatePlan(string $token, string $planId, array $data): array
    {
        return $this->auth($token)->put("/v1/admin/plans/{$planId}", $data)->throw()->json();
    }

    public function deletePlan(string $token, string $planId): array
    {
        return $this->auth($token)->delete("/v1/admin/plans/{$planId}")->throw()->json();
    }

    public function nodes(string $token): array
    {
        return $this->auth($token, true)->get('/v1/nodes')->throw()->json('nodes') ?? [];
    }

    public function dashboard(string $token): array
    {
        return $this->auth($token, true)->get('/v1/admin/dashboard')->throw()->json();
    }

    public function users(string $token): array
    {
        return $this->auth($token, true)->get('/v1/admin/users')->throw()->json('users') ?? [];
    }

    public function updateUserRole(string $token, string $userId, string $role): array
    {
        return $this->auth($token)->patch("/v1/admin/users/{$userId}/role", compact('role'))->throw()->json();
    }

    public function disableUser(string $token, string $userId): array
    {
        return $this->auth($token)->post("/v1/admin/users/{$userId}/disable")->throw()->json();
    }

    public function enableUser(string $token, string $userId): array
    {
        return $this->auth($token)->post("/v1/admin/users/{$userId}/enable")->throw()->json();
    }

    public function subscriptions(string $token): array
    {
        return $this->auth($token, true)->get('/v1/admin/subscriptions')->throw()->json('subscriptions') ?? [];
    }

    public function updateSubscriptionStatus(string $token, string $subscriptionId, string $status): array
    {
        return $this->auth($token)->patch("/v1/admin/subscriptions/{$subscriptionId}/status", compact('status'))->throw()->json();
    }

    public function devices(string $token): array
    {
        return $this->auth($token, true)->get('/v1/admin/devices')->throw()->json('devices') ?? [];
    }

    public function traffic(string $token): array
    {
        return $this->auth($token, true)->get('/v1/admin/traffic')->throw()->json('traffic') ?? [];
    }

    public function trafficHistory(string $token, int $days = 30): array
    {
        return $this->auth($token, true)->get('/v1/admin/traffic/history', compact('days'))->throw()->json('history') ?? [];
    }

    public function revokeDevice(string $token, string $deviceId): array
    {
        return $this->auth($token)->post("/v1/admin/devices/{$deviceId}/revoke")->throw()->json();
    }

    public function audit(string $token): array
    {
        return $this->auth($token, true)->get('/v1/admin/audit')->throw()->json('events') ?? [];
    }

    public function grants(string $token): array
    {
        return $this->auth($token, true)->get('/v1/admin/access/grants')->throw()->json('grants') ?? [];
    }

    public function revokeGrant(string $token, string $grantId, string $reason): array
    {
        return $this->auth($token)->post("/v1/admin/access/grants/{$grantId}/revoke", compact('reason'))->throw()->json();
    }

    public function enrollNode(string $token, string $code, string $region): array
    {
        return $this->auth($token)->post('/v1/nodes/enroll', compact('code', 'region'))->throw()->json();
    }

    private function base(): PendingRequest
    {
        return Http::baseUrl(rtrim(config('services.wavebreak.core_url'), '/'))
            ->withHeaders(['X-Request-ID' => request()?->headers->get('X-Request-ID', (string) Str::uuid())])
            ->acceptJson()
            ->asJson()
            ->timeout(5);
    }

    private function safe(): PendingRequest
    {
        return $this->base()->retry(2, 100);
    }

    private function auth(string $token, bool $safe = false): PendingRequest
    {
        return ($safe ? $this->safe() : $this->base())->withToken($token);
    }
}
