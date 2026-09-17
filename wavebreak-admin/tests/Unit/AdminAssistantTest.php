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

    public function test_it_understands_conversational_help(): void
    {
        $reply = (new AdminAssistant($this->createMock(CoreClient::class)))->reply('token', 'А что ты вообще умеешь?');

        $this->assertStringContainsString('Могу показать сводку', $reply['text']);
    }

    public function test_subscription_creation_is_a_multi_step_dialogue(): void
    {
        $core = $this->createMock(CoreClient::class);
        $core->method('users')->willReturn([['id' => 'user-id', 'email' => 'owner@example.com']]);
        $core->method('adminPlans')->willReturn([['id' => 'plan-id', 'code' => 'STARTER', 'name' => 'Starter', 'is_active' => true]]);
        $assistant = new AdminAssistant($core);

        $start = $assistant->reply('token', 'Давай добавим подписку');
        $user = $assistant->reply('token', 'owner@example.com', $start['context']);
        $plan = $assistant->reply('token', 'STARTER', $user['context']);

        $this->assertSame('user', $start['context']['step']);
        $this->assertSame('plan', $user['context']['step']);
        $this->assertSame('subscription_create', $plan['confirmation']['action']['type']);
        $this->assertSame('user-id', $plan['confirmation']['action']['user_id']);
        $this->assertSame('plan-id', $plan['confirmation']['action']['plan_id']);
    }

    public function test_it_resolves_user_email_before_preparing_hard_delete(): void
    {
        $core = $this->createMock(CoreClient::class);
        $core->method('users')->willReturn([['id' => 'user-id', 'email' => 'owner@example.com']]);

        $reply = (new AdminAssistant($core))->reply('token', 'Удали пользователя owner@example.com');

        $this->assertSame('user_delete', $reply['confirmation']['action']['type']);
        $this->assertSame('user-id', $reply['confirmation']['action']['id']);
    }

    public function test_bare_search_starts_a_guided_dialogue(): void
    {
        $assistant = new AdminAssistant($this->createMock(CoreClient::class));

        $start = $assistant->reply('token', 'найди');

        $this->assertSame('search', $start['context']['intent']);
        $this->assertContains('Пользователя', $start['suggestions']);
    }

    public function test_bare_suspend_offers_active_subscriptions_and_prepares_confirmation(): void
    {
        $id = 'a8128415-e459-4813-9c68-52e9a7ceff70';
        $core = $this->createMock(CoreClient::class);
        $core->method('subscriptions')->willReturn([['id' => $id, 'user_id' => 'user-id', 'status' => 'active']]);
        $core->method('users')->willReturn([]);
        $assistant = new AdminAssistant($core);

        $start = $assistant->reply('token', 'приостанови');
        $finish = $assistant->reply('token', $id, $start['context']);

        $this->assertSame('suspend_subscription', $start['context']['intent']);
        $this->assertContains($id, $start['suggestions']);
        $this->assertSame('subscription_status', $finish['confirmation']['action']['type']);
        $this->assertSame('suspended', $finish['confirmation']['action']['value']);
    }
}
