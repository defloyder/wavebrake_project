<?php

namespace Tests\Feature;

use App\Models\Notification;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class NotificationsTest extends TestCase
{
    use RefreshDatabase;

    public function test_user_sees_global_and_personal_notifications_only(): void
    {
        $user = User::factory()->create();
        $other = User::factory()->create();

        Notification::query()->create([
            'title' => 'Global',
            'body' => 'For everyone',
            'type' => 'info',
            'is_global' => true,
        ]);
        Notification::query()->create([
            'title' => 'Personal',
            'body' => 'For user',
            'type' => 'success',
            'is_global' => false,
            'user_id' => $user->id,
        ]);
        Notification::query()->create([
            'title' => 'Other',
            'body' => 'For other user',
            'type' => 'warning',
            'is_global' => false,
            'user_id' => $other->id,
        ]);

        $this->actingAs($user)
            ->getJson('/notifications')
            ->assertOk()
            ->assertJsonPath('unread_count', 2)
            ->assertJsonCount(2, 'notifications')
            ->assertJsonMissing(['title' => 'Other']);
    }

    public function test_mark_read_returns_updated_unread_count(): void
    {
        $user = User::factory()->create();
        $notification = Notification::query()->create([
            'title' => 'Notice',
            'body' => 'Body',
            'type' => 'info',
            'is_global' => true,
        ]);

        $this->actingAs($user)
            ->postJson("/notifications/{$notification->id}/read")
            ->assertOk()
            ->assertJsonPath('ok', true)
            ->assertJsonPath('unread_count', 0);
    }
}
