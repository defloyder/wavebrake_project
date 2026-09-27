<?php

namespace Tests\Feature;

use Illuminate\Http\Client\Request;
use Illuminate\Support\Facades\Http;
use Tests\TestCase;

/**
 * Users -> user modal. Core is faked at the HTTP level so the whole chain
 * (controller -> service -> CoreClient -> error normalization) is exercised.
 */
class UserDetailsModalTest extends TestCase
{
    private const USER_ID = '6f0b9a4e-1111-4222-8333-444455556666';

    private const GRANT_ID = '9c1d2e3f-aaaa-4bbb-8ccc-ddddeeeeffff';

    private function asAdmin(): self
    {
        return $this->withSession(['wavebreak_admin_tokens' => ['access_token' => 'access-token']]);
    }

    /** @return array<string, mixed> */
    private function detailsWithSubscription(): array
    {
        return [
            'user' => ['id' => self::USER_ID, 'email' => 'user@example.com', 'role' => 'user', 'status' => 'active', 'created_at' => '2026-09-01T10:00:00Z'],
            'subscription' => [
                'id' => 'sub-1', 'status' => 'active', 'source' => 'admin',
                'plan' => ['id' => 'plan-1', 'code' => 'starter-monthly', 'name' => 'Starter', 'price_minor' => 900, 'currency' => 'USD', 'interval' => 'month', 'duration_days' => 30, 'traffic_limit_bytes' => 107374182400, 'device_limit' => 5, 'is_active' => true],
                'started_at' => '2026-09-27T00:00:00Z', 'expires_at' => '2026-10-27T00:00:00Z',
                'traffic_limit_bytes' => 107374182400, 'device_limit' => 5,
            ],
            'access' => [
                'credential_id' => self::GRANT_ID,
                'subscription_url' => 'https://api.wavebreak.com.tr/v1/sub/'.self::GRANT_ID,
                'active_grants' => 1,
                'grants' => [['id' => self::GRANT_ID, 'node_id' => 'n1', 'node_code' => 'TR-PILOT-01', 'device_id' => null, 'protocol' => 'vless', 'status' => 'active', 'expires_at' => '2026-10-27T00:00:00Z', 'created_at' => '2026-09-27T00:00:00Z']],
            ],
            'traffic' => ['bytes_up' => 1073741824, 'bytes_down' => 9663676416, 'bytes_total' => 10737418240, 'limit_bytes' => 107374182400, 'remaining_bytes' => 96636764160, 'used_percent' => 10],
            'devices' => ['registered' => 2, 'limit' => 5, 'items' => [
                ['id' => 'd1', 'device_public_id' => 'd1', 'name' => 'iPhone 15 Pro', 'platform' => 'ios', 'status' => 'active', 'created_at' => '2026-09-27T00:00:00Z', 'last_seen_at' => '2026-09-27T01:00:00Z'],
                ['id' => 'd2', 'device_public_id' => 'd2', 'name' => 'Windows PC', 'platform' => 'windows', 'status' => 'active', 'created_at' => '2026-09-27T00:00:00Z', 'last_seen_at' => null],
            ]],
            'connections' => ['active' => null, 'source' => 'not_reported'],
        ];
    }

    /** @return array<string, mixed> */
    private function detailsWithoutSubscription(): array
    {
        return [
            'user' => ['id' => self::USER_ID, 'email' => 'user@example.com', 'role' => 'user', 'status' => 'active', 'created_at' => '2026-09-01T10:00:00Z'],
            'subscription' => null,
            'access' => ['active_grants' => 0, 'grants' => []],
            'traffic' => null,
            'devices' => ['registered' => 0, 'limit' => null, 'items' => []],
            'connections' => ['active' => null, 'source' => 'not_reported'],
        ];
    }

    /** @return list<array<string, mixed>> */
    private function plans(): array
    {
        return [
            ['id' => 'plan-1', 'code' => 'starter-monthly', 'name' => 'Starter', 'price_minor' => 900, 'currency' => 'USD', 'interval' => 'month', 'duration_days' => 30, 'traffic_limit_bytes' => 107374182400, 'device_limit' => 5, 'is_active' => true],
            ['id' => 'plan-2', 'code' => 'legacy', 'name' => 'Legacy', 'price_minor' => 500, 'currency' => 'USD', 'interval' => 'month', 'duration_days' => 30, 'traffic_limit_bytes' => null, 'device_limit' => 1, 'is_active' => false],
        ];
    }

    public function test_users_page_loads_with_open_buttons_and_modal(): void
    {
        Http::fake([
            '*/v1/me' => Http::response(['id' => 'admin-1', 'email' => 'admin@example.com', 'role' => 'admin']),
            '*/v1/admin/users' => Http::response(['users' => [
                ['id' => self::USER_ID, 'email' => 'user@example.com', 'role' => 'user', 'status' => 'active', 'created_at' => '2026-09-01T10:00:00Z'],
            ]]),
            '*' => Http::response([]),
        ]);

        $this->asAdmin()->get('/users')
            ->assertOk()
            ->assertSee('user@example.com')
            ->assertSee('data-open-user="'.self::USER_ID.'"', false)
            ->assertSee('id="adm-user-details-modal"', false);
    }

