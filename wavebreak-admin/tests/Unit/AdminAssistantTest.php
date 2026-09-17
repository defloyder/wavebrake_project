<?php

namespace Tests\Unit;

use App\Services\AdminAssistant;
use App\Services\CoreClient;
use PHPUnit\Framework\TestCase;

class AdminAssistantTest extends TestCase
{
    public function test_it_builds_a_live_overview(): void
    {
        $core = $this->createMock(CoreClient::class);
        $core->method('dashboard')->willReturn(['status' => 'ok']);
        $core->method('nodes')->willReturn([['status' => 'online'], ['status' => 'offline']]);
        $core->method('subscriptions')->willReturn([['status' => 'active'], ['status' => 'suspended']]);
        $core->method('users')->willReturn([['id' => 'u1'], ['id' => 'u2']]);
        $core->method('traffic')->willReturn([['bytes_total' => 1073741824]]);

        $reply = (new AdminAssistant($core))->reply('token', 'сводка');

        $this->assertStringContainsString('Узлы: 1 из 2', $reply['text']);
        $this->assertStringContainsString('Активных подписок: 1 из 2', $reply['text']);
        $this->assertCount(4, $reply['facts']);
    }

    public function test_mutation_is_only_prepared_for_confirmation(): void
    {
        $core = $this->createMock(CoreClient::class);
        $id = 'a8128415-e459-4813-9c68-52e9a7ceff70';

        $reply = (new AdminAssistant($core))->reply('token', "приостанови подписку {$id}");

        $this->assertSame('subscription_status', $reply['confirmation']['action']['type']);
        $this->assertSame('suspended', $reply['confirmation']['action']['value']);
        $this->assertSame($id, $reply['confirmation']['action']['id']);
    }

    public function test_confirmation_executes_the_prepared_action(): void
    {
        $core = $this->createMock(CoreClient::class);
        $core->expects($this->once())->method('updateSubscriptionStatus')->with('token', 'subscription-id', 'active')->willReturn([]);

        $reply = (new AdminAssistant($core))->execute('token', [
            'type' => 'subscription_status',
            'id' => 'subscription-id',
            'value' => 'active',
        ]);

        $this->assertStringContainsString('active', $reply['text']);
    }
}
