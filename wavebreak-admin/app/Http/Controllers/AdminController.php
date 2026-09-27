<?php

namespace App\Http\Controllers;

use App\Services\AdminAssistant;
use App\Services\Core\CoreApiException;
use App\Services\CoreClient;
use App\Services\UserAdministration\CoreErrorMessages;
use App\Support\ByteFormatter;
use App\View\Admin\AdminPageBuilder;
use Illuminate\Http\Client\RequestException;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Str;
use Illuminate\View\View;

/**
 * Admin pages and the page-level actions (create user, plans, node
 * enrollment, sign-in). Per-user actions live in the user card
 * (UserDetailsController).
 */
class AdminController extends Controller
{
    public function __construct(
        private readonly CoreClient $core,
        private readonly AdminAssistant $assistant,
        private readonly AdminPageBuilder $pages,
        private readonly CoreErrorMessages $messages,
    ) {}

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

    public function section(Request $request, string $section): View|RedirectResponse
    {
        $token = $this->token($request);
        if ($token === null) {
            return view('login', ['health' => $this->core->health()]);
        }

        // The Core JWT is short-lived and this app has no refresh flow yet,
        // so an expired session is sent back to sign in instead of a 500.
        try {
            $me = $this->core->me($token);
            if (! in_array(($me['role'] ?? 'user'), ['admin', 'superadmin'], true)) {
                $request->session()->forget('wavebreak_admin_tokens');

                return redirect('/')->withErrors(['email' => 'Нужна роль администратора.']);
            }

            return view('dashboard', $this->pages->build($token, $section, $me));
        } catch (RequestException $e) {
            if ($e->response->status() === 401) {
                $request->session()->forget('wavebreak_admin_tokens');

                return redirect('/login')->withErrors(['email' => 'Сессия истекла, войдите снова.']);
            }
            throw $e;
        }
    }

    // Polled every few seconds by the live-traffic widget — one number, the
    // cumulative total across every subscription; the widget computes the
    // delta between polls.
    public function trafficLive(Request $request): JsonResponse
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

    // Polled by the health chip in the header on every admin page: a dead
    // node agent produces no error anywhere else, just a growing gap since
    // its last usage report.
    public function trafficHealth(Request $request): JsonResponse
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

    public function assistantMessage(Request $request): JsonResponse
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
                $confirmationToken = (string) Str::uuid();
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

    public function assistantConfirm(Request $request): JsonResponse
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

    public function createUser(Request $request): RedirectResponse|JsonResponse
    {
        $data = $request->validate([
            'email' => ['required', 'email:rfc', 'max:254'],
            'username' => ['nullable', 'string', 'max:80'],
            'password' => ['required', 'string', 'min:10', 'max:200'],
            'role' => ['required', 'string', 'in:user,support,admin,superadmin'],
            'status' => ['required', 'string', 'in:active,disabled'],
        ]);
        $data['email'] = mb_strtolower(trim($data['email']));
        $data['username'] = trim($data['username'] ?? '');

        return $this->coreAction($request, '/users', 'Пользователь создан.', fn ($token) => $this->core->createUser($token, $data));
    }

    public function createPlan(Request $request): RedirectResponse|JsonResponse
    {
        $data = $this->validatedPlan($request);

        return $this->coreAction($request, '/plans', 'Тариф создан.', fn ($token) => $this->core->createPlan($token, $data));
    }

    public function updatePlan(Request $request, string $planId): RedirectResponse|JsonResponse
    {
        $data = $this->validatedPlan($request);

        return $this->coreAction($request, '/plans', 'Тариф сохранён.', fn ($token) => $this->core->updatePlan($token, $planId, $data));
    }

    public function deletePlan(Request $request, string $planId): RedirectResponse|JsonResponse
    {
        return $this->coreAction($request, '/plans', 'Тариф удалён.', fn ($token) => $this->core->deletePlan($token, $planId));
    }

    /**
     * The plan form speaks operator units (price in currency, traffic in
     * ГБ); Core stores minor units and bytes.
     */
    private function validatedPlan(Request $request): array
    {
        $data = $request->validate([
            'code' => ['required', 'string', 'max:60', 'regex:/^[a-z0-9][a-z0-9_-]*$/i'],
            'name' => ['required', 'string', 'max:120'],
            'description' => ['nullable', 'string', 'max:500'],
            'price' => ['required', 'numeric', 'min:0', 'max:1000000'],
            'currency' => ['required', 'string', 'in:USD,EUR,RUB,TRY'],
            'interval' => ['required', 'string', 'in:month,year'],
            'duration_days' => ['nullable', 'integer', 'min:1', 'max:3650'],
            'device_limit' => ['required', 'integer', 'min:1', 'max:100'],
            'traffic_limit_gb' => ['nullable', 'numeric', 'min:0.01', 'max:1048576'],
            'is_active' => ['nullable', 'boolean'],
            'is_public' => ['nullable', 'boolean'],
        ]);

        return [
            'code' => strtolower(trim($data['code'])),
            'name' => trim($data['name']),
            'description' => trim($data['description'] ?? ''),
            'price_minor' => (int) round(((float) $data['price']) * 100),
            'currency' => $data['currency'],
            'interval' => $data['interval'],
            'duration_days' => isset($data['duration_days']) ? (int) $data['duration_days'] : null,
            'device_limit' => (int) $data['device_limit'],
            'traffic_limit_bytes' => isset($data['traffic_limit_gb']) ? (int) round(((float) $data['traffic_limit_gb']) * ByteFormatter::GIB) : null,
            'is_active' => $request->boolean('is_active'),
            'is_public' => $request->boolean('is_public'),
            'sort_order' => 0,
        ];
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
            'code' => ['required', 'string', 'max:40'],
            'region' => ['required', 'string', 'max:20'],
        ]);

        return $this->coreAction($request, '/nodes', "Нода {$data['code']} зарегистрирована.", fn ($token) => $this->core->enrollNode($token, $data['code'], $data['region']));
    }

    public function logout(Request $request): RedirectResponse
    {
        $request->session()->forget('wavebreak_admin_tokens');

        return redirect('/');
    }

    // Every page-level mutation funnels through here: runs $action with the
    // current token and answers JSON (modal forms) or a redirect with a
    // flash. Core errors become readable Russian messages; an expired
    // session sends the admin back to sign in.
    private function coreAction(Request $request, string $redirectTo, string $successMessage, \Closure $action): RedirectResponse|JsonResponse
    {
        $token = $this->token($request);
        if ($token === null) {
            return $request->expectsJson()
                ? response()->json(['message' => 'Сессия истекла, войдите снова.'], 401)
                : redirect('/login');
        }
        try {
            $result = $action($token);

            if ($request->expectsJson()) {
                return response()->json(['message' => $successMessage, 'data' => $result]);
            }

            return redirect($redirectTo)->with('success', $successMessage);
        } catch (RequestException $e) {
            $error = CoreApiException::fromRequestException($e);
            if ($error->isUnauthenticated()) {
                $request->session()->forget('wavebreak_admin_tokens');

                return $request->expectsJson()
                    ? response()->json(['message' => 'Сессия истекла, войдите снова.'], 401)
                    : redirect('/login')->withErrors(['email' => 'Сессия истекла, войдите снова.']);
            }
            $message = $this->messages->for($error);

            if ($request->expectsJson()) {
                return response()->json(['message' => $message, 'code' => $error->errorCode], $error->status);
            }

            return redirect($redirectTo)->with('error', $message);
        }
    }

    private function token(Request $request): ?string
    {
        return $request->session()->get('wavebreak_admin_tokens.access_token');
    }
}
