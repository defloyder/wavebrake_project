<?php

namespace App\Http\Controllers;

use App\Models\Plan;
use App\Models\User;
use App\Services\NodeMonitorService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Illuminate\View\View;
use Symfony\Component\Process\Process;

class AdminSystemController extends Controller
{
    public function __construct(private readonly NodeMonitorService $monitor) {}

    public function index(): View
    {
        return view('admin.system', [
            'resources' => AdminPanelController::resources(),
            'serverHealth' => $this->monitor->health(),
            'checks' => $this->checks(),
            'checkedAt' => now()->toIso8601String(),
            'testRunnerLabel' => $this->testRunnerLabel(),
            'testResult' => session('system_test_result'),
        ]);
    }

    public function checksJson(): JsonResponse
    {
        return response()->json([
            'checks' => $this->checks(),
            'checked_at' => now()->toIso8601String(),
        ]);
    }

    public function runTests(Request $request): \Illuminate\Http\RedirectResponse
    {
        $phpunit = base_path('vendor/phpunit/phpunit/phpunit');

        if (! is_file($phpunit)) {
            return redirect()
                ->route('admin.system.index')
                ->with('system_test_result', [
                    'ok' => false,
                    'exit_code' => null,
                    'output' => 'PHPUnit binary not found at vendor/phpunit/phpunit/phpunit',
                ]);
        }

        $php = $this->phpCliBinary();

        if ($php === null) {
            return redirect()
                ->route('admin.system.index')
                ->with('system_test_result', [
                    'ok' => false,
                    'exit_code' => null,
                    'output' => 'PHP CLI binary not found. Set PHP_CLI_BINARY=/usr/bin/php in .env.',
                ]);
        }

        $process = new Process([$php, $phpunit, '--testdox'], base_path(), [
            'APP_ENV' => 'testing',
        ]);
        $process->setTimeout(180);
        $process->run();

        return redirect()
            ->route('admin.system.index')
            ->with('system_test_result', [
                'ok' => $process->isSuccessful(),
                'exit_code' => $process->getExitCode(),
                'output' => trim($process->getOutput() . "\n" . $process->getErrorOutput()),
            ]);
    }

    private function checks(): array
    {
        return [
            $this->check('database', 'База данных', function (): string {
                DB::select('select 1');

                return 'Соединение работает';
            }),
            $this->check('tables', 'Ключевые таблицы', function (): string {
                $required = ['users', 'plans', 'subscriptions', 'notifications', 'push_subscriptions', 'cp_orders'];
                $missing = array_values(array_filter($required, fn (string $table): bool => ! Schema::hasTable($table)));

                if ($missing !== []) {
                    throw new \RuntimeException('Нет таблиц: ' . implode(', ', $missing));
                }

                return 'Все ключевые таблицы на месте';
            }),
            $this->check('content', 'Контент витрины', function (): string {
                return 'Пользователей: ' . User::query()->count() . ', тарифов: ' . Plan::query()->count();
            }),
            $this->check('webpush', 'Web Push ключи', function (): string {
                if (! filled(config('webpush.vapid.public_key')) || ! filled(config('webpush.vapid.private_key'))) {
                    throw new \RuntimeException('VAPID ключи не настроены');
                }

                return 'VAPID ключи настроены';
            }),
            $this->check('storage', 'Storage/logs', function (): string {
                if (! is_writable(storage_path('logs'))) {
                    throw new \RuntimeException('storage/logs недоступен для записи');
                }

                return 'Логи доступны для записи';
            }),
            $this->check('seo', 'SEO файлы', function (): string {
                foreach ([public_path('robots.txt'), public_path('sitemap.xml')] as $file) {
                    if (! is_file($file)) {
                        throw new \RuntimeException(basename($file) . ' отсутствует');
                    }
                }

                return 'robots.txt и sitemap.xml доступны';
            }),
        ];
    }

    public function testRunnerLabel(): string
    {
        if (! is_file(base_path('vendor/phpunit/phpunit/phpunit'))) {
            return 'PHPUnit не найден';
        }

        $php = $this->phpCliBinary();

        return $php ? 'PHP CLI: ' . $php : 'PHP CLI не найден';
    }

    private function phpCliBinary(): ?string
    {
        $candidates = array_filter([
            env('PHP_CLI_BINARY'),
            PHP_BINARY,
            PHP_BINDIR ? PHP_BINDIR . DIRECTORY_SEPARATOR . 'php' : null,
            '/usr/bin/php',
            '/usr/local/bin/php',
            'php',
        ]);

        foreach ($candidates as $candidate) {
            if (str_contains(basename($candidate), 'fpm')) {
                continue;
            }

            if ($candidate === 'php' || (is_file($candidate) && is_executable($candidate))) {
                return $candidate;
            }
        }

        return null;
    }

    private function check(string $key, string $label, \Closure $callback): array
    {
        try {
            return [
                'key' => $key,
                'label' => $label,
                'ok' => true,
                'message' => $callback(),
            ];
        } catch (\Throwable $e) {
            return [
                'key' => $key,
                'label' => $label,
                'ok' => false,
                'message' => $e->getMessage(),
            ];
        }
    }
}
