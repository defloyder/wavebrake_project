<?php

namespace App\Http\Controllers;

use App\Models\AccountRecoveryToken;
use App\Models\User;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;
use Illuminate\View\View;

class AccountRecoveryController extends Controller
{
    private const REQUEST_TTL_MINUTES = 15;
    private const RESET_TTL_MINUTES = 15;
    private const SUPPORT_URL = 'https://t.me/auralith_support';

    public function showRequest(): View
    {
        return $this->forgotView([
            'supportUrl' => self::SUPPORT_URL,
            'supportMessage' => $this->supportMessage(),
        ]);
    }

    public function request(Request $request): View|RedirectResponse
    {
        $data = $request->validate([
            'identifier' => ['required', 'string', 'max:120'],
        ]);

        $identifier = trim($data['identifier']);
        $user = $this->findUser($identifier);

        if (! $user || empty($user->telegram_id)) {
            return redirect()->away(self::SUPPORT_URL);
        }

        $botUsername = config('services.telegram.bot_username', 'auralithaccessbot');
        $activeToken = Cache::get($this->requestCacheKey($user));

        if ($activeToken && $this->findActiveRequestToken($activeToken)) {
            return $this->forgotView([
                'supportUrl' => self::SUPPORT_URL,
                'recoveryStarted' => true,
                'deepLink' => "https://t.me/{$botUsername}?start=recover_{$activeToken}",
                'tgDeepLink' => "tg://resolve?domain={$botUsername}&start=recover_{$activeToken}",
                'manualCommand' => "/start recover_{$activeToken}",
                'statusUrl' => route('account-recovery.status', ['token' => $activeToken]),
                'expiresIn' => self::REQUEST_TTL_MINUTES,
            ]);
        }

        AccountRecoveryToken::query()
            ->where('user_id', $user->id)
            ->whereNull('used_at')
            ->update(['used_at' => now()]);

        $requestToken = Str::random(48);
        $requestTokenHash = $this->hashToken($requestToken);

        AccountRecoveryToken::query()->create([
            'user_id' => $user->id,
            'request_token_hash' => $requestTokenHash,
            'identifier' => $identifier,
            'ip' => $request->ip(),
            'user_agent' => substr((string) $request->userAgent(), 0, 1000),
            'expires_at' => now()->addMinutes(self::REQUEST_TTL_MINUTES),
        ]);

        Cache::put($this->requestCacheKey($user), $requestToken, now()->addMinutes(self::REQUEST_TTL_MINUTES));

        return $this->forgotView([
            'supportUrl' => self::SUPPORT_URL,
            'recoveryStarted' => true,
            'deepLink' => "https://t.me/{$botUsername}?start=recover_{$requestToken}",
            'tgDeepLink' => "tg://resolve?domain={$botUsername}&start=recover_{$requestToken}",
            'manualCommand' => "/start recover_{$requestToken}",
            'statusUrl' => route('account-recovery.status', ['token' => $requestToken]),
            'expiresIn' => self::REQUEST_TTL_MINUTES,
        ]);
    }

    public function status(string $token): JsonResponse
    {
        $recovery = $this->findActiveRequestToken($token);

        if (! $recovery) {
            return response()->json([
                'ok' => false,
                'expired' => true,
                'message' => 'Запрос восстановления не найден или истёк. Если вы открывали несколько ссылок, используйте последнюю команду с этой страницы или создайте новый запрос.',
                'support_url' => self::SUPPORT_URL,
            ], 404);
        }

        if (! $recovery->confirmed_at) {
            return response()->json([
                'ok' => true,
                'confirmed' => false,
            ]);
        }

        $resetToken = Cache::get($this->resetCacheKey($recovery));

        if (! $resetToken) {
            $resetToken = Str::random(72);
            $recovery->forceFill([
                'reset_token_hash' => $this->hashToken($resetToken),
                'expires_at' => now()->addMinutes(self::RESET_TTL_MINUTES),
            ])->save();

            Cache::put($this->resetCacheKey($recovery), $resetToken, now()->addMinutes(self::RESET_TTL_MINUTES));
        }

        return response()->json([
            'ok' => true,
            'confirmed' => true,
            'redirect' => route('account-recovery.reset.show', ['token' => $resetToken]),
        ]);
    }

    public function confirmTelegram(Request $request): JsonResponse
    {
        $data = $request->validate([
            'recovery_token' => ['required', 'string', 'min:20', 'max:120'],
            'telegram_id' => ['required', 'integer'],
        ]);

        $recovery = $this->findActiveRequestToken($data['recovery_token']);

        if (! $recovery) {
            return response()->json([
                'ok' => false,
                'error' => 'Token not found or expired',
                'message' => 'Запрос восстановления не найден или истёк. Откройте последнюю ссылку с сайта или запросите восстановление заново.',
            ], 404);
        }

        $user = $recovery->user;

        if (! $user || (string) $user->telegram_id !== (string) $data['telegram_id']) {
            return response()->json([
                'ok' => false,
                'error' => 'Telegram account does not match',
                'message' => 'Этот Telegram не привязан к выбранному аккаунту.',
            ], 403);
        }

        if (! $recovery->confirmed_at) {
            $recovery->forceFill(['confirmed_at' => now()])->save();
        }

        Cache::forget($this->requestCacheKey($user));

        return response()->json(['ok' => true]);
    }

