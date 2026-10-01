<?php

namespace App\Http\Controllers;

use App\Services\Core\CoreApiException;
use App\Services\UserAdministration\CoreErrorMessages;
use App\Services\UserAdministration\UserAdministrationService;
use App\Services\UserAdministration\UserDetails;
use App\View\Admin\StatusBadge;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Response;
use Illuminate\Validation\Rule;

/**
 * The user card: opened by clicking a user anywhere in the admin, and the
 * one place every per-user action lives. Each action returns the card
 * re-rendered from Core, so the modal refreshes in place without a page
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
        return $this->card($request, fn (string $token) => $this->users->details($token, $userId));
    }

    public function issueSubscription(Request $request, string $userId): Response|JsonResponse
    {
        $data = $request->validate(['plan_id' => ['required', 'string', 'max:64']]);

        return $this->card($request, fn (string $token) => $this->users->issueSubscription($token, $userId, $data['plan_id']), 'Подписка выдана.', true);
    }

    public function issueAccess(Request $request, string $userId): Response|JsonResponse
    {
        return $this->card($request, fn (string $token) => $this->users->issueAccess($token, $userId), 'Доступ выдан — ссылка подписки готова.', true);
    }

    public function updateProfile(Request $request, string $userId): Response|JsonResponse
    {
        $data = $request->validate([
            'email' => ['required', 'email:rfc', 'max:254'],
            'username' => ['nullable', 'string', 'max:80'],
            'password' => ['nullable', 'string', 'min:10', 'max:200'],
            'role' => ['required', 'string', Rule::in(StatusBadge::ROLES)],
            'status' => ['required', 'string', 'in:active,disabled'],
        ]);
        $profile = [
            'email' => mb_strtolower(trim($data['email'])),
            'username' => trim($data['username'] ?? ''),
            'password' => $data['password'] ?? '',
            'role' => $data['role'],
            'status' => $data['status'],
        ];

        return $this->card($request, fn (string $token) => $this->users->updateProfile($token, $userId, $profile), 'Данные пользователя сохранены.');
    }

    public function block(Request $request, string $userId): Response|JsonResponse
    {
        return $this->withToken($request, function (string $token) use ($userId) {
            $viewer = $this->users->viewer($token);
            if (($viewer['id'] ?? '') === $userId) {
                return response()->json(['message' => 'Нельзя заблокировать собственную учётную запись.'], 422);
            }

            return response()->view('users.details', [
                'details' => $this->users->setBlocked($token, $userId, true),
                'viewer' => $viewer,
                'plans' => $this->users->planOptions($token),
                'flash' => 'Пользователь заблокирован.',
            ]);
        });
    }

    public function unblock(Request $request, string $userId): Response|JsonResponse
    {
        return $this->card($request, fn (string $token) => $this->users->setBlocked($token, $userId, false), 'Пользователь разблокирован.');
    }

    public function destroy(Request $request, string $userId): JsonResponse
    {
        return $this->withToken($request, function (string $token) use ($userId) {
            $viewer = $this->users->viewer($token);
            if (($viewer['role'] ?? '') !== 'superadmin') {
                return response()->json(['message' => 'Удаление пользователей доступно только суперадмину.'], 403);
            }
            if (($viewer['id'] ?? '') === $userId) {
                return response()->json(['message' => 'Нельзя удалить собственную учётную запись.'], 422);
            }
            $this->users->delete($token, $userId);

            return response()->json(['message' => 'Пользователь и связанные данные удалены.', 'removed' => true]);
        });
    }

    public function editSubscription(Request $request, string $userId, string $subscriptionId): Response|JsonResponse
    {
        $data = $request->validate([
            'plan_id' => ['nullable', 'uuid'],
            'status' => ['nullable', 'string', Rule::in(StatusBadge::SUBSCRIPTION_STATUSES)],
            'expires_on' => ['nullable', 'date_format:Y-m-d'],
            'traffic_limit_gb' => ['nullable', 'numeric', 'min:0.01', 'max:1048576'],
            'traffic_reset_to_plan' => ['nullable', 'boolean'],
            'device_limit' => ['nullable', 'integer', 'min:1', 'max:100'],
        ]);
        $resetToPlan = $request->boolean('traffic_reset_to_plan');
        $changes = [
            'plan_id' => $data['plan_id'] ?? null,
            'status' => $data['status'] ?? null,
            'expires_on' => $data['expires_on'] ?? null,
            'traffic_unlimited' => $resetToPlan,
            'traffic_limit_gb' => $resetToPlan || ! isset($data['traffic_limit_gb']) ? null : (float) $data['traffic_limit_gb'],
            'device_limit' => isset($data['device_limit']) ? (int) $data['device_limit'] : null,
        ];

        return $this->card($request, fn (string $token) => $this->users->editSubscription($token, $userId, $subscriptionId, $changes), 'Подписка обновлена.', true);
    }

    public function resetTraffic(Request $request, string $userId, string $subscriptionId): Response|JsonResponse
    {
        return $this->card($request, fn (string $token) => $this->users->resetTraffic($token, $userId, $subscriptionId), 'Счётчик трафика сброшен.', true);
    }

    public function reissueAccess(Request $request, string $userId, string $subscriptionId): Response|JsonResponse
    {
        return $this->card($request, fn (string $token) => $this->users->reissueAccess($token, $userId, $subscriptionId), 'Ссылка перевыпущена. Старая ссылка больше не работает.', true);
    }

    public function cancelSubscription(Request $request, string $userId, string $subscriptionId): Response|JsonResponse
    {
        return $this->card($request, fn (string $token) => $this->users->cancelSubscription($token, $userId, $subscriptionId), 'Подписка отменена, доступ отозван.', true);
    }

    public function revokeDevice(Request $request, string $userId, string $deviceId): Response|JsonResponse
    {
        return $this->card($request, fn (string $token) => $this->users->revokeDevice($token, $userId, $deviceId), 'Устройство отозвано.', true);
    }

    public function revokeGrant(Request $request, string $userId, string $grantId): Response|JsonResponse
    {
        return $this->card($request, fn (string $token) => $this->users->revokeGrant($token, $userId, $grantId), 'Ключ доступа отозван.', true);
    }

    public function requestPasswordReset(Request $request, string $userId): JsonResponse
    {
        return $this->withToken($request, function (string $token) use ($userId) {
            $viewer = $this->users->viewer($token);
            if (! in_array($viewer['role'] ?? 'user', ['admin', 'superadmin'], true)) {
                return response()->json(['message' => 'Недостаточно прав для этого действия.'], 403);
            }

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

    /** @param \Closure(string): UserDetails $action */
    private function card(Request $request, \Closure $action, ?string $flash = null, bool $requireAdmin = false): Response|JsonResponse
    {
        return $this->withToken($request, function (string $token) use ($action, $flash, $requireAdmin) {
            $viewer = null;
            if ($requireAdmin) {
                $viewer = $this->users->viewer($token);
                if (! in_array($viewer['role'] ?? 'user', ['admin', 'superadmin'], true)) {
                    return response()->json(['message' => 'Недостаточно прав для этого действия.'], 403);
                }
            }

            $details = $action($token);

            return response()->view('users.details', [
                'details' => $details,
                'viewer' => $viewer ?? $this->users->viewer($token),
                'plans' => $this->users->planOptions($token),
                'flash' => $flash,
            ]);
        });
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
