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

class TelegramAuthController extends Controller
{
    public function login(Request $request): RedirectResponse
    {
        $token = $request->query('token')
            ?? $request->query('login_token')
            ?? $request->query('tg_token')
            ?? $request->route('token');
        $sessionKey = $request->query('session_key');

        if (! $token) {
            return redirect()->route('login')->withErrors(['username' => 'Неверная ссылка для входа.']);
        }

        try {
            $verification = $this->verifyLoginToken((string) $token);

            if (! ($verification['ok'] ?? false)) {
                Log::warning('Telegram login token verification rejected', [
                    'status' => $verification['status'] ?? null,
                    'body' => $verification['body'] ?? null,
                ]);

                $message = match ((int) ($verification['status'] ?? 0)) {
                    404 => 'Ссылка для входа не найдена. Если вы впервые открыли бота, нажмите Start и повторите вход с сайта.',
                    409, 410 => 'Ссылка для входа уже использована или истекла. Вернитесь на страницу входа и нажмите «Войти через Telegram» ещё раз.',
                    429 => 'Слишком много попыток входа через Telegram. Подождите минуту и попробуйте снова.',
                    default => 'Не удалось подтвердить Telegram-вход. Откройте бота, нажмите Start и запросите новую ссылку со страницы входа.',
                };

                return redirect()->route('login')
                    ->withErrors(['username' => $message]);
            }

            $data = $verification['data'] ?? [];

            if (! ($data['ok'] ?? false) || (empty($data['telegram_id']) && empty($data['username']) && empty($data['telegram_username']))) {
                Log::warning('Telegram login verification returned incomplete payload', [
                    'keys' => array_keys((array) $data),
                ]);

                return redirect()->route('login')
                    ->withErrors(['username' => 'Бот не вернул данные аккаунта. Нажмите Start в Telegram-боте и повторите вход с сайта.']);
            }
        } catch (\Throwable $e) {
            Log::error('Telegram login verification failed: ' . $e->getMessage());

            return redirect()->route('login')
                ->withErrors(['username' => 'Не удалось связаться с Telegram-ботом. Нажмите Start в боте и повторите вход через несколько секунд.']);
        }

        $user = $this->resolveUser($data);

        if (! $user) {
            Log::warning('Telegram login user not found', [
                'telegram_id' => $data['telegram_id'] ?? null,
                'username' => $data['username'] ?? null,
                'telegram_username' => $data['telegram_username'] ?? null,
            ]);

            return redirect()->route('login')
                ->withErrors(['username' => 'Аккаунт не найден. Войдите по логину и паролю, затем подключите Telegram в профиле.']);
        }

        Auth::login($user, true);
        $request->session()->regenerate();

        if ($sessionKey) {
            Cache::put(
                "tg_login_session_{$sessionKey}",
                ['user_id' => $user->id, 'authenticated' => true],
                now()->addMinutes(5),
            );
        }

        return redirect()->route('profile.index')
            ->with('success', 'Вы вошли через Telegram.');
    }

    public function status(Request $request): JsonResponse
    {
        $sessionKey = $request->query('session_key');

        if ($sessionKey) {
            $cached = Cache::get("tg_login_session_{$sessionKey}");
            if ($cached && ($cached['authenticated'] ?? false)) {
                $user = User::query()->find($cached['user_id']);
                if ($user) {
                    Auth::login($user, true);
                    $request->session()->regenerate();
                    Cache::forget("tg_login_session_{$sessionKey}");

                    return response()->json([
                        'authenticated' => true,
                        'redirect' => route('profile.index'),
                    ]);
                }
            }
        }

        return response()->json([
            'authenticated' => Auth::check(),
            'redirect' => Auth::check() ? route('profile.index') : null,
        ]);
    }

    private function resolveUser(array $data): ?User
    {
        $telegramId = $data['telegram_id'] ?? null;
        $telegramUsername = $data['telegram_username'] ?? $data['username'] ?? null;

        if ($telegramId !== null && ctype_digit((string) $telegramId)) {
            $user = User::query()->where('telegram_id', (string) $telegramId)->first();
            if ($user) {
                return $user;
            }
        }

        if ($telegramUsername) {
            $username = ltrim((string) $telegramUsername, '@');
            $user = User::query()
                ->where('username', $username)
                ->orWhere('name', $username)
                ->first();

            if ($user && $telegramId !== null && ctype_digit((string) $telegramId) && empty($user->telegram_id)) {
                $user->forceFill(['telegram_id' => (string) $telegramId])->save();
            }

            return $user;
        }

        return null;
    }

    private function verifyLoginToken(string $token): array
    {
        $coreUrl = rtrim((string) config('services.core.url'), '/');
        if ($coreUrl === '') {
            return ['ok' => false, 'status' => 0, 'body' => 'CORE_API_URL is empty'];
        }

        try {
            $response = Http::timeout(5)
                ->acceptJson()
                ->get($coreUrl . '/auth/verify-login-token', [
                    'token' => $token,
                ]);

            if (! $response->successful()) {
                return ['ok' => false, 'status' => $response->status(), 'body' => $response->body()];
            }

            $data = $response->json() ?? [];
            $data['ok'] = (bool) ($data['ok'] ?? true);

            return ['ok' => true, 'status' => $response->status(), 'data' => $data];
        } catch (\Throwable $e) {
            return ['ok' => false, 'status' => 0, 'body' => $e->getMessage()];
        }
    }
}
