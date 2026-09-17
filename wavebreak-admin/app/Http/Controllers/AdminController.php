<?php

namespace App\Http\Controllers;

use App\Services\CoreClient;
use Illuminate\Http\Client\RequestException;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Illuminate\View\View;

class AdminController extends Controller
{
    public function __construct(private readonly CoreClient $core)
    {
    }

    public function index(Request $request): View|RedirectResponse
    {
        if ($this->token($request) !== null) {
            return redirect('/dashboard');
        }

        return view('login', ['health' => $this->core->health()]);
    }

    public function loginPage(Request $request): View|RedirectResponse
    {
        return $this->index($request);
    }

    public function dashboard(Request $request): View|RedirectResponse
    {
        return $this->renderAdminPage($request, 'dashboard');
    }

    public function nodes(Request $request): View|RedirectResponse
    {
        return $this->renderAdminPage($request, 'nodes');
    }

    public function plans(Request $request): View|RedirectResponse
    {
        return $this->renderAdminPage($request, 'plans');
    }

    public function enroll(Request $request): View|RedirectResponse
    {
        return $this->renderAdminPage($request, 'enroll');
    }

    public function users(Request $request): View|RedirectResponse
    {
        return $this->renderAdminPage($request, 'users');
    }

    public function subscriptions(Request $request): View|RedirectResponse
    {
        return $this->renderAdminPage($request, 'subscriptions');
    }

    public function grants(Request $request): View|RedirectResponse
    {
        return $this->renderAdminPage($request, 'grants');
    }

    public function devices(Request $request): View|RedirectResponse
    {
        return $this->renderAdminPage($request, 'devices');
    }

    public function traffic(Request $request): View|RedirectResponse
    {
        return $this->renderAdminPage($request, 'traffic');
    }

    public function audit(Request $request): View|RedirectResponse
    {
        return $this->renderAdminPage($request, 'audit');
    }

    private function renderAdminPage(Request $request, string $section): View|RedirectResponse
    {
        $token = $this->token($request);
        if ($token === null) {
            return view('login', ['health' => $this->core->health()]);
        }

        // The Core JWT is short-lived (15 min) and this app has no refresh-
        // token flow yet, so a session left open past that window used to
        // surface as a raw 500 (uncaught RequestException from the first
        // Core call to fail) instead of just asking the admin to sign back
        // in — same session, no data lost, just a fresh token.
        try {
            $me = $this->core->me($token);
            if (! in_array(($me['role'] ?? 'user'), ['admin', 'superadmin'], true)) {
                $request->session()->forget('wavebreak_admin_tokens');
                return redirect('/')->withErrors(['email' => 'Admin role is required.']);
            }

            $needsTraffic = in_array($section, ['dashboard', 'traffic'], true);

            return view('dashboard', [
                'section' => $section,
                'me' => $me,
                'health' => $this->core->health(),
                'plans' => $this->core->adminPlans($token),
                'nodes' => $this->core->nodes($token),
                'dashboard' => $this->core->dashboard($token),
                'users' => $this->core->users($token),
                'subscriptions' => $this->core->subscriptions($token),
                'grants' => $this->core->grants($token),
                'devices' => $this->core->devices($token),
                'traffic' => $this->core->traffic($token),
                'trafficHistory' => $needsTraffic ? $this->core->trafficHistory($token, 30) : [],
                'auditEvents' => $this->core->audit($token),
            ]);
        } catch (RequestException $e) {
            if ($e->response->status() === 401) {
                $request->session()->forget('wavebreak_admin_tokens');
                return redirect('/login')->withErrors(['email' => 'Сессия истекла, войдите снова.']);
            }
            throw $e;
        }
    }

    public function updateUserRole(Request $request, string $userId): RedirectResponse
    {
        $data = $request->validate([
            'role' => ['required', 'string', 'in:user,support,admin,superadmin'],
        ]);
        $this->core->updateUserRole($this->token($request), $userId, $data['role']);

        return redirect('/users')->with('success', 'Роль обновлена.');
    }

