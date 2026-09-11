<?php

namespace Tests\Feature;

use App\Models\Admin;
use App\Models\CpOrder;
use App\Models\Plan;
use App\Models\PushSubscription;
use App\Models\User;
use App\Notifications\WebPushNotification;
use App\Services\AdminAlertService;
use App\Services\NodeMonitorService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Notification;
use Tests\TestCase;

class AdminAlertsTest extends TestCase
{
    use RefreshDatabase;

    public function test_payment_alert_is_sent_to_subscribed_admins_only(): void
    {
        Notification::fake();
        $subscribed = $this->admin('subscribed');
        $plain = $this->admin('plain');

        PushSubscription::query()->create([
            'subscribable_type' => Admin::class,
            'subscribable_id' => $subscribed->id,
            'endpoint' => 'https://example.com/push/admin-device',
            'public_key' => str_repeat('a', 88),
            'auth_token' => str_repeat('b', 24),
            'content_encoding' => 'aes128gcm',
        ]);

        app(AdminAlertService::class)->sendPaymentEvent('Заказ оплачен', 'Проверка', 'success');

        Notification::assertSentTo($subscribed, WebPushNotification::class);
        Notification::assertNotSentTo($plain, WebPushNotification::class);
    }

    public function test_order_event_creates_personal_profile_notification(): void
    {
        Notification::fake();
        $user = User::factory()->create();
        $plan = Plan::query()->create([
            'name' => 'Basic',
            'duration_months' => 1,
            'price_rub' => 169,
            'headline' => 'Basic access',
            'features' => [],
        ]);
        $order = CpOrder::query()->create([
            'invoice_id' => 'test-order-1',
            'user_id' => $user->id,
            'plan_id' => $plan->id,
            'amount' => 169,
            'currency' => 'RUB',
            'status' => 'paid',
        ]);

        app(AdminAlertService::class)->sendOrderEvent($order);

        $this->assertDatabaseHas('notifications', [
            'user_id' => $user->id,
            'is_global' => false,
            'type' => 'success',
        ]);
    }

    public function test_system_digest_command_sends_alert(): void
    {
        Notification::fake();
        $admin = $this->admin('digest');
        $this->fakeNodeMonitor();

        PushSubscription::query()->create([
            'subscribable_type' => Admin::class,
            'subscribable_id' => $admin->id,
            'endpoint' => 'https://example.com/push/admin-digest',
            'public_key' => str_repeat('a', 88),
            'auth_token' => str_repeat('b', 24),
            'content_encoding' => 'aes128gcm',
        ]);

        $this->artisan('admin:system-digest --force')->assertSuccessful();

        Notification::assertSentTo($admin, WebPushNotification::class);
    }

    private function admin(string $username): Admin
    {
        return Admin::query()->create([
            'name' => ucfirst($username),
            'username' => $username,
            'password' => Hash::make('password'),
        ]);
    }

    private function fakeNodeMonitor(): void
    {
        $this->app->instance(NodeMonitorService::class, new class extends NodeMonitorService {
            public function health(): array
            {
                return [
                    'alive_nodes' => 2,
                    'total_nodes' => 2,
                    'avg_load_percent' => 10,
                    'nodes' => [],
                ];
            }
        });
    }
}
