<?php

namespace Tests\Feature;

use App\Models\Plan;
use App\Models\Subscription;
use App\Models\User;
use App\Services\CoreApiService;
use App\Services\NodeMonitorService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Http;
use Mockery;
use Tests\TestCase;

class AdminUsersTest extends TestCase
{
    use RefreshDatabase;

    public function test_users_index_shows_core_subscription_summary(): void
    {
        $this->fakeNodeMonitor();
        Cache::put('admin-core-refresh-throttle:users', true, 60);
        Cache::put('admin-core-refresh-last-success', now()->toIso8601String(), 60);
        config()->set('services.core.url', 'https://core.test');
        config()->set('services.core.admin_key', 'test-admin-key');
        Http::fake([
            'https://core.test/admin/users/622/overview' => Http::response([
                'user_id' => 622,
                'subscription' => [
                    'is_active' => true,
                    'status' => 'active',
                    'plan_name' => 'Core Access',
                    'expires_at' => now()->addMonth()->toIso8601String(),
                ],
            ]),
        ]);

        $user = User::factory()->create([
            'core_user_id' => 622,
            'name' => 'User662154082',
            'username' => 'User662154082',
            'telegram_id' => 662154082,
        ]);
        $plan = Plan::query()->create([
            'name' => 'Auralith Access',
            'duration_months' => 1,
            'price_rub' => 499,
            'headline' => 'Доступ на месяц',
            'features' => [],
            'is_highlighted' => false,
        ]);
        Subscription::query()->create([
            'user_id' => $user->id,
            'plan_id' => $plan->id,
            'status' => 'inactive',
            'starts_at' => now()->subDay(),
            'ends_at' => now()->subDay(),
            'last_sync_at' => now()->subHour(),
        ]);

        $this->withSession(['admin_id' => 1, 'admin_name' => 'Admin'])
            ->get(route('admin.resource.index', 'users'))
            ->assertOk()
            ->assertSee('Источник данных:', false)
            ->assertSee('Core Access', false)
            ->assertSee('Активна', false)
            ->assertSee('Проверено напрямую через Core API', false)
            ->assertSee('Карточка пользователя', false);

        Http::assertSent(fn ($request) => $request->url() === 'https://core.test/admin/users/622/overview');
    }

    public function test_core_owned_users_and_subscriptions_cannot_be_deleted_locally(): void
    {
        $this->fakeNodeMonitor();

        $user = User::factory()->create(['core_user_id' => 622]);
        $plan = Plan::query()->create([
            'name' => 'Auralith Access',
            'duration_months' => 1,
            'price_rub' => 499,
            'headline' => 'Доступ на месяц',
            'features' => [],
            'is_highlighted' => false,
        ]);
        $subscription = Subscription::query()->create([
            'user_id' => $user->id,
            'plan_id' => $plan->id,
            'status' => 'active',
            'ends_at' => now()->addMonth(),
            'last_sync_at' => now(),
        ]);

        $session = ['admin_id' => 1, 'admin_name' => 'Admin'];

        $this->withSession($session)
            ->delete(route('admin.resource.destroy', ['users', $user->id]))
            ->assertStatus(405);

        $this->withSession($session)
            ->delete(route('admin.resource.destroy', ['subscriptions', $subscription->id]))
            ->assertStatus(405);

        $this->withSession($session)
            ->put(route('admin.resource.update', ['subscriptions', $subscription->id]), [
                'status' => 'inactive',
            ])
            ->assertRedirect(route('admin.resource.index', 'subscriptions'))
            ->assertSessionHas('error');

        $this->assertDatabaseHas('users', ['id' => $user->id]);
        $this->assertDatabaseHas('subscriptions', [
            'id' => $subscription->id,
            'status' => 'active',
        ]);
    }

    public function test_subscriptions_index_uses_user_style_details_and_edit_modals(): void
    {
        $this->fakeNodeMonitor();
        Cache::put('admin-core-refresh-throttle:users', true, 60);

        $user = User::factory()->create([
            'core_user_id' => 622,
            'name' => 'Modal User',
            'username' => 'modal_user',
            'telegram_id' => 662154082,
        ]);
        $plan = Plan::query()->create([
            'name' => 'Advanced',
            'duration_months' => 3,
            'price_rub' => 999,
            'headline' => 'Расширенный доступ',
            'features' => [],
            'is_highlighted' => false,
        ]);
        $subscription = Subscription::query()->create([
            'user_id' => $user->id,
            'plan_id' => $plan->id,
            'status' => 'active',
            'starts_at' => now()->subDay(),
            'ends_at' => now()->addMonths(3),
            'last_sync_at' => now(),
        ]);

        $this->withSession(['admin_id' => 1, 'admin_name' => 'Admin'])
            ->get(route('admin.resource.index', 'subscriptions'))
            ->assertOk()
            ->assertSee('Modal User', false)
            ->assertSee('Карточка подписки', false)
            ->assertSee('Изменение подписки', false)
            ->assertSee('subscription-card-'.$subscription->id, false)
            ->assertSee('subscription-edit-'.$subscription->id, false)
            ->assertSee('Пользователь и диагностика', false);
    }

