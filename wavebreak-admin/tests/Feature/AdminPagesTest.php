<?php

namespace Tests\Feature;

use Illuminate\Http\Client\Request;
use Illuminate\Support\Facades\Http;
use Tests\TestCase;

/**
 * Admin pages: rows open the user card (no per-row action buttons), ids
 * are resolved to emails / plan names / node codes, dates are local and
 * day-first, and each page loads only the Core data it shows.
 */
class AdminPagesTest extends TestCase
{
    private const USER_ID = '6f0b9a4e-1111-4222-8333-444455556666';

    private const PLAN_ID = '0c7c5f7e-2222-4333-8444-555566667777';

    private const SUB_ID = '7a0b9a4e-1111-4222-8333-444455556666';

    private const NODE_ID = '1b1b1b1b-3333-4444-8555-666677778888';

    private const GRANT_ID = '9c1d2e3f-aaaa-4bbb-8ccc-ddddeeeeffff';

    private function asAdmin(): self
    {
        return $this->withSession(['wavebreak_admin_tokens' => ['access_token' => 'access-token']]);
    }

    /** @param array<string, mixed> $overrides stubs that replace the defaults */
    private function fakeCore(array $overrides = []): void
    {
        $user = ['id' => self::USER_ID, 'email' => 'user@example.com', 'username' => 'neo', 'role' => 'user', 'status' => 'active',
            'created_at' => '2026-09-01T10:00:00Z', 'last_login_at' => '2026-09-26T21:30:00Z',
            'subscription' => ['id' => self::SUB_ID, 'plan_id' => self::PLAN_ID, 'plan_name' => 'Plus', 'status' => 'active', 'current_period_end' => '2026-10-27T00:00:00Z']];

        Http::fake($overrides + [
            '*/healthz' => Http::response(['status' => 'ok']),
            '*/v1/me' => Http::response(['id' => 'admin-1', 'email' => 'admin@example.com', 'role' => 'admin']),
            '*/v1/nodes' => Http::response(['nodes' => [['id' => self::NODE_ID, 'code' => 'TR-PILOT-01', 'region' => 'TR', 'status' => 'online', 'desired_revision' => 5, 'applied_revision' => 5, 'last_heartbeat_at' => '2026-09-27T01:00:00Z']]]),
            '*/v1/admin/dashboard' => Http::response(['users' => 1, 'active_users' => 1, 'subscriptions' => 1, 'active_subscriptions' => 1, 'plans' => 1, 'nodes' => 1, 'nodes_online' => 1, 'access_grants' => 1, 'bytes_total' => 5368709120]),
            '*/v1/admin/users' => Http::response(['users' => [$user, ['id' => 'admin-1', 'email' => 'admin@example.com', 'role' => 'admin', 'status' => 'active', 'created_at' => '2026-08-01T00:00:00Z']]]),
            '*/v1/admin/plans' => Http::response(['plans' => [['id' => self::PLAN_ID, 'code' => 'plus-monthly', 'name' => 'Plus', 'price_minor' => 499, 'currency' => 'USD', 'interval' => 'month', 'device_limit' => 3, 'traffic_limit_bytes' => 107374182400, 'is_active' => true, 'is_public' => true]]]),
            '*/v1/admin/subscriptions' => Http::response(['subscriptions' => [[
                'id' => self::SUB_ID, 'user_id' => self::USER_ID, 'plan_id' => self::PLAN_ID, 'status' => 'active', 'source' => 'purchase',
                'traffic_limit_bytes_snapshot' => 107374182400, 'device_limit_snapshot' => 3, 'current_period_end' => '2026-10-27T00:00:00Z',
            ]]]),
            '*/v1/admin/access/grants' => Http::response(['grants' => [['id' => self::GRANT_ID, 'user_id' => self::USER_ID, 'subscription_id' => self::SUB_ID, 'node_id' => self::NODE_ID, 'protocol' => 'vless', 'status' => 'active', 'expires_at' => '2026-10-27T00:00:00Z', 'created_at' => '2026-09-27T00:00:00Z']]]),
            '*/v1/admin/traffic' => Http::response(['traffic' => [['subscription_id' => self::SUB_ID, 'user_id' => self::USER_ID, 'status' => 'active', 'bytes_up' => 1073741824, 'bytes_down' => 4294967296, 'bytes_total' => 5368709120, 'limit_bytes' => 107374182400]]]),
            '*/v1/admin/traffic/history*' => Http::response(['history' => []]),
            '*/v1/admin/devices' => Http::response(['devices' => [['id' => 'd1', 'user_id' => self::USER_ID, 'name' => 'Pixel 9', 'platform' => 'android', 'created_at' => '2026-09-20T00:00:00Z', 'last_seen_at' => null]]]),
            '*/v1/admin/audit' => Http::response(['events' => [['id' => 'e1', 'actor_user_id' => 'admin-1', 'action' => 'user.disabled', 'target_type' => 'user', 'target_id' => self::USER_ID, 'metadata' => [], 'created_at' => '2026-09-27T09:15:00Z']]]),
            '*' => Http::response([], 404),
        ]);
    }

