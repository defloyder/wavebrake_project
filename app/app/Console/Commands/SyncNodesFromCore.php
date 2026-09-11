<?php

namespace App\Console\Commands;

use App\Models\Node;
use App\Services\CoreApiService;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

class SyncNodesFromCore extends Command
{
    protected $signature = 'nodes:sync';
    protected $description = 'Sync nodes from Core API to Laravel database';

    public function __construct(private readonly CoreApiService $core)
    {
        parent::__construct();
    }

    public function handle(): int
    {
        $this->info('Starting nodes sync from Core API...');

        $coreNodes = $this->core->adminNodes();
        
        if (! $coreNodes) {
            $this->error('Failed to fetch nodes from Core API');
            return self::FAILURE;
        }

        $synced = 0;

        $coreNodes = array_is_list($coreNodes)
            ? $coreNodes
            : ($coreNodes['nodes'] ?? $coreNodes['data'] ?? []);

        $columns = collect(Schema::getColumnListing('nodes'))->flip();

        foreach ($coreNodes as $coreNode) {
            DB::transaction(function () use ($coreNode, &$synced) {
                $payload = [
                    'ip' => $coreNode['ip'] ?? '',
                    'port' => $coreNode['port'] ?? 443,
                    'api_port' => $coreNode['api_port'] ?? 8443,
                    'api_secret' => $coreNode['api_secret'] ?? $coreNode['pubkey'] ?? '',
                    'status' => $coreNode['status'] ?? 'unknown',
                    'latency' => $coreNode['latency'] ?? null,
                    'load' => $coreNode['load'] ?? 0,
                    'errors' => $coreNode['errors'] ?? 0,
                    'is_active' => $coreNode['is_active'] ?? true,
                ];

                $payload = array_intersect_key($payload, Schema::getColumnListing('nodes') ? array_flip(Schema::getColumnListing('nodes')) : []);

                Node::query()->updateOrCreate(
                    ['name' => $coreNode['name'] ?? 'unknown'],
                    $payload,
                );
                $synced++;
            });

            $this->info("Synced node: {$coreNode['name']}");
        }

        $this->info("Sync completed: {$synced} nodes synced");
        return self::SUCCESS;
    }
}
