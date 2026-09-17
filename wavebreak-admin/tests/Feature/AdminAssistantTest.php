<?php

namespace Tests\Feature;

use App\Services\AdminAssistant;
use App\Services\CoreClient;
use Mockery\MockInterface;
use Tests\TestCase;

class AdminAssistantTest extends TestCase
{
    public function test_anonymous_user_cannot_send_commands(): void
    {
        $this->postJson('/assistant/message', ['message' => 'сводка'])
            ->assertUnauthorized();
    }

    public function test_admin_can_receive_an_assistant_reply(): void
    {
        $this->mock(CoreClient::class, function (MockInterface $mock) {
            $mock->shouldReceive('me')->once()->with('access-token')->andReturn(['role' => 'admin']);
        });
        $this->mock(AdminAssistant::class, function (MockInterface $mock) {
            $mock->shouldReceive('reply')->once()->with('access-token', 'сводка', null)->andReturn(['text' => 'Система работает.']);
        });

        $this->withSession(['wavebreak_admin_tokens' => ['access_token' => 'access-token']])
            ->postJson('/assistant/message', ['message' => 'сводка'])
            ->assertOk()
            ->assertJson(['text' => 'Система работает.']);
    }

    public function test_mutation_requires_and_consumes_confirmation_token(): void
    {
        $this->mock(CoreClient::class, function (MockInterface $mock) {
            $mock->shouldReceive('me')->once()->with('access-token')->andReturn(['role' => 'superadmin']);
        });
        $this->mock(AdminAssistant::class, function (MockInterface $mock) {
            $mock->shouldReceive('execute')->once()->with('access-token', [
                'type' => 'subscription_status',
                'id' => 'subscription-id',
                'value' => 'suspended',
            ])->andReturn(['text' => 'Подписка приостановлена.']);
        });
        $confirmation = 'c52bd902-606a-4a16-8d57-3cc02d74c189';

        $this->withSession([
            'wavebreak_admin_tokens' => ['access_token' => 'access-token'],
            'admin_assistant_actions' => [
                $confirmation => [
                    'action' => ['type' => 'subscription_status', 'id' => 'subscription-id', 'value' => 'suspended'],
                    'expires_at' => now()->addMinute()->timestamp,
                ],
            ],
        ])->postJson('/assistant/confirm', ['token' => $confirmation])
            ->assertOk()
            ->assertJson(['text' => 'Подписка приостановлена.'])
            ->assertSessionMissing("admin_assistant_actions.{$confirmation}");
    }
}
