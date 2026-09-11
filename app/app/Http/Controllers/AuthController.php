<?php

namespace App\Http\Controllers;

use App\Models\User;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;
use Illuminate\View\View;

class AuthController extends Controller
{
    public function showLogin(): View|RedirectResponse
    {
        if (Auth::check()) {
            return redirect()->route('profile.index');
        }
        return view('public-react', [
            'page' => 'login',
            'bodyClass' => 'auth-page',
            'meta' => ['title' => 'Auralith | Вход', 'robots' => 'noindex, nofollow'],
            'props' => [
                'errors' => session('errors')?->all() ?? [],
                'success' => session('success'),
                'telegramError' => request('telegram_error'),
            ],
        ]);
    }

    public function login(Request $request): RedirectResponse
    {
        $data = $request->validate([
            'username' => ['required', 'string'],
            'password' => ['required', 'string'],
        ]);

        if (! Auth::attempt(['username' => $data['username'], 'password' => $data['password']], true)) {
            return back()
                ->withErrors(['username' => 'Неверное имя пользователя или пароль.'])
                ->onlyInput('username');
        }

        $request->session()->regenerate();
        return redirect()->route('profile.index');
    }

    public function showRegister(): View|RedirectResponse
    {
        if (Auth::check()) {
            return redirect()->route('profile.index');
        }
        return view('public-react', [
            'page' => 'register',
            'bodyClass' => 'auth-page',
            'meta' => ['title' => 'Auralith | Регистрация', 'robots' => 'noindex, nofollow'],
            'props' => [
                'errors' => session('errors')?->all() ?? [],
            ],
        ]);
    }

    public function register(Request $request): RedirectResponse
    {
        $data = $request->validate([
            'username' => ['required', 'string', 'max:60', 'unique:users,username', 'regex:/^[a-zA-Z0-9_]+$/'],
            'password' => ['required', 'string', 'min:8', 'confirmed'],
            'privacy_consent' => ['accepted'],
            'offer_acceptance' => ['accepted'],
        ]);

        // Check if username conflicts with auto-generated usernames from Core API import
        // Auto-generated usernames have format: user{telegram_id}
        $user = User::query()->create([
            'name'        => $data['username'],
            'username'    => $data['username'],
            'password'    => Hash::make($data['password']),
            'token'       => Str::uuid(),
            'client_uuid' => Str::uuid(),
            'has_password'=> true,
        ]);

        Auth::login($user, true);
        $request->session()->regenerate();

        return redirect()->route('profile.index')
            ->with('success', 'Добро пожаловать! Аккаунт создан.');
    }

    public function logout(Request $request): RedirectResponse
    {
        Auth::logout();
        $request->session()->invalidate();
        $request->session()->regenerateToken();
        return redirect()->route('home');
    }
}
