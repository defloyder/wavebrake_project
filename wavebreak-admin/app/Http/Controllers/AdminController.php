<?php

namespace App\Http\Controllers;

use App\Services\CoreClient;
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

        $me = $this->core->me($token);
        if (! in_array(($me['role'] ?? 'user'), ['admin', 'superadmin'], true)) {
            $request->session()->forget('wavebreak_admin_tokens');
            return redirect('/')->withErrors(['email' => 'Admin role is required.']);
        }

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
            'auditEvents' => $this->core->audit($token),
        ]);
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
