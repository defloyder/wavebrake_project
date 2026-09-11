<?php

namespace Tests\Feature;

use App\Models\Admin;
use App\Models\AdminSystemDigestSchedule;
use App\Models\PushSubscription;
use App\Services\NodeMonitorService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Tests\TestCase;

class AdminSettingsTest extends TestCase
{
    use RefreshDatabase;

    public function test_admin_manifest_is_available(): void
    {
        $this->get(route('admin.manifest'))
            ->assertOk()
            ->assertJsonPath('name', 'Auralith Admin')
            ->assertJsonPath('display', 'standalone');
    }

    public function test_admin_can_open_settings_page(): void
    {
        $admin = $this->admin();
        $this->fakeNodeMonitor();

        $this->withSession(['admin_id' => $admin->id, 'admin_name' => $admin->name])
            ->get(route('admin.settings.index'))
            ->assertOk()
            ->assertSee('Настройки', false)
            ->assertSee('Уведомления администратора', false)
            ->assertSee('Расписание системных уведомлений', false)
            ->assertDontSee('Веб-приложение', false);
    }

    public function test_admin_push_subscription_is_saved_for_current_admin(): void
    {
        $admin = $this->admin();

        $this->withSession(['admin_id' => $admin->id, 'admin_name' => $admin->name])
            ->postJson(route('admin.settings.push.subscribe'), [
                'endpoint' => 'https://example.com/push/admin-device',
                'p256dh' => str_repeat('a', 88),
                'auth' => str_repeat('b', 24),
                'content_encoding' => 'aes128gcm',
            ])
            ->assertOk()
            ->assertJsonPath('ok', true);

        $this->assertDatabaseHas('push_subscriptions', [
            'subscribable_type' => Admin::class,
            'subscribable_id' => $admin->id,
            'endpoint' => 'https://example.com/push/admin-device',
            'user_id' => null,
        ]);
    }

    public function test_admin_push_subscription_can_be_removed(): void
    {
        $admin = $this->admin();

        PushSubscription::query()->create([
            'subscribable_type' => Admin::class,
            'subscribable_id' => $admin->id,
            'endpoint' => 'https://example.com/push/admin-device',
            'public_key' => str_repeat('a', 88),
            'auth_token' => str_repeat('b', 24),
            'content_encoding' => 'aes128gcm',
        ]);

        $this->withSession(['admin_id' => $admin->id, 'admin_name' => $admin->name])
            ->deleteJson(route('admin.settings.push.unsubscribe'), [
                'endpoint' => 'https://example.com/push/admin-device',
            ])
            ->assertOk()
            ->assertJsonPath('ok', true);

        $this->assertDatabaseMissing('push_subscriptions', [
            'subscribable_type' => Admin::class,
            'subscribable_id' => $admin->id,
            'endpoint' => 'https://example.com/push/admin-device',
        ]);
    }

    public function test_admin_can_update_digest_schedule(): void
    {
        $admin = $this->admin();

        $this->withSession(['admin_id' => $admin->id, 'admin_name' => $admin->name])
            ->put(route('admin.settings.digest-schedule.update'), [
                'times' => ['08:30', '13:00', '20:45', '', ''],
            ])
            ->assertRedirect(route('admin.settings.index'));

        $this->assertSame(
            ['08:30', '13:00', '20:45'],
            AdminSystemDigestSchedule::query()->orderBy('send_time')->pluck('send_time')->all(),
        );
    }

    private function admin(): Admin
    {
        return Admin::query()->create([
            'name' => 'Admin',
            'username' => 'admin',
            'password' => Hash::make('password'),
        ]);
    }

    private function fakeNodeMonitor(): void
    {
        $this->app->instance(NodeMonitorService::class, new class extends NodeMonitorService {
            public function health(): array
            {
                return [
                    'alive_nodes' => 0,
                    'total_nodes' => 0,
                    'avg_load_percent' => 0,
                    'nodes' => [],
                ];
            }
        });
    }
}
