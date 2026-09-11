<?php

namespace Tests\Feature;

use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class PushSubscriptionsTest extends TestCase
{
    use RefreshDatabase;

    public function test_authenticated_user_can_subscribe_check_status_and_unsubscribe(): void
    {
        $user = User::factory()->create();
        $payload = [
            'endpoint' => 'https://fcm.googleapis.com/fcm/send/test-token',
            'p256dh' => str_repeat('a', 88),
            'auth' => str_repeat('b', 24),
            'content_encoding' => 'aes128gcm',
        ];

        $this->actingAs($user)
            ->postJson('/push/subscribe', $payload)
            ->assertOk()
            ->assertJsonPath('ok', true);

        $this->assertDatabaseHas('push_subscriptions', [
            'subscribable_type' => User::class,
            'subscribable_id' => $user->id,
            'endpoint' => $payload['endpoint'],
        ]);

        $this->actingAs($user)
            ->getJson('/push/status')
            ->assertOk()
            ->assertJsonPath('subscribed', true);

        $this->actingAs($user)
            ->deleteJson('/push/subscribe', ['endpoint' => $payload['endpoint']])
            ->assertOk()
            ->assertJsonPath('ok', true);

        $this->actingAs($user)
            ->getJson('/push/status')
            ->assertOk()
            ->assertJsonPath('subscribed', false);
    }

    public function test_guest_cannot_subscribe_to_push(): void
    {
        $this->postJson('/push/subscribe', [
            'endpoint' => 'https://fcm.googleapis.com/fcm/send/test-token',
            'p256dh' => str_repeat('a', 88),
            'auth' => str_repeat('b', 24),
        ])->assertUnauthorized();
    }
}