    public function test_users_rows_open_the_card_and_have_no_action_buttons(): void
    {
        $this->fakeCore();

        $this->asAdmin()->get('/users')
            ->assertOk()
            ->assertSee('Пользователи')
            ->assertSee('user@example.com')
            ->assertSee('data-open-user="'.self::USER_ID.'"', false)
            ->assertSee('id="adm-user-card"', false)
            ->assertSee('Plus')
            ->assertSee('до 27.10.2026')
            ->assertSee('27.09.2026 00:30') // 21:30Z in Europe/Istanbul
            ->assertDontSee('Заблокировать')
            ->assertDontSee('/users/'.self::USER_ID.'/disable', false)
            ->assertDontSee('adm-role-select', false);

        // Only what the page shows is loaded.
        Http::assertNotSent(fn (Request $r) => str_contains($r->url(), '/v1/admin/subscriptions'));
        Http::assertNotSent(fn (Request $r) => str_contains($r->url(), '/v1/admin/audit'));
    }

    public function test_subscriptions_show_plan_names_emails_and_local_dates_not_ids(): void
    {
        $this->fakeCore();

        $this->asAdmin()->get('/subscriptions')
            ->assertOk()
            ->assertSee('user@example.com')
            ->assertSee('<strong>Plus</strong>', false)
            ->assertSee('27.10.2026')
            ->assertSee('5 ГБ')
            ->assertSee('100 ГБ')
            ->assertSee('Покупка')
            ->assertSee('data-open-user="'.self::USER_ID.'"', false)
            ->assertDontSee('>'.self::PLAN_ID.'<', false)
            ->assertDontSee('2026-10-27T00:00:00Z')
            ->assertDontSee('/subscriptions/'.self::SUB_ID.'/delete', false)
            ->assertDontSee('ключ не выдан');
    }

    public function test_subscription_without_active_grant_is_flagged(): void
    {
        $this->fakeCore(['*/v1/admin/access/grants' => Http::response(['grants' => []])]);

        $this->asAdmin()->get('/subscriptions')->assertOk()->assertSee('ключ не выдан');
    }

    public function test_plans_page_uses_names_currency_and_gb(): void
    {
        $this->fakeCore();

        $this->asAdmin()->get('/plans')
            ->assertOk()
            ->assertSee('Plus')
            ->assertSee('4,99 $')
            ->assertSee('100 ГБ')
            ->assertSee('data-open-plan=', false)
            ->assertSee('name="traffic_limit_gb"', false)
            ->assertSee('name="price"', false)
            ->assertDontSee('Price (cents)');
    }

    public function test_grants_devices_traffic_and_audit_resolve_ids(): void
    {
        $this->fakeCore();

        $this->asAdmin()->get('/grants')->assertOk()
            ->assertSee('WVB-9C1D2E3F')->assertSee('TR-PILOT-01')->assertSee('user@example.com')
            ->assertDontSee('>'.self::NODE_ID.'<', false);
        $this->asAdmin()->get('/devices')->assertOk()
            ->assertSee('Pixel 9')->assertSee('Android')->assertSee('user@example.com')->assertSee('нет данных');
        $this->asAdmin()->get('/traffic')->assertOk()
            ->assertSee('Plus')->assertSee('4 ГБ')->assertSee('1 ГБ')->assertSee('5 ГБ');
        $this->asAdmin()->get('/audit')->assertOk()
            ->assertSee('Пользователь заблокирован')->assertSee('Пользователь · user@example.com')->assertSee('admin@example.com')->assertSee('27.09.2026 12:15')
            ->assertDontSee('>admin-1<', false);
    }

    public function test_every_section_renders(): void
    {
        $this->fakeCore();

        foreach (['dashboard', 'users', 'subscriptions', 'plans', 'nodes', 'grants', 'devices', 'traffic', 'audit', 'enroll'] as $section) {
            $this->asAdmin()->get('/'.$section)->assertOk()->assertSee('adm-section-title', false);
        }
    }

    public function test_pages_require_sign_in(): void
    {
        Http::fake(['*/healthz' => Http::response(['status' => 'ok'])]);

        $this->get('/users')->assertOk()->assertSee('name="password"', false)->assertDontSee('adm-user-card', false);
    }
}