    public function test_user_with_subscription_renders_all_data(): void
    {
        Http::fake(['*/v1/admin/users/'.self::USER_ID => Http::response($this->detailsWithSubscription())]);

        $response = $this->asAdmin()->get('/users/'.self::USER_ID.'/details');

        $response->assertOk()
            ->assertSee(self::USER_ID)
            ->assertSee('user@example.com')
            ->assertSee('Starter')
            ->assertSee('data-subscription-status', false)
            ->assertSee('active')
            ->assertSee(self::GRANT_ID)
            ->assertSee('https://api.wavebreak.com.tr/v1/sub/9c1d••••ffff')
            ->assertSee('data-copy="https://api.wavebreak.com.tr/v1/sub/'.self::GRANT_ID.'"', false)
            ->assertSee('10 GB')
            ->assertSee('100 GB')
            ->assertSee('90 GB')
            ->assertSee('Devices: 2 / 5')
            ->assertSee('iPhone 15 Pro')
            ->assertSee('Windows PC')
            ->assertSee('Отправить ссылку для восстановления пароля')
            ->assertDontSee('Выдать подписку');
        Http::assertSent(fn (Request $r) => $r->hasHeader('Authorization', 'Bearer access-token'));
    }

    public function test_user_without_subscription_shows_issue_form_with_plans_from_core(): void
    {
        Http::fake([
            '*/v1/admin/users/'.self::USER_ID => Http::response($this->detailsWithoutSubscription()),
            '*/v1/admin/plans' => Http::response(['plans' => $this->plans()]),
        ]);

        $this->asAdmin()->get('/users/'.self::USER_ID.'/details')
            ->assertOk()
            ->assertSee('No active subscription')
            ->assertSee('Выдать подписку')
            ->assertSee('value="plan-1"', false)
            ->assertSee('Starter — 9.00 USD · 30 дн. · 100 GB · 5 устр.')
            ->assertSee('Legacy')
            ->assertSee('неактивен')
            ->assertSee('Devices: 0 / —');
    }

    public function test_issue_subscription_goes_through_core_and_returns_refreshed_modal(): void
    {
        Http::fake(['*/v1/admin/users/'.self::USER_ID.'/subscriptions' => Http::response($this->detailsWithSubscription(), 201)]);

        $this->asAdmin()->post('/users/'.self::USER_ID.'/subscription', ['plan_id' => 'plan-1'])
            ->assertOk()
            ->assertSee('Подписка выдана.')
            ->assertSee('Starter')
            ->assertSee(self::GRANT_ID)
            ->assertDontSee('Выдать подписку');
        Http::assertSent(fn (Request $r) => $r->method() === 'POST'
            && str_ends_with($r->url(), '/v1/admin/users/'.self::USER_ID.'/subscriptions')
            && $r['plan_id'] === 'plan-1');
    }

    public function test_issue_subscription_requires_a_plan(): void
    {
        Http::fake();
        $this->asAdmin()->postJson('/users/'.self::USER_ID.'/subscription', [])->assertStatus(422);
        Http::assertNothingSent();
    }

    public function test_core_domain_errors_are_shown_as_readable_messages(): void
    {
        Http::fake(['*/v1/admin/users/'.self::USER_ID.'/subscriptions' => Http::response(
            ['error' => ['code' => 'SUBSCRIPTION_ALREADY_ACTIVE', 'message' => 'User already has an active subscription.', 'request_id' => 'req-42']],
            409,
        )]);

        $this->asAdmin()->post('/users/'.self::USER_ID.'/subscription', ['plan_id' => 'plan-1'])
            ->assertStatus(409)
            ->assertJson(['code' => 'SUBSCRIPTION_ALREADY_ACTIVE', 'request_id' => 'req-42'])
            ->assertJsonFragment(['message' => 'У пользователя уже есть активная подписка. (request req-42)']);
    }

    public function test_password_reset_button_reports_created_link(): void
    {
        Http::fake(['*/v1/admin/users/'.self::USER_ID.'/password-reset' => Http::response(
            ['status' => 'reset_link_created', 'channel' => 'email', 'delivery' => 'not_configured', 'expires_at' => '2026-09-27T01:00:00Z'],
            202,
        )]);

        $this->asAdmin()->postJson('/users/'.self::USER_ID.'/password-reset')
            ->assertOk()
            ->assertJson(['status' => 'reset_link_created', 'delivery' => 'not_configured'])
            ->assertJsonFragment(['message' => 'Ссылка для восстановления пароля создана. Отправка почты в Core пока не настроена.']);
    }

    public function test_password_reset_without_email_shows_channel_error(): void
    {
        Http::fake(['*/v1/admin/users/'.self::USER_ID.'/password-reset' => Http::response(
            ['error' => ['code' => 'PASSWORD_RESET_CHANNEL_UNAVAILABLE', 'message' => 'no email', 'request_id' => 'r1']],
            422,
        )]);

        $this->asAdmin()->postJson('/users/'.self::USER_ID.'/password-reset')
            ->assertStatus(422)
            ->assertJson(['code' => 'PASSWORD_RESET_CHANNEL_UNAVAILABLE']);
    }

    public function test_expired_core_session_asks_to_sign_in_again(): void
    {
        Http::fake(['*/v1/admin/users/'.self::USER_ID => Http::response(['code' => 'invalid bearer token', 'error' => 'invalid bearer token'], 401)]);

        $this->asAdmin()->get('/users/'.self::USER_ID.'/details')
            ->assertStatus(401)
            ->assertJson(['message' => 'Сессия истекла, войдите снова.'])
            ->assertSessionMissing('wavebreak_admin_tokens');
    }

    public function test_modal_endpoints_require_an_admin_session(): void
    {
        Http::fake();
        $this->get('/users/'.self::USER_ID.'/details')->assertStatus(401);
        $this->post('/users/'.self::USER_ID.'/password-reset')->assertStatus(401);
        Http::assertNothingSent();
    }
}
