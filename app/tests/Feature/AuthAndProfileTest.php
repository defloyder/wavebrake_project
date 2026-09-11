<?php

namespace Tests\Feature;

use App\Models\User;
use App\Services\CoreApiService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Mockery;
use Tests\TestCase;

class AuthAndProfileTest extends TestCase
{
    use RefreshDatabase;

    public function test_registration_marks_password_as_available_and_logs_user_in(): void
    {
        $this->post('/register', [
            'username' => 'new_user',
            'password' => 'password123',
            'password_confirmation' => 'password123',
            'privacy_consent' => '1',
            'offer_acceptance' => '1',
        ])->assertRedirect(route('profile.index'));

        $this->assertAuthenticated();
        $this->assertDatabaseHas('users', [
            'username' => 'new_user',
            'has_password' => true,
        ]);
    }

    public function test_registration_requires_personal_data_consent(): void
    {
        $this->post('/register', [
            'username' => 'without_consent',
            'password' => 'password123',
            'password_confirmation' => 'password123',
            'offer_acceptance' => '1',
        ])->assertSessionHasErrors('privacy_consent');

        $this->assertGuest();
        $this->assertDatabaseMissing('users', ['username' => 'without_consent']);
    }

    public function test_login_page_explains_telegram_prerequisite(): void
    {
        $this->get('/login')
            ->assertOk()
            ->assertSee('Вход через Telegram', false)
            ->assertSee('Старые ссылки из бота одноразовые', false);
    }

    public function test_profile_warns_when_backup_password_is_missing(): void
    {
        $user = User::factory()->create([
            'username' => 'tg_only',
            'password' => Hash::make('unused-password'),
            'has_password' => false,
        ]);

        $this->actingAs($user)
            ->get('/profile')
            ->assertOk()
            ->assertSee('Запасной вход не настроен', false);
    }

    public function test_user_can_set_backup_password_from_profile(): void
    {
        $user = User::factory()->create([
            'username' => 'tg_user',
            'has_password' => false,
        ]);

        $this->actingAs($user)
            ->post('/profile/set-password', [
                'password' => 'new-password',
                'password_confirmation' => 'new-password',
            ])
            ->assertRedirect(route('profile.index'));

        $user->refresh();

        $this->assertTrue((bool) $user->has_password);
        $this->assertTrue(Hash::check('new-password', $user->password));
    }

    public function test_profile_devices_endpoint_returns_current_user_devices_from_core(): void
    {
        $user = User::factory()->create([
            'username' => 'device_user',
            'core_user_id' => 904,
        ]);

        $core = Mockery::mock(CoreApiService::class);
        $core->shouldReceive('adminUserDevices')
            ->once()
            ->with(904)
            ->andReturn([
                'devices' => [[
                    'id' => 7,
                    'display_name' => 'Work laptop',
                    'platform' => 'windows',
                    'app_version' => '2.2.3',
                    'is_active' => true,
                    'last_seen' => '2026-07-20T07:30:00Z',
                    'rx_bytes' => 1024,
                    'tx_bytes' => 2048,
                    'ip_address' => '203.0.113.7',
                    'user_agent' => 'Hidden from profile',
                ]],
            ]);
        $this->app->instance(CoreApiService::class, $core);

        $response = $this->actingAs($user)->getJson(route('profile.devices'));

        $response
            ->assertOk()
            ->assertJsonPath('ok', true)
            ->assertJsonPath('devices.0.id', 7)
            ->assertJsonPath('devices.0.display_name', 'Work laptop')
            ->assertJsonPath('devices.0.platform', 'windows')
            ->assertJsonPath('devices.0.traffic_bytes', 3072);

        $this->assertArrayNotHasKey('ip_address', $response->json('devices.0'));
        $this->assertArrayNotHasKey('user_agent', $response->json('devices.0'));
    }
}
