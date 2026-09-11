<?php

namespace Tests\Feature;

use App\Models\AccountRecoveryToken;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Tests\TestCase;

class AccountRecoveryTest extends TestCase
{
    use RefreshDatabase;

    public function test_user_without_linked_telegram_is_redirected_to_support(): void
    {
        User::factory()->create([
            'username' => 'plain_user',
            'telegram_id' => null,
        ]);

        $this->post(route('account-recovery.request.submit'), [
            'identifier' => 'plain_user',
        ])->assertRedirect('https://t.me/auralith_support');
    }

    public function test_linked_telegram_can_confirm_recovery_and_reset_password(): void
    {
        $user = User::factory()->create([
            'username' => 'tg_user',
            'telegram_id' => 701337001,
            'password' => Hash::make('old-password'),
            'has_password' => true,
        ]);

        $response = $this->post(route('account-recovery.request.submit'), [
            'identifier' => 'tg_user',
        ])->assertOk();

        $deepLink = $response->viewData('deepLink');
        $this->assertIsString($deepLink);
        preg_match('/recover_([^&]+)/', $deepLink, $matches);
        $this->assertNotEmpty($matches[1] ?? null);
        $requestToken = $matches[1];

        $this->postJson(route('webhook.telegram-recovery'), [
            'recovery_token' => $requestToken,
            'telegram_id' => 123,
        ])->assertForbidden();

        $this->postJson(route('webhook.telegram-recovery'), [
            'recovery_token' => $requestToken,
            'telegram_id' => 701337001,
        ])->assertOk();

        $status = $this->getJson(route('account-recovery.status', ['token' => $requestToken]))
            ->assertOk()
            ->assertJson(['confirmed' => true])
            ->json();

        $this->assertNotEmpty($status['redirect'] ?? null);
        preg_match('#/reset-access/([^/?]+)#', $status['redirect'], $resetMatches);
        $this->assertNotEmpty($resetMatches[1] ?? null);

        $this->post(route('account-recovery.reset.submit', ['token' => $resetMatches[1]]), [
            'password' => 'new-password',
            'password_confirmation' => 'new-password',
        ])->assertRedirect(route('login'));

        $this->assertTrue(Hash::check('new-password', $user->fresh()->password));
        $this->assertNotNull(AccountRecoveryToken::query()->first()?->used_at);
    }
}
