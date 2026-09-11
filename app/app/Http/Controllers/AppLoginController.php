<?php

namespace App\Http\Controllers;

use App\Models\User;
use App\Services\CoreApiService;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Schema;
use Illuminate\View\View;

class AppLoginController extends Controller
{
    public function __construct(private readonly CoreApiService $core) {}

    public function show(Request $request): View
    {
        $sessionKey = $this->sessionKey($request);
        $client = $this->clientName($request);

        if (! $sessionKey) {
            return $this->reactView([
                'invalidLink' => true,
                'confirmed' => false,
                'sessionKey' => null,
                'client' => $client,
            ]);
        }

        return $this->reactView([
            'invalidLink' => false,
            'confirmed' => false,
            'sessionKey' => $sessionKey,
            'client' => $client,
        ]);
    }

    public function submit(Request $request): View|RedirectResponse
    {
        $sessionKey = $this->sessionKey($request);
        $client = $this->clientName($request);

        if (! $sessionKey) {
            return $this->reactView([
                'invalidLink' => true,
                'confirmed' => false,
                'sessionKey' => null,
                'client' => $client,
            ]);
        }

        if (! Auth::check()) {
            $credentials = $request->validate([
                'login' => ['required', 'string'],
                'password' => ['required', 'string'],
            ]);

            if (! $this->attemptAppLogin($credentials['login'], $credentials['password'], $request)) {
                return back()
                    ->withErrors(['login' => 'Неверный логин или пароль.'])
                    ->withInput(['login' => $credentials['login']]);
            }
        }

        $user = Auth::user();
        if (! $user || empty($user->telegram_id)) {
            return $this->reactView([
                'invalidLink' => false,
                'confirmed' => false,
                'sessionKey' => $sessionKey,
                'client' => $client,
                'coreError' => true,
            ]);
        }

        $result = $this->core->createAppLoginToken(
            $user->telegram_id,
            $user->username ?: $user->name,
            $sessionKey,
        );

        if (! is_array($result) || empty($result['login_token'])) {
            return $this->reactView([
                'invalidLink' => false,
                'confirmed' => false,
                'sessionKey' => $sessionKey,
                'client' => $client,
                'coreError' => true,
            ]);
        }

        return $this->reactView([
            'invalidLink' => false,
            'confirmed' => true,
            'sessionKey' => $sessionKey,
            'client' => $client,
        ]);
    }

    private function sessionKey(Request $request): ?string
    {
        $sessionKey = (string) $request->query('session_key', $request->input('session_key', ''));
        $sessionKey = trim($sessionKey);

        return preg_match('/^[A-Za-z0-9]{32}$/', $sessionKey) ? $sessionKey : null;
    }

    private function clientName(Request $request): string
    {
        $client = strtolower((string) $request->query('client', $request->input('client', 'app')));

        return match ($client) {
            'windows' => 'Windows',
            'android' => 'Android',
            default => 'Auralith',
        };
    }

    private function attemptAppLogin(string $login, string $password, Request $request): bool
    {
        $query = User::query()->where('username', $login);

        if (Schema::hasColumn('users', 'email')) {
            $query->orWhere('email', $login);
        }

        $query->orWhere('name', $login);

        $user = $query->first();
        if (! $user || ! Hash::check($password, (string) $user->password)) {
            return false;
        }

        Auth::login($user, true);
        $request->session()->regenerate();

        return true;
    }

    private function reactView(array $props): View
    {
        return view('public-react', [
            'page' => 'app-login',
            'bodyClass' => 'auth-page',
            'meta' => ['title' => 'Auralith | Вход в приложение', 'robots' => 'noindex, nofollow'],
            'props' => $props + [
                'errors' => session('errors')?->all() ?? [],
                'authenticated' => Auth::check(),
                'action' => route('app-login.submit', [
                    'session_key' => $props['sessionKey'] ?? null,
                    'client' => strtolower($props['client'] ?? 'app'),
                ], false),
            ],
        ]);
    }
}
