<?php

namespace App\Services;

use App\Models\User;
use App\Notifications\WebPushNotification;
use Illuminate\Support\Facades\Log;

class WebPushService
{
    public function isConfigured(): bool
    {
        return filled(config('webpush.vapid.public_key')) && filled(config('webpush.vapid.private_key'));
    }

    public function sendToUser(int $userId, string $title, string $body, string $type = 'info'): void
    {
        if (! $this->isConfigured()) {
            Log::warning('WebPush: VAPID keys not configured, skipping push notification');
            return;
        }

        $user = User::query()->find($userId);

        if (! $user) {
            Log::warning("WebPush: user {$userId} not found");
            return;
        }

        $subscriptionsCount = $user->pushSubscriptions()->count();

        Log::info("WebPush: sending to user {$userId}, subscriptions={$subscriptionsCount}");

        if ($subscriptionsCount === 0) {
            return;
        }

        try {
            $user->notify(new WebPushNotification($title, $body, $type));
        } catch (\Throwable $e) {
            Log::error("WebPush: failed to send to user {$userId}: {$e->getMessage()}", [
                'exception' => $e::class,
            ]);
        }
    }

    public function sendToAll(string $title, string $body, string $type = 'info'): void
    {
        if (! $this->isConfigured()) {
            Log::warning('WebPush: VAPID keys not configured, skipping push notification');
            return;
        }

        User::query()
            ->whereHas('pushSubscriptions')
            ->with('pushSubscriptions')
            ->chunkById(200, function ($users) use ($title, $body, $type): void {
                Log::info("WebPush: sending broadcast chunk, users={$users->count()}");

                foreach ($users as $user) {
                    try {
                        $user->notify(new WebPushNotification($title, $body, $type));
                    } catch (\Throwable $e) {
                        Log::error("WebPush: failed to send broadcast to user {$user->id}: {$e->getMessage()}", [
                            'exception' => $e::class,
                        ]);
                    }
                }
            });
    }
}
