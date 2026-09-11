<?php

namespace App\Console\Commands;

use App\Models\Node;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\Http;

class SyncNodes extends Command
{
    protected $signature   = 'nodes:sync-legacy';
    protected $description = 'Sync nodes from Core API into local DB';

    public function handle(): int
    {
        $url    = config('services.core.url') . '/admin/nodes';
        $apiKey = config('services.core.admin_key');

        $this->info("Fetching nodes from {$url}...");

        try {
            $response = Http::withHeaders(['X-Admin-Key' => $apiKey])
                ->timeout(10)
                ->get($url);
        } catch (\Throwable $e) {
            $this->error('API unreachable: ' . $e->getMessage());
            return 1;
        }

        if (! $response->successful()) {
            $this->error('API returned ' . $response->status() . ': ' . $response->body());
            return 1;
        }

        $apiNodes = collect($response->json());
        $apiIds   = $apiNodes->pluck('id')->all();

        // Upsert each node from API
        foreach ($apiNodes as $n) {
            Node::updateOrCreate(
                ['id' => $n['id']],
                [
                    'name'       => $n['name'],
                    'ip'         => $n['ip'],
                    'port'       => $n['port']     ?? 443,
                    'api_port'   => $n['api_port'] ?? 8443,
                    'api_secret' => $n['pubkey']   ?? '',
                    'status'     => $n['status']   ?? 'unknown',
                    'latency'    => $n['latency']  ?? null,
                    'load'       => $n['load']     ?? 0,
                    'errors'     => $n['errors']   ?? 0,
                    'is_active'  => $n['is_active'] ?? true,
                ]
            );
            $this->line("  ✓ {$n['name']} ({$n['ip']}) — {$n['status']}");
        }

        // Delete nodes not in API
        $deleted = Node::whereNotIn('id', $apiIds)->delete();
        if ($deleted) {
            $this->warn("  Deleted {$deleted} stale node(s) from local DB.");
        }

        $this->info("Sync complete. {$apiNodes->count()} node(s) in DB.");
        return 0;
    }
}
