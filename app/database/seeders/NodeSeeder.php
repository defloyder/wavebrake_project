<?php

namespace Database\Seeders;

use App\Models\Node;
use Illuminate\Database\Seeder;

class NodeSeeder extends Seeder
{
    /**
     * Run the database seeds.
     */
    public function run(): void
    {
        Node::query()->delete();

        Node::insert([
            [
                'name' => 'NL1',
                'ip' => '145.223.72.10',
                'port' => 443,
                'api_port' => 8443,
                'api_secret' => 'demo-node-secret-nl1',
                'status' => 'alive',
                'latency' => 31,
                'load' => 0.32,
                'errors' => 0,
                'is_active' => true,
                'created_at' => now(),
                'updated_at' => now(),
            ],
            [
                'name' => 'FIN1',
                'ip' => '85.117.55.41',
                'port' => 443,
                'api_port' => 8443,
                'api_secret' => 'demo-node-secret-fin1',
                'status' => 'alive',
                'latency' => 44,
                'load' => 0.24,
                'errors' => 1,
                'is_active' => true,
                'created_at' => now(),
                'updated_at' => now(),
            ],
            [
                'name' => 'UK1',
                'ip' => '185.220.101.42',
                'port' => 443,
                'api_port' => 8443,
                'api_secret' => 'demo-node-secret-uk1',
                'status' => 'alive',
                'latency' => 38,
                'load' => 0.41,
                'errors' => 0,
                'is_active' => true,
                'created_at' => now(),
                'updated_at' => now(),
            ],
            [
                'name' => 'TR1',
                'ip' => '91.108.56.14',
                'port' => 443,
                'api_port' => 8443,
                'api_secret' => 'demo-node-secret-tr1',
                'status' => 'alive',
                'latency' => 67,
                'load' => 0.28,
                'errors' => 0,
                'is_active' => true,
                'created_at' => now(),
                'updated_at' => now(),
            ],
        ]);
    }
}