    public function test_subscriptions_index_prefers_live_core_overview_over_local_snapshot(): void
    {
        $this->fakeNodeMonitor();
        Cache::put('admin-core-refresh-throttle:users', true, 60);
        Cache::put('admin-core-refresh-last-success', now()->toIso8601String(), 60);
        config()->set('services.core.url', 'https://core.test');
        config()->set('services.core.admin_key', 'test-admin-key');
        Http::fake([
            'https://core.test/admin/users/622/overview' => Http::response([
                'user_id' => 622,
                'subscription' => [
                    'is_active' => true,
                    'status' => 'active',
                    'plan_name' => 'Core Standard',
                    'starts_at' => now()->subDay()->toIso8601String(),
                    'expires_at' => now()->addMonth()->toIso8601String(),
                ],
            ]),
        ]);

        $user = User::factory()->create([
            'core_user_id' => 622,
            'name' => 'Snapshot User',
            'username' => 'snapshot_user',
        ]);
        $plan = Plan::query()->create([
            'name' => 'Local Stale Plan',
            'duration_months' => 12,
            'price_rub' => 1490,
            'headline' => 'Old local data',
            'features' => [],
            'is_highlighted' => false,
        ]);
        Subscription::query()->create([
            'user_id' => $user->id,
            'plan_id' => $plan->id,
            'status' => 'inactive',
            'starts_at' => now()->subMonths(3),
            'ends_at' => now()->subMonth(),
            'last_sync_at' => now()->subMonths(2),
        ]);

        $this->withSession(['admin_id' => 1, 'admin_name' => 'Admin'])
            ->get(route('admin.resource.index', 'subscriptions'))
            ->assertOk()
            ->assertSee('Core Standard', false)
            ->assertSee('Core overview', false);

        Http::assertSent(fn ($request) => $request->url() === 'https://core.test/admin/users/622/overview');
    }

    public function test_core_sync_does_not_mark_expired_subscription_active_from_stale_core_flags(): void
    {
        $plan = Plan::query()->create([
            'name' => 'Basic',
            'duration_months' => 1,
            'price_rub' => 169,
            'headline' => 'Basic',
            'features' => [],
            'is_highlighted' => false,
        ]);

        $core = Mockery::mock(CoreApiService::class);
        $core->shouldReceive('adminUsers')->once()->andReturn([
            'users' => [[
                'id' => 904,
                'username' => 'expired_core_user',
                'trial_used' => false,
                'subscription' => [
                    'is_active' => true,
                    'plan_name' => 'Basic',
                    'expires_at' => now()->subDay()->toIso8601String(),
                ],
            ]],
        ]);
        $this->app->instance(CoreApiService::class, $core);

        $this->artisan('core:sync')->assertSuccessful();

        $user = User::query()->where('core_user_id', 904)->firstOrFail();
        $this->assertDatabaseHas('subscriptions', [
            'user_id' => $user->id,
            'plan_id' => $plan->id,
            'status' => 'expired',
        ]);
    }

    public function test_core_sync_imports_user_without_telegram_or_subscription_token(): void
    {
        $core = Mockery::mock(CoreApiService::class);
        $core->shouldReceive('adminUsers')->once()->andReturn([
            'users' => [[
                'id' => 904,
                'username' => 'core_only_user',
                'trial_used' => false,
            ]],
        ]);
        $this->app->instance(CoreApiService::class, $core);

        $this->artisan('core:sync')->assertSuccessful();

        $this->assertDatabaseHas('users', [
            'core_user_id' => 904,
            'username' => 'core_only_user',
            'telegram_id' => null,
            'token' => null,
        ]);
    }

    public function test_plans_index_shows_readable_features_and_modal_actions(): void
    {
        $this->fakeNodeMonitor();

        $plan = Plan::query()->create([
            'name' => 'Standard',
            'duration_months' => 3,
            'price_rub' => 449,
            'headline' => 'Выгодно',
            'features' => [
                'Управление устройствами',
                'Поддержка в рабочее время',
            ],
            'is_highlighted' => true,
        ]);

        $response = $this->withSession(['admin_id' => 1, 'admin_name' => 'Admin'])
            ->get(route('admin.resource.index', 'plans'));

        $response
            ->assertOk()
            ->assertSee('Преимущества', false)
            ->assertSee('Управление устройствами', false)
            ->assertSee('Преимущества тарифа', false)
            ->assertSee('Карточка тарифа', false)
            ->assertSee('Изменение тарифа', false)
            ->assertSee('plan-card-'.$plan->id, false)
            ->assertSee('plan-edit-'.$plan->id, false)
            ->assertDontSee('\\u0423', false);
    }

    public function test_plan_feature_list_reads_legacy_nested_json(): void
    {
        $plan = new Plan();
        $plan->setRawAttributes([
            'features' => json_encode(json_encode([
                'Личный кабинет',
                'Управление устройствами',
            ], JSON_UNESCAPED_UNICODE), JSON_UNESCAPED_UNICODE),
        ]);

        $this->assertSame([
            'Личный кабинет',
            'Управление устройствами',
        ], $plan->featureList());
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
