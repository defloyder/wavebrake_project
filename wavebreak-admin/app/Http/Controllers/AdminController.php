<?php

namespace App\Http\Controllers;

use App\Services\CoreClient;
use App\Services\AdminAssistant;
use Illuminate\Http\Client\RequestException;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Illuminate\View\View;

class AdminController extends Controller
{
    public function __construct(
        private readonly CoreClient $core,
        private readonly AdminAssistant $assistant,
    )
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

    // Polled every few seconds by the live-traffic widget (see
    // dashboard.blade.php) — deliberately tiny (one number, not the whole
    // per-subscription breakdown /traffic already loads) so polling it
    // doesn't get heavier than the thing it's watching. The widget itself
    // computes the delta between polls; this just reports the current
    // cumulative total across every subscription right now.
    public function trafficLive(Request $request): \Illuminate\Http\JsonResponse
    {
        $token = $this->token($request);
        if ($token === null) {
            return response()->json(['error' => 'unauthenticated'], 401);
        }
        try {
            $rows = $this->core->traffic($token);
        } catch (RequestException $e) {
            return response()->json(['error' => 'core unavailable'], $e->response->status() === 401 ? 401 : 502);
        }
        $totalBytes = array_sum(array_map(fn ($row) => $row['bytes_total'] ?? 0, $rows));

        return response()->json(['total_bytes' => $totalBytes, 'timestamp' => now()->toIso8601String()]);
    }

    // Polled by the health badge in the sidebar header on every admin page
    // (see layout.blade.php) — a dead node agent produces no error anywhere
    // else in the system, just a growing gap since its last usage report,
    // so this is the only way anyone would notice without reading raw logs.
    public function trafficHealth(Request $request): \Illuminate\Http\JsonResponse
    {
        $token = $this->token($request);
        if ($token === null) {
            return response()->json(['error' => 'unauthenticated'], 401);
        }
        try {
            return response()->json($this->core->trafficHealth($token));
        } catch (RequestException $e) {
            return response()->json(['error' => 'core unavailable'], $e->response->status() === 401 ? 401 : 502);
        }
    }

    public function audit(Request $request): View|RedirectResponse
    {
        return $this->renderAdminPage($request, 'audit');
    }

    public function assistantMessage(Request $request): \Illuminate\Http\JsonResponse
    {
        $token = $this->assistantToken($request);
        if ($token === null) {
            return response()->json(['error' => 'Сессия истекла. Войдите снова.'], 401);
        }

        $data = $request->validate(['message' => ['required', 'string', 'max:500']]);
        try {
            $context = $request->session()->get('admin_assistant_context');
            $reply = $this->assistant->reply($token, $data['message'], is_array($context) ? $context : null);
            if (array_key_exists('context', $reply)) {
                if (is_array($reply['context'])) {
                    $request->session()->put('admin_assistant_context', $reply['context']);
                } else {
                    $request->session()->forget('admin_assistant_context');
                }
                unset($reply['context']);
            }
            if (isset($reply['confirmation']['action'])) {
                $confirmationToken = (string) \Illuminate\Support\Str::uuid();
                $request->session()->put("admin_assistant_actions.{$confirmationToken}", [
                    'action' => $reply['confirmation']['action'],
                    'expires_at' => now()->addMinutes(5)->timestamp,
                ]);
                unset($reply['confirmation']['action']);
                $reply['confirmation']['token'] = $confirmationToken;
            }
            return response()->json($reply);
        } catch (RequestException $e) {
            return response()->json(['error' => 'Не удалось получить данные системы.'], $e->response->status() === 401 ? 401 : 502);
        }
    }

    public function assistantConfirm(Request $request): \Illuminate\Http\JsonResponse
    {
        $token = $this->assistantToken($request);
        if ($token === null) {
            return response()->json(['error' => 'Сессия истекла. Войдите снова.'], 401);
        }

        $data = $request->validate(['token' => ['required', 'uuid']]);
        $key = "admin_assistant_actions.{$data['token']}";
        $pending = $request->session()->pull($key);
        if (! is_array($pending) || ($pending['expires_at'] ?? 0) < now()->timestamp) {
            return response()->json(['error' => 'Подтверждение истекло. Повторите команду.'], 422);
        }

        try {
            return response()->json($this->assistant->execute($token, $pending['action'] ?? []));
        } catch (RequestException $e) {
            return response()->json(['error' => $e->response->json('error') ?? 'Действие не выполнено.'], $e->response->status() === 401 ? 401 : 502);
        }
    }

    private function assistantToken(Request $request): ?string
    {
        $token = $this->token($request);
        if ($token === null) {
            return null;
        }
        try {
            $me = $this->core->me($token);
            return in_array($me['role'] ?? 'user', ['admin', 'superadmin'], true) ? $token : null;
        } catch (RequestException) {
            return null;
        }
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

        return $this->coreAction($request, '/users', 'Роль обновлена.', fn ($token) => $this->core->updateUserRole($token, $userId, $data['role']));
    }