    public function showReset(string $token): View|RedirectResponse
    {
        $recovery = $this->findActiveResetToken($token);

        if (! $recovery) {
            return redirect()->route('account-recovery.request')
                ->withErrors(['identifier' => 'Ссылка восстановления устарела. Запросите новую или напишите в поддержку.']);
        }

        return view('public-react', [
            'page' => 'reset-access',
            'bodyClass' => 'auth-page',
            'meta' => ['title' => 'Auralith | Новый пароль', 'robots' => 'noindex, nofollow'],
            'props' => [
            'token' => $token,
            'username' => $recovery->user?->username,
            'supportUrl' => self::SUPPORT_URL,
            'action' => route('account-recovery.reset.submit', ['token' => $token], false),
            'errors' => session('errors')?->all() ?? [],
            ],
        ]);
    }

    public function reset(Request $request, string $token): RedirectResponse
    {
        $data = $request->validate([
            'password' => ['required', 'string', 'min:8', 'confirmed'],
        ]);

        $recovery = $this->findActiveResetToken($token);

        if (! $recovery) {
            return redirect()->route('account-recovery.request')
                ->withErrors(['identifier' => 'Ссылка восстановления устарела. Запросите новую или напишите в поддержку.']);
        }

        $user = $recovery->user;

        DB::transaction(function () use ($user, $recovery, $data): void {
            $user->forceFill([
                'password' => Hash::make($data['password']),
                'has_password' => true,
            ])->save();

            $recovery->forceFill(['used_at' => now()])->save();

            DB::table('sessions')->where('user_id', $user->id)->delete();
        });

        Cache::forget($this->resetCacheKey($recovery));
        Cache::forget($this->requestCacheKey($user));

        return redirect()->route('login')
            ->with('success', 'Пароль обновлён. Теперь можно войти по логину ' . $user->username . ' и новому паролю.');
    }

    public function createAdminResetLink(User $user): JsonResponse
    {
        AccountRecoveryToken::query()
            ->where('user_id', $user->id)
            ->whereNull('used_at')
            ->update(['used_at' => now()]);

        $resetToken = Str::random(72);

        AccountRecoveryToken::query()->create([
            'user_id' => $user->id,
            'request_token_hash' => $this->hashToken(Str::random(48)),
            'reset_token_hash' => $this->hashToken($resetToken),
            'identifier' => 'admin:' . (session('admin_id') ?? 'unknown'),
            'ip' => request()->ip(),
            'user_agent' => substr((string) request()->userAgent(), 0, 1000),
            'confirmed_at' => now(),
            'expires_at' => now()->addMinutes(self::RESET_TTL_MINUTES),
        ]);

        return response()->json([
            'ok' => true,
            'reset_url' => route('account-recovery.reset.show', ['token' => $resetToken]),
            'expires_in_minutes' => self::RESET_TTL_MINUTES,
            'message' => "Здравствуйте! Для восстановления доступа к Auralith откройте ссылку и задайте новый пароль. Ссылка действует " . self::RESET_TTL_MINUTES . " минут: " . route('account-recovery.reset.show', ['token' => $resetToken]),
        ]);
    }

    private function forgotView(array $props): View
    {
        return view('public-react', [
            'page' => 'forgot-access',
            'bodyClass' => 'auth-page',
            'meta' => ['title' => 'Auralith | Восстановление доступа', 'robots' => 'noindex, nofollow'],
            'props' => $props + [
                'errors' => session('errors')?->all() ?? [],
            ],
        ] + $props);
    }

    private function findUser(string $identifier): ?User
    {
        $value = trim($identifier);
        $username = ltrim($value, '@');

        return User::query()
            ->where('username', $username)
            ->orWhere('name', $username)
            ->when(ctype_digit($value), fn ($query) => $query->orWhere('telegram_id', $value))
            ->first();
    }

    private function findActiveRequestToken(string $token): ?AccountRecoveryToken
    {
        return AccountRecoveryToken::query()
            ->with('user')
            ->where('request_token_hash', $this->hashToken($token))
            ->whereNull('used_at')
            ->where('expires_at', '>', now())
            ->first();
    }

    private function findActiveResetToken(string $token): ?AccountRecoveryToken
    {
        return AccountRecoveryToken::query()
            ->with('user')
            ->where('reset_token_hash', $this->hashToken($token))
            ->whereNotNull('confirmed_at')
            ->whereNull('used_at')
            ->where('expires_at', '>', now())
            ->first();
    }

    private function hashToken(string $token): string
    {
        return hash('sha256', $token);
    }

    private function resetCacheKey(AccountRecoveryToken $recovery): string
    {
        return "account_recovery_reset_{$recovery->id}";
    }

    private function requestCacheKey(User $user): string
    {
        return "account_recovery_request_user_{$user->id}";
    }

    private function supportMessage(?string $identifier = null, ?Request $request = null): string
    {
        $lines = [
            'Здравствуйте! Не получается восстановить доступ к Auralith.',
            'Прошу помочь восстановить вход в личный кабинет.',
        ];

        if ($identifier) {
            $lines[] = 'Указанный логин: ' . $identifier;
        }

        if ($request) {
            $lines[] = 'Время обращения: ' . now()->format('d.m.Y H:i');
            $lines[] = 'IP: ' . $request->ip();
        }

        $lines[] = 'Готов подтвердить оплату/заказ и данные аккаунта.';

        return implode("\n", $lines);
    }
}
