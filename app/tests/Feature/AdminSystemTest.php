<?php

namespace Tests\Feature;

use App\Services\NodeMonitorService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class AdminSystemTest extends TestCase
{
    use RefreshDatabase;

    public function test_system_page_requires_admin_session(): void
    {
        $this->get(route('admin.system.index'))
            ->assertRedirect(route('admin.login'));
    }

    public function test_admin_can_open_system_page(): void
    {
        $this->fakeNodeMonitor();

        $this->withSession(['admin_id' => 1, 'admin_name' => 'Admin'])
            ->get(route('admin.system.index'))
            ->assertOk()
            ->assertSee('Проверка состояния', false)
            ->assertSee('Запустить тесты', false);
    }

    private function fakeNodeMonitor(): void
    {
        $this->app->instance(NodeMonitorService::class, new class extends NodeMonitorService {
            public function health(): array
            {
                return [
                    'alive_nodes' => 0,
                    'total_nodes' => 0,
                    'avg_load_percent' => 0,
                    'nodes' => [],
                ];
            }
        });
    }
}
