<?php

namespace App\Http\Controllers;

use App\Services\CoreClient;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Illuminate\View\View;
use Throwable;

class WebController extends Controller
{
    public function __construct(private readonly CoreClient $core)
    {
    }

    public function index(): View
    {
        return view('home', $this->publicData());
    }

    public function pricing(): View
    {
        return view('pricing', $this->publicData());
    }

    public function access(): View
    {
        return view('access', $this->publicData());
    }

    public function loginPage(Request $request): View|RedirectResponse
    {
        if ($this->token($request) !== null) {
            return redirect('/dashboard');
        }

        return view('auth', $this->publicData(['mode' => 'login']));
    }

    public function registerPage(Request $request): View|RedirectResponse
    {
        if ($this->token($request) !== null) {
            return redirect('/dashboard');
        }

        return view('auth', $this->publicData(['mode' => 'register']));
    }

    public function login(Request $request): RedirectResponse
    {
        $data = $request->validate([
            'email' => ['required', 'email'],
            'password' => ['required', 'string'],
        ]);

        try {
            $tokens = $this->core->login($data['email'], $data['password']);
            $request->session()->put('wavebreak_tokens', $tokens);
        } catch (Throwable) {
            return back()->withInput($request->only('email'))->withErrors([
                'email' => 'Не удалось войти. Проверьте email и пароль.',
            ]);
        }

        return redirect('/dashboard');
    }

    public function register(Request $request): RedirectResponse
    {
        $data = $request->validate([
            'email' => ['required', 'email'],
            'password' => ['required', 'string', 'min:10'],
        ]);

        try {
            $result = $this->core->register($data['email'], $data['password']);
            $request->session()->put('wavebreak_tokens', $result['tokens']);
        } catch (Throwable) {
            return back()->withInput($request->only('email'))->withErrors([
                'email' => 'Не удалось создать аккаунт. Возможно, этот email уже зарегистрирован.',
            ]);
        }

        return redirect('/dashboard');
    }

    public function dashboard(Request $request): View|RedirectResponse
    {
        return $this->dashboardSection($request, 'overview');
    }

    public function subscription(Request $request): View|RedirectResponse
    {
        return $this->dashboardSection($request, 'subscription');
    }

    public function accessDashboard(Request $request): View|RedirectResponse
    {
        return $this->dashboardSection($request, 'access');
    }

    public function nodes(Request $request): View|RedirectResponse
    {
        return $this->dashboardSection($request, 'nodes');
    }

    public function devices(Request $request): View|RedirectResponse
    {
        return $this->dashboardSection($request, 'devices');
    }

    private function dashboardSection(Request $request, string $section): View|RedirectResponse
    {
        $token = $this->token($request);
        if ($token === null) {
            return redirect('/login');
        }

        return view('dashboard', [
            'section' => $section,
            'me' => $this->core->me($token),
            'overview' => $this->core->overview($token),
            'plans' => $this->core->plans(),
            'subscription' => $this->core->currentSubscription($token),
            'usage' => $this->core->usage($token),
            'usageHistory' => $this->core->usageHistory($token),
            'devices' => $this->core->devices($token),
            'nodes' => $this->core->locations($token),
            'grants' => $this->core->grants($token),
        ]);
    }

    public function subscribe(Request $request): RedirectResponse
    {
        $data = $request->validate(['plan_id' => ['required', 'uuid']]);
        $token = $this->token($request);
        if ($token === null) {
            return redirect('/login');
        }

        try {
            $this->core->createSubscription($token, $data['plan_id']);
        } catch (Throwable) {
            return back()->withErrors(['plan_id' => 'Не удалось активировать тариф. Попробуйте еще раз.']);
        }

        return redirect('/dashboard/subscription')->with('success', 'Тариф активирован.');
    }

    public function grant(Request $request): RedirectResponse
    {
        $data = $request->validate([
            'node_id' => ['required', 'uuid'],
            'protocol' => ['required', 'string'],
        ]);
        $token = $this->token($request);
        if ($token === null) {
            return redirect('/login');
        }

        try {
            $this->core->createGrant($token, $data['node_id'], $data['protocol']);
        } catch (Throwable) {
            return back()->withErrors(['node_id' => 'Не удалось выдать доступ. Проверьте выбранную ноду.']);
        }

        return redirect('/dashboard/access')->with('success', 'Доступ создан.');
    }

    public function revokeGrant(Request $request, string $grantId): RedirectResponse
    {
        $token = $this->token($request);
        if ($token === null) {
            return redirect('/login');
        }

        try {
            $this->core->revokeGrant($token, $grantId);
        } catch (Throwable) {
            return back()->withErrors(['grant' => 'Не удалось отозвать доступ.']);
        }

        return redirect('/dashboard/access')->with('success', 'Доступ отозван.');
    }

    public function createDevice(Request $request): RedirectResponse
    {
        $data = $request->validate([
            'name' => ['required', 'string', 'max:120'],
            'platform' => ['nullable', 'string', 'max:80'],
        ]);
        $token = $this->token($request);
        if ($token === null) {
            return redirect('/login');
        }

        try {
            $this->core->createDevice($token, $data['name'], $data['platform'] ?? '');
        } catch (Throwable) {
            return back()->withErrors(['device' => 'Не удалось добавить устройство. Проверьте лимит тарифа.']);
        }

        return redirect('/dashboard/devices')->with('success', 'Устройство добавлено.');
    }

    public function createTelegramLink(Request $request): RedirectResponse
    {
        $token = $this->token($request);
        if ($token === null) {
            return redirect('/login');
        }

        try {
            $link = $this->core->createTelegramLink($token);
            $request->session()->flash('telegram_link_token', $link['token'] ?? '');
        } catch (Throwable) {
            return back()->withErrors(['telegram' => 'Не удалось создать Telegram link token.']);
        }

        return redirect('/dashboard/devices')->with('success', 'Telegram link token создан на 15 минут.');
    }

    public function unlinkTelegram(Request $request): RedirectResponse
    {
        $token = $this->token($request);
        if ($token === null) {
            return redirect('/login');
        }

        try {
            $this->core->unlinkTelegram($token);
        } catch (Throwable) {
            return back()->withErrors(['telegram' => 'Не удалось отвязать Telegram.']);
        }

        return redirect('/dashboard/devices')->with('success', 'Telegram отвязан.');
    }

    public function logout(Request $request): RedirectResponse
    {
        $refreshToken = $request->session()->get('wavebreak_tokens.refresh_token');
        if ($refreshToken !== null) {
            $this->core->logout($refreshToken);
        }
        $request->session()->forget('wavebreak_tokens');

        return redirect('/');
    }

    private function token(Request $request): ?string
    {
        return $request->session()->get('wavebreak_tokens.access_token');
    }

    private function publicData(array $extra = []): array
    {
        return array_merge([
            'health' => $this->core->health(),
            'plans' => $this->core->plans(),
        ], $extra);
    }
}
