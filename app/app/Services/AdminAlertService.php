<?php

namespace App\Services;

use App\Models\Admin;
use App\Models\CpOrder;
use App\Models\Notification;
use App\Models\Plan;
use App\Models\User;
use App\Notifications\WebPushNotification;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;

class AdminAlertService
{
    public function __construct(private readonly NodeMonitorService $monitor) {}

    public function sendPaymentEvent(string $title, string $body, string $type = 'info'): int
    {
        return $this->notifySubscribedAdmins($title, $body, $type);
    }

    public function sendOrderEvent(CpOrder $order): int
    {
        $title = match ($order->status) {
            'paid' => 'Заказ оплачен',
            'cancelled' => 'Заказ отменён',
            'failed' => 'Заказ не оплачен',
            'expired' => 'Заказ истёк',
            default => 'Новый заказ',
        };

        $type = match ($order->status) {
            'paid' => 'success',
            'cancelled', 'failed', 'expired' => 'warning',
            default => 'info',
        };

        $body = $this->orderBody($title, $order);

        Notification::query()->create([
            'title' => $title,
            'body' => $this->personalOrderBody($title, $order),
            'type' => $type,
            'is_global' => false,
            'user_id' => $order->user_id,
        ]);

        return $this->notifySubscribedAdmins($title, $body, $type);
    }

    public function sendSystemDigest(): int
    {
        $health = $this->monitor->health();
        $deadNodes = max(0, (int) $health['total_nodes'] - (int) $health['alive_nodes']);
        $ordersToday = DB::table('cp_orders')->whereDate('created_at', now()->toDateString())->count();
        $paidToday = DB::table('cp_orders')->where('status', 'paid')->whereDate('paid_at', now()->toDateString())->count();

        $type = $deadNodes > 0 ? 'warning' : 'success';
        $body = sprintf(
            'Ноды: %d/%d онлайн, средняя нагрузка %d%%. Заказы сегодня: %d, оплачено: %d. Пользователей: %d, тарифов: %d.',
            (int) $health['alive_nodes'],
            (int) $health['total_nodes'],
            (int) $health['avg_load_percent'],
            $ordersToday,
            $paidToday,
            User::query()->count(),
            Plan::query()->count(),
        );

        return $this->notifySubscribedAdmins('Состояние Auralith', $body, $type);
    }

    private function notifySubscribedAdmins(string $title, string $body, string $type): int
    {
        $sent = 0;

        Admin::query()
            ->whereHas('pushSubscriptions')
            ->each(function (Admin $admin) use ($title, $body, $type, &$sent): void {
                try {
                    $admin->notify(new WebPushNotification($title, $body, $type, route('admin.dashboard', absolute: false)));
                    $sent++;
                } catch (\Throwable $e) {
                    Log::warning('Admin WebPush: notification failed to queue', [
                        'admin_id' => $admin->id,
                        'error' => $e->getMessage(),
                    ]);
                }
            });

        return $sent;
    }

    private function orderBody(string $title, CpOrder $order): string
    {
        $user = $order->user()->first();
        $userLabel = $user?->username ?: ($user?->name ?: 'User #' . $order->user_id);

        return $title . '. Пользователь: ' . $userLabel . '. Сумма: ' . number_format((float) $order->amount, 0, '.', ' ') . ' ₽';
    }

    private function personalOrderBody(string $title, CpOrder $order): string
    {
        return $title . '. Сумма: ' . number_format((float) $order->amount, 0, '.', ' ') . ' ₽';
    }
}
