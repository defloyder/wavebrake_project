<?php

namespace Tests\Feature;

use Illuminate\Http\Client\Request;
use Illuminate\Support\Facades\Http;
use Tests\TestCase;

/**
 * The user card. Core is faked at the HTTP level so the whole chain
 * (controller -> service -> CoreClient -> error normalization -> view)
 * is exercised.
 */
class UserDetailsModalTest extends TestCase
{
    private const USER_ID = '6f0b9a4e-1111-4222-8333-444455556666';

    private const SUB_ID = '7a0b9a4e-1111-4222-8333-444455556666';

    private const GRANT_ID = '9c1d2e3f-aaaa-4bbb-8ccc-ddddeeeeffff';

    private const ADMIN = ['id' => 'admin-1', 'email' => 'admin@example.com', 'role' => 'admin'];

    private const SUPERADMIN = ['id' => 'root-1', 'email' => 'root@example.com', 'role' => 'superadmin'];

    private function asAdmin(): self
    {
        return $this->withSession(['wavebreak_admin_tokens' => ['access_token' => 'access-token']]);
    }

    /** @return array<string, mixed> */
    private function detailsWithSubscription(bool $withAccess = true): array
    {
        return [
            'user' => ['id' => self::USER_ID, 'email' => 'user@example.com', 'role' => 'user', 'status' => 'active', 'created_at' => '2026-09-01T10:00:00Z'],
            'subscription' => [
                'id' => self::SUB_ID, 'status' => 'active', 'source' => 'admin',
                'plan' => ['id' => 'plan-1', 'code' => 'starter-monthly', 'name' => 'Starter', 'price_minor' => 900, 'currency' => 'USD', 'interval' => 'month', 'duration_days' => 30, 'traffic_limit_bytes' => 107374182400, 'device_limit' => 5, 'is_active' => true],
                'started_at' => '2026-09-27T00:00:00Z', 'expires_at' => '2099-10-27T00:00:00Z',
                'traffic_limit_bytes' => 107374182400, 'device_limit' => 5,
            ],
            'access' => $withAccess ? [
                'credential_id' => self::GRANT_ID,
                'subscription_url' => 'https://api.wavebreak.com.tr/v1/sub/'.self::GRANT_ID,
                'active_grants' => 1,
                'grants' => [['id' => self::GRANT_ID, 'node_id' => 'n1', 'node_code' => 'TR-PILOT-01', 'device_id' => null, 'protocol' => 'vless', 'status' => 'active', 'expires_at' => '2099-10-27T00:00:00Z', 'created_at' => '2026-09-27T00:00:00Z']],
            ] : ['active_grants' => 0, 'grants' => []],
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

    /** Fakes Core for a card render: details + viewer + plans. */
    private function fakeCard(array $details, array $viewer = self::ADMIN, array $extra = []): void
    {
        Http::fake($extra + [
            '*/v1/admin/users/'.self::USER_ID => Http::response($details),
            '*/v1/me' => Http::response($viewer),
            '*/v1/admin/plans' => Http::response(['plans' => $this->plans()]),
            '*' => Http::response([], 404),
        ]);
    }

    public function test_user_card_renders_everything_in_operator_language(): void
    {
        $this->fakeCard($this->detailsWithSubscription());

        $this->asAdmin()->get('/users/'.self::USER_ID.'/details')
            ->assertOk()
            ->assertSee('user@example.com')
            ->assertSee('Пользователь')
            ->assertSee('Активен')
            ->assertSee('Starter')
            ->assertSee('data-subscription-status', false)
            ->assertSee('Активна')
            ->assertSee('27.09.2026')
            ->assertSee('https://api.wavebreak.com.tr/v1/sub/9c1d••••ffff')
            ->assertSee('data-copy="https://api.wavebreak.com.tr/v1/sub/'.self::GRANT_ID.'"', false)
            ->assertSee(self::GRANT_ID)
            ->assertSee('10 ГБ')
            ->assertSee('100 ГБ')
            ->assertSee('90 ГБ')
            ->assertSee('2 из 5')
            ->assertSee('iPhone 15 Pro')
            ->assertSee('iOS')
            ->assertSee('Windows PC')
            ->assertSee('WVB-9C1D2E3F')
            ->assertSee('TR-PILOT-01')
            // Every action lives in the card.
            ->assertSee('Редактировать')
            ->assertSee('Сбросить пароль')
            ->assertSee('Заблокировать')
            ->assertSee('/users/'.self::USER_ID.'/subscriptions/'.self::SUB_ID.'/reset-traffic', false)
            ->assertSee('/users/'.self::USER_ID.'/subscriptions/'.self::SUB_ID.'/reissue', false)
            ->assertSee('/users/'.self::USER_ID.'/subscriptions/'.self::SUB_ID.'/cancel', false)
            ->assertSee('/users/'.self::USER_ID.'/devices/d1/revoke', false)
            ->assertSee('/users/'.self::USER_ID.'/grants/'.self::GRANT_ID.'/revoke', false)
            ->assertDontSee('Выдать доступ')
            ->assertDontSee('Выдать подписку')
            // Only a superadmin may delete.
            ->assertDontSee('/users/'.self::USER_ID.'/remove', false);
        Http::assertSent(fn (Request $r) => $r->hasHeader('Authorization', 'Bearer access-token'));
    }

    public function test_superadmin_sees_delete(): void
    {
        $this->fakeCard($this->detailsWithSubscription(), self::SUPERADMIN);
        $this->asAdmin()->get('/users/'.self::USER_ID.'/details')
            ->assertOk()
            ->assertSee('/users/'.self::USER_ID.'/remove', false);
    }

    public function test_admin_cannot_delete_or_block_themselves(): void
    {
        $this->fakeCard($this->detailsWithSubscription(), ['id' => self::USER_ID, 'role' => 'superadmin']);
        $this->asAdmin()->get('/users/'.self::USER_ID.'/details')
            ->assertOk()
            ->assertDontSee('/users/'.self::USER_ID.'/remove', false)
            ->assertDontSee('/users/'.self::USER_ID.'/block', false);
    }

    public function test_subscription_without_key_offers_issue_access(): void
    {
        $this->fakeCard($this->detailsWithSubscription(withAccess: false));

        $this->asAdmin()->get('/users/'.self::USER_ID.'/details')
            ->assertOk()
            ->assertSee('Ключ доступа не выдан')
            ->assertSee('data-action="/users/'.self::USER_ID.'/access"', false)
            ->assertSee('Выдать доступ')
            ->assertDontSee('Перевыпустить ссылку');
    }

    public function test_issue_access_goes_through_core_and_returns_refreshed_card(): void
    {
        $this->fakeCard($this->detailsWithSubscription(), self::ADMIN, [
            '*/v1/admin/users/'.self::USER_ID.'/access' => Http::response($this->detailsWithSubscription()),
        ]);

        $this->asAdmin()->post('/users/'.self::USER_ID.'/access')
            ->assertOk()
            ->assertSee('Доступ выдан')
            ->assertSee(self::GRANT_ID);
        Http::assertSent(fn (Request $r) => $r->method() === 'POST' && str_ends_with($r->url(), '/v1/admin/users/'.self::USER_ID.'/access'));
    }

    public function test_user_without_subscription_shows_issue_form_with_plans_from_core(): void
    {
        $this->fakeCard($this->detailsWithoutSubscription());

        $this->asAdmin()->get('/users/'.self::USER_ID.'/details')
            ->assertOk()
            ->assertSee('Нет активной подписки')
            ->assertSee('Выдать подписку')
            ->assertSee('value="plan-1"', false)
            ->assertSee('Starter — 9,00 USD · 30 дн. · 100 ГБ · 5 устр.')
            ->assertSee('Legacy')
            ->assertSee('неактивен')
            ->assertSee('0 из —');
    }

    public function test_issue_subscription_goes_through_core_and_returns_refreshed_card(): void
    {
        $this->fakeCard($this->detailsWithSubscription(), self::ADMIN, [
            '*/v1/admin/users/'.self::USER_ID.'/subscriptions' => Http::response($this->detailsWithSubscription(), 201),
        ]);

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

    public function test_block_and_unblock_call_core_and_refresh_the_card(): void
    {
        $this->fakeCard($this->detailsWithSubscription(), self::ADMIN, [
            '*/v1/admin/users/'.self::USER_ID.'/disable' => Http::response(['ok' => true]),
            '*/v1/admin/users/'.self::USER_ID.'/enable' => Http::response(['ok' => true]),
        ]);

        $this->asAdmin()->post('/users/'.self::USER_ID.'/block')->assertOk()->assertSee('Пользователь заблокирован.');
        $this->asAdmin()->post('/users/'.self::USER_ID.'/unblock')->assertOk()->assertSee('Пользователь разблокирован.');
        Http::assertSent(fn (Request $r) => str_ends_with($r->url(), '/disable'));
        Http::assertSent(fn (Request $r) => str_ends_with($r->url(), '/enable'));
    }

    public function test_profile_update_normalizes_and_patches_core(): void
    {
        $this->fakeCard($this->detailsWithSubscription(), self::ADMIN, [
            '*/v1/admin/users/'.self::USER_ID => Http::sequence()
                ->push(['id' => self::USER_ID])
                ->push($this->detailsWithSubscription()),
        ]);

        $this->asAdmin()->post('/users/'.self::USER_ID.'/profile', [
            'email' => '  New@Example.COM ', 'username' => 'neo', 'role' => 'support', 'status' => 'active', 'password' => '',
        ])->assertOk()->assertSee('Данные пользователя сохранены.');

        Http::assertSent(fn (Request $r) => $r->method() === 'PATCH'
            && $r['email'] === 'new@example.com' && $r['role'] === 'support' && $r['password'] === '');
    }

    public function test_subscription_edit_sends_only_changed_fields_with_end_of_day_expiry(): void
    {
        $this->fakeCard($this->detailsWithSubscription(), self::ADMIN, [
            '*/v1/admin/subscriptions/'.self::SUB_ID => Http::response(['id' => self::SUB_ID]),
        ]);

        $this->asAdmin()->post('/users/'.self::USER_ID.'/subscriptions/'.self::SUB_ID.'/edit', [
            'expires_on' => '2026-12-31', 'traffic_limit_gb' => '250', 'plan_id' => '', 'status' => '', 'device_limit' => '',
        ])->assertOk()->assertSee('Подписка обновлена.');

        Http::assertSent(fn (Request $r) => $r->method() === 'PATCH'
            && str_ends_with($r->url(), '/v1/admin/subscriptions/'.self::SUB_ID)
            && $r['expires_at'] === '2026-12-31T20:59:59+00:00' // 23:59:59 Europe/Istanbul
            && $r['traffic_limit_gb'] == 250.0
            && $r['traffic_unlimited'] === false
            && $r['plan_id'] === null && $r['status'] === null && $r['device_limit'] === null);
    }

    public function test_subscription_edit_rejects_statuses_core_does_not_accept(): void
    {
        Http::fake();
        $this->asAdmin()->postJson('/users/'.self::USER_ID.'/subscriptions/'.self::SUB_ID.'/edit', ['status' => 'past_due'])->assertStatus(422);
        Http::assertNothingSent();
    }

    public function test_subscription_and_access_actions_hit_the_right_core_endpoints(): void
    {
        $this->fakeCard($this->detailsWithSubscription(), self::ADMIN, [
            '*/v1/admin/subscriptions/'.self::SUB_ID.'/*' => Http::response(['ok' => true]),
            '*/v1/admin/devices/d1/revoke' => Http::response(['ok' => true]),
            '*/v1/admin/access/grants/'.self::GRANT_ID.'/revoke' => Http::response(['ok' => true]),
        ]);
        $base = '/users/'.self::USER_ID;

        $this->asAdmin()->post($base.'/subscriptions/'.self::SUB_ID.'/reset-traffic')->assertOk()->assertSee('Счётчик трафика сброшен.');
        $this->asAdmin()->post($base.'/subscriptions/'.self::SUB_ID.'/reissue')->assertOk()->assertSee('Ссылка перевыпущена.');
        $this->asAdmin()->post($base.'/subscriptions/'.self::SUB_ID.'/cancel')->assertOk()->assertSee('Подписка отменена');
        $this->asAdmin()->post($base.'/devices/d1/revoke')->assertOk()->assertSee('Устройство отозвано.');
        $this->asAdmin()->post($base.'/grants/'.self::GRANT_ID.'/revoke')->assertOk()->assertSee('Ключ доступа отозван.');

        Http::assertSent(fn (Request $r) => str_ends_with($r->url(), '/subscriptions/'.self::SUB_ID.'/reset-usage'));
        Http::assertSent(fn (Request $r) => str_ends_with($r->url(), '/subscriptions/'.self::SUB_ID.'/reissue'));
        Http::assertSent(fn (Request $r) => str_ends_with($r->url(), '/subscriptions/'.self::SUB_ID.'/delete') && $r['confirm'] === true);
        Http::assertSent(fn (Request $r) => str_ends_with($r->url(), '/devices/d1/revoke'));
        Http::assertSent(fn (Request $r) => str_ends_with($r->url(), '/grants/'.self::GRANT_ID.'/revoke'));
    }

    public function test_delete_is_superadmin_only(): void
    {
        Http::fake(['*/v1/me' => Http::response(self::ADMIN), '*' => Http::response([], 404)]);
        $this->asAdmin()->postJson('/users/'.self::USER_ID.'/remove')->assertForbidden();
        Http::assertNotSent(fn (Request $r) => $r->method() === 'DELETE');
    }

    public function test_superadmin_deletes_through_core(): void
    {
        Http::fake(['*/v1/me' => Http::response(self::SUPERADMIN), '*/v1/admin/users/*' => Http::response(['status' => 'deleted'])]);
        $this->asAdmin()->postJson('/users/'.self::USER_ID.'/remove')->assertOk()->assertJson(['removed' => true]);
        Http::assertSent(fn (Request $r) => $r->method() === 'DELETE' && str_ends_with($r->url(), '/v1/admin/users/'.self::USER_ID));
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

    public function test_legacy_core_errors_are_translated(): void
    {
        Http::fake(['*/v1/admin/subscriptions/'.self::SUB_ID.'/reissue' => Http::response(['error' => 'subscription has no active grant to reissue'], 404)]);

        $this->asAdmin()->post('/users/'.self::USER_ID.'/subscriptions/'.self::SUB_ID.'/reissue')
            ->assertStatus(404)
            ->assertJsonFragment(['message' => 'У подписки нет ключа — сначала выдайте доступ.']);
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

    public function test_card_endpoints_require_an_admin_session(): void
    {
        Http::fake();
        $this->get('/users/'.self::USER_ID.'/details')->assertStatus(401);
        $this->post('/users/'.self::USER_ID.'/password-reset')->assertStatus(401);
        $this->post('/users/'.self::USER_ID.'/access')->assertStatus(401);
        $this->post('/users/'.self::USER_ID.'/block')->assertStatus(401);
        Http::assertNothingSent();
    }
}
