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

    public function plans(): array
    {
        return $this->safe()->get('/v1/plans')->json('plans') ?? [];
    }

    public function register(string $email, string $password): array
    {
        return $this->base()->post('/v1/auth/register', compact('email', 'password'))->throw()->json();
    }

    public function login(string $email, string $password): array
    {
        return $this->base()->post('/v1/auth/login', compact('email', 'password'))->throw()->json();
    }

    public function me(string $token): array
    {
        return $this->auth($token, true)->get('/v1/me')->throw()->json();
    }

    public function overview(string $token): array
    {
        return $this->auth($token, true)->get('/v1/me/overview')->throw()->json();
    }

    public function currentSubscription(string $token): ?array
    {
        $response = $this->auth($token)->get('/v1/subscriptions/current');
        return $response->ok() ? $response->json() : null;
    }

    public function createSubscription(string $token, string $planId): array
    {
        return $this->auth($token)->post('/v1/subscriptions', ['plan_id' => $planId])->throw()->json();
    }

    public function locations(string $token): array
    {
        return $this->auth($token, true)->get('/v1/locations')->throw()->json('nodes') ?? [];
    }

    public function grants(string $token): array
    {
        return $this->auth($token, true)->get('/v1/access/grants')->throw()->json('grants') ?? [];
    }

    public function usage(string $token): ?array
    {
        $response = $this->auth($token)->get('/v1/me/usage');
        return $response->ok() ? $response->json() : null;
    }

    public function usageHistory(string $token, string $period = '7d'): array
    {
        $response = $this->auth($token)->get('/v1/me/usage/history', ['period' => $period]);
        return $response->ok() ? ($response->json('history') ?? []) : [];
    }

    public function devices(string $token): array
    {
        return $this->auth($token, true)->get('/v1/me/devices')->throw()->json('devices') ?? [];
    }

    public function createDevice(string $token, string $name, string $platform): array
    {
        return $this->auth($token)->post('/v1/me/devices', compact('name', 'platform'))->throw()->json();
    }

    public function createTelegramLink(string $token): array
    {
        return $this->auth($token)->post('/v1/me/identities/telegram/link')->throw()->json();
    }

    public function unlinkTelegram(string $token): void
    {
        $this->auth($token)->delete('/v1/me/identities/telegram')->throw();
    }

    public function createGrant(string $token, string $nodeId, string $protocol, ?string $deviceId = null): array
    {
        return $this->auth($token)->post('/v1/access/grants', [
            'node_id' => $nodeId,
            'protocol' => $protocol,
            'device_id' => $deviceId,
        ])->throw()->json();
    }

    public function revokeGrant(string $token, string $grantId): array
    {
        return $this->auth($token)->post("/v1/access/grants/{$grantId}/revoke")->throw()->json();
    }

    public function logout(string $refreshToken): void
    {
        $this->base()->post('/v1/auth/logout', ['refresh_token' => $refreshToken])->throw();
    }

    private function base(): PendingRequest
    {
        return Http::baseUrl(rtrim(config('services.wavebreak.core_url'), '/'))
            ->withHeaders(['X-Request-ID' => request()?->headers->get('X-Request-ID', (string) Str::uuid())])
            ->acceptJson()
            ->asJson()
            ->connectTimeout(2)
            ->timeout(5);
    }

    private function safe(): PendingRequest
    {
        return $this->base()
            ->connectTimeout(0.35)
            ->timeout(0.35);
    }

    private function auth(string $token, bool $safe = false): PendingRequest
    {
        return ($safe ? $this->safe() : $this->base())->withToken($token);
    }
}
