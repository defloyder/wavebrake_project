<?php

namespace App\Http\Controllers;

use App\Services\Core\CoreApiException;
use App\Services\UserAdministration\CoreErrorMessages;
use App\Services\UserAdministration\UserAdministrationService;
use App\Services\UserAdministration\UserDetails;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Response;

/**
 * The Users -> user modal. Returns a server-rendered partial so the modal
 * can be refreshed in place (after issuing a subscription) without a page
 * reload. All data and every action go through Core.
 */
final class UserDetailsController extends Controller
{
    public function __construct(
        private readonly UserAdministrationService $users,
        private readonly CoreErrorMessages $messages,
    ) {}

    public function show(Request $request, string $userId): Response|JsonResponse
    {
        return $this->withToken($request, function (string $token) use ($userId) {
            return $this->renderDetails($token, $this->users->details($token, $userId));
        });
    }

    public function issueSubscription(Request $request, string $userId): Response|JsonResponse
    {
        $data = $request->validate(['plan_id' => ['required', 'string', 'max:64']]);

        return $this->withToken($request, function (string $token) use ($userId, $data) {
            $details = $this->users->issueSubscription($token, $userId, $data['plan_id']);

            return $this->renderDetails($token, $details, 'Подписка выдана.');
        });
    }

    public function requestPasswordReset(Request $request, string $userId): Response|JsonResponse
    {
        return $this->withToken($request, function (string $token) use ($userId) {
            $result = $this->users->requestPasswordReset($token, $userId);
            $message = ($result['delivery'] ?? '') === 'sent'
                ? 'Ссылка для восстановления пароля отправлена.'
                : 'Ссылка для восстановления пароля создана. Отправка почты в Core пока не настроена.';

            return response()->json([
                'message' => $message,
                'status' => $result['status'] ?? null,
                'delivery' => $result['delivery'] ?? null,
                'expires_at' => $result['expires_at'] ?? null,
            ]);
        });
    }

    private function renderDetails(string $token, UserDetails $details, ?string $flash = null): Response
    {
        $plans = $details->hasSubscription() ? [] : $this->users->planOptions($token);

        return response()->view('users.details', [
            'details' => $details,
            'plans' => $plans,
            'flash' => $flash,
        ]);
    }

    /** @param \Closure(string): (Response|JsonResponse) $action */
    private function withToken(Request $request, \Closure $action): Response|JsonResponse
    {
        $token = $request->session()->get('wavebreak_admin_tokens.access_token');
        if (! is_string($token) || $token === '') {
            return response()->json(['message' => 'Сессия истекла, войдите снова.', 'code' => 'UNAUTHENTICATED'], 401);
        }

        try {
            return $action($token);
        } catch (CoreApiException $e) {
            if ($e->isUnauthenticated()) {
                $request->session()->forget('wavebreak_admin_tokens');
            }

            return response()->json([
                'message' => $this->messages->for($e),
                'code' => $e->errorCode,
                'request_id' => $e->requestId,
            ], $e->status >= 400 && $e->status < 600 ? $e->status : 502);
        }
    }
}
