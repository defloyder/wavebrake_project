<?php

namespace App\Http\Controllers;

use App\Models\Admin;
use App\Models\AdminSystemDigestSchedule;
use App\Models\AdminWebAuthnCredential;
use App\Notifications\WebPushNotification;
use App\Services\AdminAlertService;
use App\Services\NodeMonitorService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Illuminate\View\View;

class AdminSettingsController extends Controller
{
    public function __construct(private readonly NodeMonitorService $monitor) {}

    public function index(Request $request): View
    {
        $admin = $this->currentAdmin($request);

        return view('admin.settings', [
            'resources' => AdminPanelController::resources(),
            'serverHealth' => $this->monitor->health(),
            'admin' => $admin,
            'pushSubscribed' => $admin->pushSubscriptions()->exists(),
            'vapidPublicKey' => config('webpush.vapid.public_key', ''),
            'adminStartUrl' => route('admin.dashboard', absolute: false),
            'digestSchedules' => AdminSystemDigestSchedule::query()->orderBy('send_time')->get(),
            'webauthnCredential' => AdminWebAuthnCredential::query()
                ->where('admin_id', $admin->id)
                ->latest()
                ->first(),
        ]);
    }

    public function pushStatus(Request $request): JsonResponse
    {
        return response()->json([
            'subscribed' => $this->currentAdmin($request)->pushSubscriptions()->exists(),
        ]);
    }

    public function subscribe(Request $request): JsonResponse
    {
        $data = $request->validate([
            'endpoint' => ['required', 'string', 'url', 'max:500'],
            'p256dh' => ['required', 'string', 'max:512'],
            'auth' => ['required', 'string', 'max:256'],
            'content_encoding' => ['nullable', 'string', 'max:50'],
        ]);

        $this->currentAdmin($request)->updatePushSubscription(
            $data['endpoint'],
            $data['p256dh'],
            $data['auth'],
            $data['content_encoding'] ?? 'aes128gcm',
        );

        return response()->json(['ok' => true]);
    }

    public function unsubscribe(Request $request): JsonResponse
    {
        $data = $request->validate([
            'endpoint' => ['required', 'string', 'max:500'],
        ]);

        $this->currentAdmin($request)->deletePushSubscription($data['endpoint']);

        return response()->json(['ok' => true]);
    }

    public function sendTestNotification(Request $request): JsonResponse
    {
        $admin = $this->currentAdmin($request);

        if (! $admin->pushSubscriptions()->exists()) {
            return response()->json([
                'ok' => false,
                'message' => 'Сначала включите уведомления на этом устройстве.',
            ], 422);
        }

        $admin->notify(new WebPushNotification(
            'Auralith Admin',
            'Тестовое уведомление доставлено в подписку админки.',
            'success',
            route('admin.settings.index', absolute: false),
        ));

        return response()->json([
            'ok' => true,
            'message' => 'Тестовое уведомление отправлено.',
        ]);
    }

    public function sendSystemDigestNow(Request $request, AdminAlertService $alerts): JsonResponse
    {
        $sent = $alerts->sendSystemDigest();

        return response()->json([
            'ok' => $sent > 0,
            'sent' => $sent,
            'message' => $sent > 0
                ? "Системное уведомление отправлено администраторам: {$sent}."
                : 'Не найдено ни одной активной push-подписки администратора.',
        ], $sent > 0 ? 200 : 422);
    }

    public function updateDigestSchedule(Request $request): RedirectResponse
    {
        $data = $request->validate([
            'times' => ['nullable', 'array', 'max:5'],
            'times.*' => ['nullable', 'date_format:H:i', 'distinct'],
        ]);

        $times = collect($data['times'] ?? [])
            ->filter()
            ->unique()
            ->sort()
            ->values();

        AdminSystemDigestSchedule::query()->delete();

        foreach ($times as $time) {
            AdminSystemDigestSchedule::query()->create([
                'send_time' => $time,
                'is_enabled' => true,
            ]);
        }

        return redirect()
            ->route('admin.settings.index')
            ->with('success', 'Расписание системных уведомлений обновлено.');
    }

    private function currentAdmin(Request $request): Admin
    {
        return Admin::query()->findOrFail((int) $request->session()->get('admin_id'));
    }
}
