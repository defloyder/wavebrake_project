<?php

namespace Database\Seeders;

use App\Models\Plan;
use App\Models\Subscription;
use App\Models\User;
use App\Models\Node;
use Illuminate\Support\Str;
use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\Hash;

class DemoUserSeeder extends Seeder
{
    /**
     * Run the database seeds.
     */
    public function run(): void
    {
        $user = User::query()->updateOrCreate(
            ['email' => 'demo@auralith.test'],
            [
                'name' => 'Test User',
                'username' => 'auralith_demo',
                'telegram_id' => 701337001,
                'token' => (string) Str::uuid(),
                'client_uuid' => (string) Str::uuid(),
                'trial_used' => true,
                'password' => Hash::make('demo12345'),
            ]
        );

        $plan = Plan::query()->where('duration_months', 3)->first() ?? Plan::query()->first();
        $node = Node::query()->where('status', 'alive')->orderBy('latency')->first();

        if (! $plan) {
            return;
        }

        Subscription::query()->updateOrCreate(
            ['user_id' => $user->id],
            [
                'plan_id' => $plan->id,
                'node_id' => $node?->id,
                'email' => $user->email,
                'telegram' => '@auralith_demo',
                'status' => 'active',
                'traffic_used_gb' => 168.4,
                'traffic_limit_gb' => 500,
                'avg_speed_mbps' => 124,
                'peak_speed_mbps' => 356,
                'devices_online' => 3,
                'last_sync_at' => now(),
                'starts_at' => now()->subDays(11),
                'ends_at' => now()->addDays(79),
            ]
        );
    }
}
