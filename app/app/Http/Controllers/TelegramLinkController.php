<?php

namespace App\Http\Controllers;

use App\Models\User;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Str;

class TelegramLinkController extends Controller
{
    private const TTL = 600; // 10 minutes

    /**
     * Generate a link token and return deep-link.
     * Called via AJAX from the profile page.
     * POST /profile/telegram/link-token
     */
    public function generateToken(Request $request): JsonResponse
    {
        $user = Auth::user();

        $oldKey = "tg_link_user_{$user->id}";
        $botUsername = config('services.telegram.bot_username', 'auralithaccessbot');

        if (($oldToken = Cache::get($oldKey)) && Cache::has("tg_link_{$oldToken}")) {
            return response()->json([
                'link_token' => $oldToken,
                'deep_link'  => "https://t.me/{$botUsername}?start={$oldToken}",
                'tg_link'    => "tg://resolve?domain={$botUsername}&start={$oldToken}",
                'manual_command' => "/start {$oldToken}",
                'expires_in' => self::TTL,
                'reused' => true,
            ]);
        }

        $token = (string) Str::uuid();

        // Store: token → user_id
        Cache::put("tg_link_{$token}", $user->id, self::TTL);
        // Store: user_id → token (for invalidation)
        Cache::put($oldKey, $token, self::TTL);

        return response()->json([
            'link_token' => $token,
            'deep_link'  => "https://t.me/{$botUsername}?start={$token}",
            'tg_link'    => "tg://resolve?domain={$botUsername}&start={$token}",
            'manual_command' => "/start {$token}",
            'expires_in' => self::TTL,
        ]);
    }

    /**
     * Poll endpoint — check if telegram was linked.
     * GET /profile/telegram/status
     */
    public function status(): JsonResponse
    {
        $user = Auth::user()->fresh();

        return response()->json([
            'linked'           => ! empty($user->telegram_id),
            'telegram_id'      => $user->telegram_id,
        ]);
    }

    /**
     * Webhook called by Core API / Bot after successful linking.
     * POST /webhook/telegram-link  (no auth — protected by token)
     */
    public function handle(Request $request): JsonResponse
    {
        $data = $request->validate([
            'link_token'  => ['required', 'uuid'],
            'telegram_id' => ['required', 'integer'],
            'username'    => ['nullable', 'string'],
        ]);

        $userId = Cache::get("tg_link_{$data['link_token']}");

        if (! $userId) {
            $consumedLink = Cache::get("tg_link_consumed_{$data['link_token']}");

            if (
                is_array($consumedLink)
                && (string) ($consumedLink['telegram_id'] ?? '') === (string) $data['telegram_id']
            ) {
                return response()->json(['ok' => true]);
            }

            return response()->json([
                'ok' => false,
                'error' => 'Token not found or expired',
                'message' => 'Токен привязки не найден или истёк. Создайте новую ссылку в профиле.',
            ], 404);
        }

        // Check if telegram_id already linked to another user
        $conflict = User::query()
            ->where('telegram_id', $data['telegram_id'])
            ->where('id', '!=', $userId)
            ->exists();

        if ($conflict) {
            return response()->json([
                'ok' => false,
                'error' => 'Telegram already linked to another account',
                'message' => 'Этот Telegram уже привязан к другому аккаунту.',
            ], 409);
        }

        $user = User::query()->findOrFail($userId);

        // Update telegram_id in Laravel DB
        $user->update([
            'telegram_id' => $data['telegram_id'],
        ]);

        // Sync user to Core API database
        $this->syncUserToCoreApi($user);

        // Clean up tokens
        Cache::put("tg_link_consumed_{$data['link_token']}", [
            'user_id' => $userId,
            'telegram_id' => (string) $data['telegram_id'],
        ], self::TTL);
        Cache::forget("tg_link_{$data['link_token']}");
        Cache::forget("tg_link_user_{$userId}");

        return response()->json(['ok' => true]);
    }

    public function confirm(Request $request): JsonResponse
    {
        return $this->handle($request);
    }

    /**
     * Sync user data to Core API database.
     * Creates or updates user in Core API with Laravel user's token and client_uuid.
     */
    private function syncUserToCoreApi(User $user): void
    {
        try {
            Http::timeout(5)
                ->acceptJson()
                ->asJson()
                ->post(config('services.core.url') . '/webhook/sync-user', [
                    'telegram_id' => $user->telegram_id,
                    'username'    => $user->name,
                    'token'       => $user->token,
                    'client_uuid' => $user->client_uuid,
                ]);
        } catch (\Throwable $e) {
            Log::error("Failed to sync user to Core API: " . $e->getMessage());
        }
    }

    /**
     * Unlink Telegram from profile.
     * DELETE /profile/telegram/unlink
     */
    public function unlink(): JsonResponse
    {
        $user = Auth::user();

        if (empty($user->telegram_id)) {
            return response()->json(['error' => 'No Telegram linked'], 400);
        }

        $user->update(['telegram_id' => null]);

        return response()->json(['ok' => true]);
    }
}