    public function disableUser(Request $request, string $userId): RedirectResponse
    {
        $this->core->disableUser($this->token($request), $userId);

        return redirect('/users')->with('success', 'Пользователь заблокирован.');
    }

    public function enableUser(Request $request, string $userId): RedirectResponse
    {
        $this->core->enableUser($this->token($request), $userId);

        return redirect('/users')->with('success', 'Пользователь разблокирован.');
    }

    public function createPlan(Request $request): RedirectResponse
    {
        $data = $this->validatedPlan($request);
        $this->core->createPlan($this->token($request), $data);

        return redirect('/plans')->with('success', 'Тариф создан.');
    }

    public function updatePlan(Request $request, string $planId): RedirectResponse
    {
        $data = $this->validatedPlan($request);
        $this->core->updatePlan($this->token($request), $planId, $data);

        return redirect('/plans')->with('success', 'Тариф обновлён.');
    }

    public function deletePlan(Request $request, string $planId): RedirectResponse
    {
        $this->core->deletePlan($this->token($request), $planId);

        return redirect('/plans')->with('success', 'Тариф удалён.');
    }

    public function revokeDevice(Request $request, string $deviceId): RedirectResponse
    {
        $this->core->revokeDevice($this->token($request), $deviceId);

        return redirect('/devices')->with('success', 'Устройство отозвано.');
    }

    private function validatedPlan(Request $request): array
    {
        $data = $request->validate([
            'code' => ['required', 'string', 'max:60'],
            'name' => ['required', 'string', 'max:120'],
            'description' => ['nullable', 'string', 'max:500'],
            'price_minor' => ['required', 'integer', 'min:0'],
            'currency' => ['nullable', 'string', 'max:6'],
            'interval' => ['required', 'string', 'in:month,year'],
            'device_limit' => ['required', 'integer', 'min:1'],
            'traffic_limit_bytes' => ['nullable', 'integer', 'min:0'],
            'is_active' => ['nullable', 'boolean'],
            'is_public' => ['nullable', 'boolean'],
            'sort_order' => ['nullable', 'integer'],
        ]);
        $data['is_active'] = $request->boolean('is_active', true);
        $data['is_public'] = $request->boolean('is_public', true);
        $data['sort_order'] = (int) ($data['sort_order'] ?? 0);
        if (empty($data['traffic_limit_bytes'])) {
            $data['traffic_limit_bytes'] = null;
        }

        return $data;
    }

    public function login(Request $request): RedirectResponse
    {
        $data = $request->validate([
            'email' => ['required', 'email'],
            'password' => ['required', 'string'],
        ]);
        $tokens = $this->core->login($data['email'], $data['password']);
        $request->session()->put('wavebreak_admin_tokens', $tokens);

        return redirect('/dashboard');
    }

    public function enrollNode(Request $request): RedirectResponse
    {
        $data = $request->validate([
            'code' => ['required', 'string'],
            'region' => ['required', 'string'],
        ]);
        $this->core->enrollNode($this->token($request), $data['code'], $data['region']);

        return redirect('/nodes');
    }

    public function revokeGrant(Request $request, string $grantId): RedirectResponse
    {
        $data = $request->validate([
            'reason' => ['nullable', 'string', 'max:160'],
        ]);
        $this->core->revokeGrant($this->token($request), $grantId, $data['reason'] ?? 'admin');

        return redirect('/grants');
    }

    public function updateSubscriptionStatus(Request $request, string $subscriptionId): RedirectResponse
    {
        $data = $request->validate([
            'status' => ['required', 'string', 'in:pending,active,expired,cancelled,suspended'],
        ]);
        $this->core->updateSubscriptionStatus($this->token($request), $subscriptionId, $data['status']);

        return redirect('/subscriptions');
    }

    public function logout(Request $request): RedirectResponse
    {
        $request->session()->forget('wavebreak_admin_tokens');

        return redirect('/');
    }

    private function token(Request $request): ?string
    {
        return $request->session()->get('wavebreak_admin_tokens.access_token');
    }
}