    public function disableUser(Request $request, string $userId): RedirectResponse
    {
        return $this->coreAction($request, '/users', 'Пользователь заблокирован.', fn ($token) => $this->core->disableUser($token, $userId));
    }

    public function enableUser(Request $request, string $userId): RedirectResponse
    {
        return $this->coreAction($request, '/users', 'Пользователь разблокирован.', fn ($token) => $this->core->enableUser($token, $userId));
    }

    public function deleteUser(Request $request, string $userId): RedirectResponse
    {
        $token = $this->token($request);
        if ($token === null) {
            return redirect('/login');
        }
        try {
            $me = $this->core->me($token);
            if (($me['role'] ?? '') !== 'superadmin') {
                return redirect('/users')->with('error', 'Удаление пользователей доступно только superadmin.');
            }
            if (($me['id'] ?? '') === $userId) {
                return redirect('/users')->with('error', 'Нельзя удалить собственную учётную запись.');
            }
        } catch (RequestException) {
            return redirect('/login');
        }

        return $this->coreAction($request, '/users', 'Пользователь и связанные данные удалены.', fn ($accessToken) => $this->core->deleteUser($accessToken, $userId));
    }

    public function createPlan(Request $request): RedirectResponse
    {
        $data = $this->validatedPlan($request);

        return $this->coreAction($request, '/plans', 'Тариф создан.', fn ($token) => $this->core->createPlan($token, $data));
    }

    public function updatePlan(Request $request, string $planId): RedirectResponse
    {
        $data = $this->validatedPlan($request);

        return $this->coreAction($request, '/plans', 'Тариф обновлён.', fn ($token) => $this->core->updatePlan($token, $planId, $data));
    }

    public function deletePlan(Request $request, string $planId): RedirectResponse
    {
        return $this->coreAction($request, '/plans', 'Тариф удалён.', fn ($token) => $this->core->deletePlan($token, $planId));
    }

    public function revokeDevice(Request $request, string $deviceId): RedirectResponse
    {
        return $this->coreAction($request, '/devices', 'Устройство отозвано.', fn ($token) => $this->core->revokeDevice($token, $deviceId));
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
        try {
            $tokens = $this->core->login($data['email'], $data['password']);
        } catch (RequestException) {
            return back()->withInput($request->only('email'))->withErrors(['email' => 'Неверный email или пароль.']);
        }
        $request->session()->put('wavebreak_admin_tokens', $tokens);

        return redirect('/dashboard');
    }

    public function enrollNode(Request $request): RedirectResponse
    {
        $data = $request->validate([
            'code' => ['required', 'string'],
            'region' => ['required', 'string'],
        ]);

        return $this->coreAction($request, '/nodes', "Нода {$data['code']} зарегистрирована.", fn ($token) => $this->core->enrollNode($token, $data['code'], $data['region']));
    }

    public function revokeGrant(Request $request, string $grantId): RedirectResponse
    {
        $data = $request->validate([
            'reason' => ['nullable', 'string', 'max:160'],
        ]);

        return $this->coreAction($request, '/grants', 'Подключение отозвано.', fn ($token) => $this->core->revokeGrant($token, $grantId, $data['reason'] ?? 'admin'));
    }

    public function updateSubscriptionStatus(Request $request, string $subscriptionId): RedirectResponse
    {
        $data = $request->validate([
            'status' => ['required', 'string', 'in:pending,active,expired,cancelled,suspended'],
        ]);

        return $this->coreAction($request, '/subscriptions', 'Статус подписки обновлён.', fn ($token) => $this->core->updateSubscriptionStatus($token, $subscriptionId, $data['status']));
    }

    // Every mutating admin action funnels through here: runs $action with
    // the current token, flashes a success message on the way back to
    // $redirectTo, and turns whatever Core says on failure into something
    // an admin can actually read instead of a raw Laravel 500 — a 401
    // means the session expired mid-click (same handling as
    // renderAdminPage), anything else surfaces Core's own error message
    // when it sent one.
    private function coreAction(Request $request, string $redirectTo, string $successMessage, \Closure $action): RedirectResponse
    {
        $token = $this->token($request);
        if ($token === null) {
            return redirect('/login');
        }
        try {
            $action($token);

            return redirect($redirectTo)->with('success', $successMessage);
        } catch (RequestException $e) {
            if ($e->response->status() === 401) {
                $request->session()->forget('wavebreak_admin_tokens');

                return redirect('/login')->withErrors(['email' => 'Сессия истекла, войдите снова.']);
            }
            $message = $e->response->json('error') ?? $e->response->json('code') ?? 'Не удалось выполнить действие.';

            return redirect($redirectTo)->with('error', is_string($message) ? $message : 'Не удалось выполнить действие.');
        }
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
