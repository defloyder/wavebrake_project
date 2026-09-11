<?php

namespace App\Http\Controllers;

use App\Models\PasswordChangeRequest;
use App\Services\CoreApiService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Str;

class PasswordChangeController extends Controller
{
    private const TTL_MINUTES = 10;

    public function __construct(private readonly CoreApiService $core) {}

    public function request(Request $request): JsonResponse
    {
        $user = Auth::user();

        if (empty($user->telegram_id)) {
            return response()->json([
                'ok' => false,
                'message' => 'Сначала подключите Telegram в блоке уведомлений.',
            ], 422);
        }

        $activeRequest = PasswordChangeRequest::query()
            ->where('user_id', $user->id)
            ->where('status', 'pending')
            ->whereNull('used_at')
            ->where('expires_at', '>', now())
            ->latest()
            ->first();

        if (! $activeRequest) {
            PasswordChangeRequest::query()
                ->where('user_id', $user->id)
                ->whereIn('status', ['pending', 'confirmed'])
                ->whereNull('used_at')
                ->update([
                    'status' => 'cancelled',
                    'cancelled_at' => now(),
                ]);

            $activeRequest = PasswordChangeRequest::query()->create([
                'user_id' => $user->id,
                'pwd_token' => (string) Str::uuid(),
                'status' => 'pending',
                'expires_at' => now()->addMinutes(self::TTL_MINUTES),
            ]);
        }

        try {
            $this->sendToCore($user->telegram_id, $activeRequest->pwd_token);
        } catch (\Throwable $e) {
            return response()->json([
                'ok' => false,
                'message' => 'Не удалось отправить подтверждение в Telegram. Попробуйте ещё раз позже.',
            ], 502);
        }

        return response()->json([
            'ok' => true,
            'pwd_token' => $activeRequest->pwd_token,
            'status_url' => route('profile.password-change.status', ['pwdToken' => $activeRequest->pwd_token]),
            'expires_in' => self::TTL_MINUTES * 60,
        ]);
    }

    public function status(string $pwdToken): JsonResponse
    {
        $passwordChange = PasswordChangeRequest::query()
            ->where('pwd_token', $pwdToken)
            ->where('user_id', Auth::id())
            ->whereNull('used_at')
            ->first();

        if (
            $passwordChange
            && $passwordChange->status === 'confirmed'
            && $passwordChange->expires_at <= now()
            && $passwordChange->confirmed_at
            && $passwordChange->confirmed_at->gt(now()->subMinutes(self::TTL_MINUTES))
        ) {
            $passwordChange->forceFill([
                'expires_at' => $passwordChange->confirmed_at->copy()->addMinutes(self::TTL_MINUTES),
            ])->save();
        }

        if (! $passwordChange || $passwordChange->expires_at <= now()) {
            return response()->json([
                'ok' => false,
                'status' => 'expired',
                'message' => 'Подтверждение устарело. Запросите смену пароля заново.',
            ], 404);
        }

        return response()->json([
            'ok' => true,
            'status' => $passwordChange->status,
            'confirmed' => $passwordChange->status === 'confirmed',
            'cancelled' => $passwordChange->status === 'cancelled',
        ]);
    }

    public function confirm(Request $request): JsonResponse
    {
        $data = $request->validate([
            'pwd_token' => ['required', 'uuid'],
            'action' => ['required', 'string'],
        ]);

        $action = match ($data['action']) {
            'confirm', 'confirmed', 'approve', 'approved' => 'confirm',
            'cancel', 'cancelled', 'decline', 'declined' => 'cancel',
            default => null,
        };

        if (! $action) {
            return response()->json([
                'ok' => false,
                'message' => 'Неизвестное действие подтверждения.',
            ], 422);
        }

        $passwordChange = PasswordChangeRequest::query()
            ->where('pwd_token', $data['pwd_token'])
            ->whereNull('used_at')
            ->first();

        if (! $passwordChange) {
            return response()->json([
                'ok' => false,
                'message' => 'Запрос смены пароля не найден или истёк.',
            ], 404);
        }

        if ($action === 'confirm') {
            $passwordChange->forceFill([
                'status' => 'confirmed',
                'confirmed_at' => $passwordChange->confirmed_at ?? now(),
                'cancelled_at' => null,
                'expires_at' => now()->addMinutes(self::TTL_MINUTES),
            ])->save();
        } else {
            $passwordChange->forceFill([
                'status' => 'cancelled',
                'cancelled_at' => $passwordChange->cancelled_at ?? now(),
            ])->save();
        }

        return response()->json(['ok' => true]);
    }

    private function sendToCore(int|string $telegramId, string $pwdToken): void
    {
        $result = $this->core->sendPasswordChangeConfirmation($telegramId, $pwdToken);
        if ($result !== null) {
            return;
        }

        $coreUrl = rtrim((string) config('services.core.url'), '/');

        if ($coreUrl === '') {
            throw new \RuntimeException('CORE_API_URL is not configured.');
        }

        Http::timeout(5)
            ->acceptJson()
            ->asJson()
            ->post($coreUrl . '/auth/password-change/send', [
                'telegram_id' => (int) $telegramId,
                'pwd_token' => $pwdToken,
            ])
            ->throw();
    }
}
