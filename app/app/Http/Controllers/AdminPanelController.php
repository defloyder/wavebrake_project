<?php

namespace App\Http\Controllers;

use App\Models\CpOrder;
use App\Models\ClientRelease;
use App\Models\Lead;
use App\Models\Node;
use App\Models\AdminLog;
use App\Models\Plan;
use App\Models\PromoCode;
use App\Models\Subscription;
use App\Models\User;
use App\Services\ClientReleaseService;
use App\Services\CoreApiService;
use App\Services\NodeMonitorService;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Pagination\LengthAwarePaginator;
use Illuminate\Support\Arr;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\Artisan;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Schema;
use Illuminate\View\View;

class AdminPanelController extends Controller
{
    public function __construct(
        private readonly NodeMonitorService $monitor,
        private readonly CoreApiService $core,
        private readonly ClientReleaseService $clientReleases,
    ) {}
    private const RESOURCES = [
        'users' => [
            'model' => User::class,
            'title' => 'Пользователи',
            'fields' => ['core_user_id', 'name', 'username', 'telegram_id', 'trial_used'],
            'search_fields' => ['id', 'core_user_id', 'username', 'name', 'telegram_id'],
            'sortable' => ['id', 'core_user_id', 'username', 'created_at'],
            'editable' => false,
            'creatable' => false,
            'deletable' => false,
            'selects' => [],
        ],
        'plans' => [
            'model' => Plan::class,
            'title' => 'Тарифы',
            'fields' => ['name', 'duration_months', 'price_rub', 'headline', 'features', 'is_highlighted'],
            'search_fields' => ['id', 'name', 'headline', 'duration_months', 'price_rub'],
            'sortable' => ['id', 'name', 'duration_months', 'price_rub', 'is_highlighted'],
            'editable' => true,
            'creatable' => true,
            'selects' => [],
        ],
        'nodes' => ['model' => Node::class, 'title' => 'Ноды', 'fields' => ['name', 'ip', 'country', 'city', 'lat', 'lng', 'port', 'api_port', 'status', 'is_active', 'hidden_on_dashboard'], 'editable' => true, 'creatable' => true, 'selects' => []],
        'subscriptions' => [
            'model' => Subscription::class,
            'title' => 'Подписки',
            'fields' => ['user_id', 'plan_id', 'status', 'starts_at', 'ends_at'],
            'display_fields' => [
                'user_id' => ['relation' => 'user', 'column' => 'username'],
                'plan_id' => ['relation' => 'plan', 'column' => 'name'],
            ],
            'search_fields' => ['user_id', 'plan_id', 'status'],
            'sortable' => ['id', 'plan_id', 'status', 'starts_at', 'ends_at'],
            'editable' => true,
            'creatable' => true,
            'deletable' => false,
            'selects' => [
                'status' => [
                    'active' => 'active',
                    'trial' => 'trial',
                    'inactive' => 'inactive',
                    'expiring_soon' => 'expiring_soon',
                ],
            ],
        ],
        'cp_orders' => [
            'model' => CpOrder::class,
            'title' => 'CloudPayments',
            'fields' => ['invoice_id', 'user_id', 'plan_id', 'amount', 'currency', 'payment_method', 'status', 'paid_at', 'failed_at'],
            'display_fields' => [
                'user_id' => ['relation' => 'user', 'column' => 'username'],
                'plan_id' => ['relation' => 'plan', 'column' => 'name'],
            ],
            'search_fields' => ['invoice_id', 'transaction_id', 'user_id', 'plan_id', 'status'],
            'sortable' => ['id', 'amount', 'status', 'paid_at', 'failed_at', 'created_at'],
            'editable' => false,
            'creatable' => false,
            'deletable' => false,
            'hidden' => true,
            'selects' => [],
        ],
        'orders' => [
            'model' => CpOrder::class,
            'title' => 'Заказы',
            'fields' => ['invoice_id', 'user_id', 'plan_id', 'promo_code', 'amount', 'discount_amount', 'currency', 'payment_method', 'status', 'paid_at', 'failed_at'],
            'display_fields' => [
                'user_id' => ['relation' => 'user', 'column' => 'username'],
                'plan_id' => ['relation' => 'plan', 'column' => 'name'],
            ],
            'search_fields' => ['invoice_id', 'transaction_id', 'user_id', 'plan_id', 'status', 'promo_code'],
            'sortable' => ['id', 'amount', 'discount_amount', 'status', 'paid_at', 'failed_at', 'created_at'],
            'editable' => false,
            'creatable' => false,
            'deletable' => false,
            'selects' => [],
        ],
        'promo_codes' => [
            'model' => PromoCode::class,
            'title' => 'Промокоды',
            'fields' => ['code', 'type', 'value', 'is_active', 'starts_at', 'expires_at', 'max_uses', 'used_count'],
            'create_fields' => ['code', 'type', 'value', 'is_active', 'starts_at', 'expires_at', 'max_uses'],
            'persist_fields' => ['code', 'type', 'value', 'is_active', 'starts_at', 'expires_at', 'max_uses'],
            'search_fields' => ['code', 'type'],
            'sortable' => ['id', 'code', 'type', 'value', 'expires_at', 'used_count'],
            'editable' => true,
            'creatable' => true,
            'selects' => [
                'type' => [
                    'percent' => 'Процент',
                    'fixed' => 'Фиксированная скидка',
                    'duration_days' => 'Дни подписки',
                ],
            ],
        ],
        'leads' => [
            'model' => Lead::class,
            'title' => 'Заявки',
            'fields' => ['name', 'email', 'message', 'status', 'created_at'],
            'search_fields' => ['name', 'email', 'status'],
            'sortable' => ['id', 'name', 'status', 'created_at'],
            'editable' => true,
            'creatable' => false,
            'selects' => [
                'status' => [
                    'new' => 'Новая',
                    'in_progress' => 'В работе',
                    'done' => 'Выполнена',
                ],
            ],
        ],
    ];

    public static function resources(): array
    {
        return self::RESOURCES;
    }

    public function logs(Request $request): View
    {
        $allowedSorts = ['id', 'admin_id', 'action', 'resource', 'resource_id', 'ip', 'created_at'];
        $sortBy = (string) $request->query('sort', 'created_at');
        $sortDir = strtolower((string) $request->query('dir', 'desc')) === 'asc' ? 'asc' : 'desc';
        $logsUnavailable = false;
        if (!in_array($sortBy, $allowedSorts, true)) {
            $sortBy = 'created_at';
        }

        if (Schema::hasTable('admin_logs')) {
            $logs = AdminLog::query()
                ->with('admin')
                ->when($request->query('admin_id'), fn($q, $v) => $q->where('admin_id', $v))
                ->when($request->query('action'), fn($q, $v) => $q->where('action', $v))
                ->orderBy($sortBy, $sortDir)
                ->paginate(30)
                ->withQueryString();
        } else {
            $logsUnavailable = true;
            $logs = new LengthAwarePaginator(
                items: [],
                total: 0,
                perPage: 30,
                currentPage: max(1, (int) $request->query('page', 1)),
                options: ['path' => $request->url(), 'query' => $request->query()],
            );
        }

        $admins = Schema::hasTable('admins')
            ? \App\Models\Admin::query()->select('id', 'username', 'name')->get()
            : collect();

        return view('admin.logs', [
            'logs' => $logs,
            'admins' => $admins,
            'logsUnavailable' => $logsUnavailable,
            'resources' => self::RESOURCES,
            'serverHealth' => $this->monitor->health(),
        ]);
    }

    public function dashboard(): View
    {
        $this->refreshCoreAdminSnapshots();

        $serverHealth = $this->monitor->health();
        $revenuePeriod = request('revenue_period', 'month');
        if (! in_array($revenuePeriod, ['week', 'month', 'year', 'all'], true)) {
            $revenuePeriod = 'month';
        }

        $revenueQuery = CpOrder::query()
            ->where('status', 'paid')
            ->when(Schema::hasColumn('cp_orders', 'raw_payload'), fn ($query) => $query->whereNotNull('raw_payload'));
        match ($revenuePeriod) {
            'week' => $revenueQuery->where('paid_at', '>=', now()->subWeek()),
            'month' => $revenueQuery->where('paid_at', '>=', now()->subMonth()),
            'year' => $revenueQuery->where('paid_at', '>=', now()->subYear()),
            default => null,
        };

        $stats = [
            'users' => User::query()
                ->when(Schema::hasColumn('users', 'core_user_id'), fn ($query) => $query->whereNotNull('core_user_id'))
                ->count(),
            'active_subscriptions' => Subscription::query()
                ->whereIn('status', ['active', 'trial'])
                ->when(Schema::hasColumn('subscriptions', 'last_sync_at'), fn ($query) => $query->whereNotNull('last_sync_at'))
                ->where(function ($query): void {
                    $query->whereNull('ends_at')
                        ->orWhere('ends_at', '>', now());
                })
                ->count(),
            'orders' => CpOrder::query()
                ->when(Schema::hasColumn('cp_orders', 'raw_payload'), fn ($query) => $query->whereNotNull('raw_payload'))
                ->count(),
            'revenue' => $revenueQuery->sum('amount'),
            'nodes_alive' => $serverHealth['alive_nodes'],
            'nodes_total' => $serverHealth['total_nodes'],
            'new_leads' => Lead::query()->where('status', 'new')->count(),
        ];

        $coreStats = $this->core->adminStats();
        if (is_array($coreStats)) {
            $stats = $this->mergeCoreDashboardStats($stats, $coreStats, $revenuePeriod);
        }

        $trafficSummary = $this->dashboardTrafficSummary(
            is_array($coreStats) ? $coreStats : $this->core->adminTrafficSummary(),
            $serverHealth,
        );
        $latestOrders = CpOrder::query()
            ->with(['user', 'plan'])
            ->when(Schema::hasColumn('cp_orders', 'raw_payload'), fn ($query) => $query->whereNotNull('raw_payload'))
            ->orderByRaw('COALESCE(paid_at, created_at) DESC')
            ->limit(6)
            ->get();
        $latestSubscriptions = Subscription::query()
            ->with(['user', 'plan', 'node'])
            ->when(Schema::hasColumn('subscriptions', 'last_sync_at'), fn ($query) => $query->whereNotNull('last_sync_at'))
            ->orderByRaw('COALESCE(starts_at, created_at) DESC')
            ->orderByDesc('id')
            ->limit(6)
            ->get();
        $ordersByStatus = CpOrder::query()
            ->when(Schema::hasColumn('cp_orders', 'raw_payload'), fn ($query) => $query->whereNotNull('raw_payload'))
            ->selectRaw('status, COUNT(*) as total')
            ->groupBy('status')
            ->pluck('total', 'status');

        return view('admin.dashboard', [
            'stats' => $stats,
            'latestOrders' => $latestOrders,
            'latestSubscriptions' => $latestSubscriptions,
            'ordersByStatus' => $ordersByStatus,
            'revenuePeriod' => $revenuePeriod,
            'resources' => self::RESOURCES,
            'serverHealth' => $serverHealth,
            'trafficSummary' => $trafficSummary,
            'recentNotifications' => \App\Models\Notification::query()->orderByDesc('created_at')->limit(50)->get(),
            'clientReleases' => $this->clientReleases->releases(),
            'clientReleaseChannels' => ClientRelease::CHANNELS,
        ]);
    }

    public function diagnostics(): View
    {
        $appClientsResponse = $this->core->adminAppClients();
        $appClients = [];

        if (is_array($appClientsResponse)) {
            $appClients = array_is_list($appClientsResponse)
                ? $appClientsResponse
                : (Arr::get($appClientsResponse, 'clients')
                    ?? Arr::get($appClientsResponse, 'data')
                    ?? Arr::get($appClientsResponse, 'items')
                    ?? []);
        }

        return view('admin.diagnostics', [
            'resources' => self::RESOURCES,
            'serverHealth' => $this->monitor->health(),
            'appClients' => is_array($appClients) ? $appClients : [],
            'appClientsError' => $appClientsResponse === null ? $this->core->lastErrorMessage() : null,
        ]);
    }

    public function updateClientReleases(Request $request): RedirectResponse
    {
        abort_unless(Schema::hasTable('client_releases'), 503, 'Client releases table is not migrated.');

        $data = $request->validate([
            'releases' => ['required', 'array'],
            'releases.*.version' => ['nullable', 'string', 'max:64'],
            'releases.*.download_path' => ['nullable', 'string', 'max:512'],
            'releases.*.latest_json_path' => ['nullable', 'string', 'max:512'],
            'releases.*.notes' => ['nullable', 'string', 'max:2000'],
            'releases.*.is_enabled' => ['nullable'],
        ]);

        foreach (ClientRelease::CHANNELS as $channel => $label) {
            $payload = $data['releases'][$channel] ?? [];

            ClientRelease::query()->updateOrCreate(
                ['channel' => $channel],
                [
                    'label' => $label,
                    'version' => trim((string) ($payload['version'] ?? '')) ?: null,
                    'download_path' => trim((string) ($payload['download_path'] ?? '')) ?: null,
                    'latest_json_path' => trim((string) ($payload['latest_json_path'] ?? '')) ?: null,
                    'notes' => trim((string) ($payload['notes'] ?? '')) ?: null,
                    'is_enabled' => $request->boolean("releases.{$channel}.is_enabled"),
                ],
            );
        }

        $this->log('update', 'client_releases', null, $data['releases']);

        return redirect()
            ->route('admin.dashboard')
            ->with('success', 'Версии клиента обновлены.');
    }

    private function mergeCoreDashboardStats(array $stats, array $coreStats, string $revenuePeriod): array
    {
        $coreStats = $coreStats['stats'] ?? $coreStats['data'] ?? $coreStats;

        $stats['users'] = $this->firstNumeric($coreStats, [
            'users',
            'total_users',
            'users_total',
            'user_count',
        ], $stats['users']);

        $stats['active_subscriptions'] = $this->firstNumeric($coreStats, [
            'active_subscriptions',
            'subscriptions_active',
            'active_users',
            'paid_users',
        ], $stats['active_subscriptions']);

        $stats['orders'] = $this->firstNumeric($coreStats, [
            'orders',
            'total_orders',
            'orders_total',
            'cp_orders',
            'payments_total',
        ], $stats['orders']);

        $revenueKeys = match ($revenuePeriod) {
            'week' => ['revenue_week', 'weekly_revenue', 'revenue_7d'],
            'month' => ['revenue_month', 'monthly_revenue', 'revenue_30d'],
            'year' => ['revenue_year', 'yearly_revenue', 'revenue_365d'],
            default => ['revenue', 'total_revenue', 'revenue_total'],
        };

        $stats['revenue'] = $this->firstNumeric($coreStats, [
            ...$revenueKeys,
            'revenue',
            'total_revenue',
            'revenue_total',
        ], $stats['revenue']);

        return $stats;
    }

    private function dashboardTrafficSummary(?array $coreTraffic, array $serverHealth): array
    {
        $source = is_array($coreTraffic)
            ? ($coreTraffic['traffic'] ?? $coreTraffic['stats'] ?? $coreTraffic['summary'] ?? $coreTraffic['data'] ?? $coreTraffic)
            : [];
        $localUsedGb = (float) Subscription::query()->sum('traffic_used_gb');
        $localLimitGb = (float) Subscription::query()
            ->where('traffic_limit_gb', '>', 0)
            ->sum('traffic_limit_gb');

        $totalBytes = $this->trafficBytes($source, [
            'total_bytes', 'traffic_total_bytes', 'total_traffic_bytes', 'used_bytes', 'total_used_bytes',
        ], [
            'total_gb', 'traffic_total_gb', 'total_traffic_gb', 'used_gb', 'traffic_used_gb',
        ], [
            'total_mb', 'traffic_total_mb', 'total_traffic_mb', 'used_mb', 'traffic_used_mb',
        ]) ?? $this->gbToBytes($localUsedGb);

        $limitBytes = $this->trafficBytes($source, [
            'limit_bytes', 'traffic_limit_bytes',
        ], [
            'limit_gb', 'traffic_limit_gb',
        ], [
            'limit_mb', 'traffic_limit_mb',
        ]) ?? ($localLimitGb > 0 ? $this->gbToBytes($localLimitGb) : null);

        $uploadBytes = $this->trafficBytes($source, [
            'upload_bytes', 'uploaded_bytes', 'tx_bytes',
        ], [
            'upload_gb', 'uploaded_gb', 'tx_gb',
        ], [
            'upload_mb', 'uploaded_mb', 'tx_mb',
        ]);

        $downloadBytes = $this->trafficBytes($source, [
            'download_bytes', 'downloaded_bytes', 'rx_bytes',
        ], [
            'download_gb', 'downloaded_gb', 'rx_gb',
        ], [
            'download_mb', 'downloaded_mb', 'rx_mb',
        ]);

        $nodes = collect($serverHealth['nodes'] ?? [])
            ->reject(fn (array $node): bool => (bool) ($node['hidden_on_dashboard'] ?? false))
            ->sortByDesc(fn (array $node): float => (float) ($node['load_percent'] ?? 0))
            ->take(4)
            ->values()
            ->map(fn (array $node): array => [
                'name' => (string) ($node['name'] ?? 'Node'),
                'status' => (string) ($node['status'] ?? 'unknown'),
                'load_percent' => round((float) ($node['load_percent'] ?? 0), 1),
                'latency' => $node['latency'] ?? null,
            ])
            ->all();

        $avgLoad = round((float) ($serverHealth['avg_load_percent'] ?? 0), 1);
        $peakLoad = collect($nodes)->max('load_percent') ?? $avgLoad;
        $usedPercent = $limitBytes && $limitBytes > 0
            ? min(100, round($totalBytes / $limitBytes * 100, 1))
            : null;

        return [
            'source' => $source === [] ? 'local' : 'core',
            'total_bytes' => $totalBytes,
            'today_bytes' => $this->trafficBytes($source, ['today_bytes', 'day_bytes', 'daily_bytes', 'traffic_today_bytes', 'traffic_day_bytes', 'traffic_daily_bytes', 'traffic_24h_bytes', 'daily_traffic_bytes'], ['today_gb', 'day_gb', 'daily_gb', 'traffic_today_gb', 'traffic_day_gb', 'traffic_daily_gb', 'traffic_24h_gb', 'daily_traffic_gb'], ['today_mb', 'day_mb', 'daily_mb', 'traffic_today_mb', 'traffic_day_mb', 'traffic_daily_mb', 'traffic_24h_mb', 'daily_traffic_mb']) ?? 0,
            'week_bytes' => $this->trafficBytes($source, ['week_bytes', 'last_7d_bytes', 'traffic_7d_bytes', 'traffic_week_bytes', 'traffic_7_days_bytes'], ['week_gb', 'last_7d_gb', 'traffic_7d_gb', 'traffic_week_gb', 'traffic_7_days_gb'], ['week_mb', 'last_7d_mb', 'traffic_7d_mb', 'traffic_week_mb', 'traffic_7_days_mb']) ?? 0,
            'month_bytes' => $this->trafficBytes($source, ['month_bytes', 'last_30d_bytes', 'traffic_30d_bytes', 'traffic_month_bytes', 'traffic_30_days_bytes'], ['month_gb', 'last_30d_gb', 'traffic_30d_gb', 'traffic_month_gb', 'traffic_30_days_gb'], ['month_mb', 'last_30d_mb', 'traffic_30d_mb', 'traffic_month_mb', 'traffic_30_days_mb']) ?? 0,
            'upload_bytes' => $uploadBytes,
            'download_bytes' => $downloadBytes,
            'limit_bytes' => $limitBytes,
            'used_percent' => $usedPercent,
            'avg_load_percent' => $avgLoad,
            'peak_load_percent' => $peakLoad,
            'active_sessions' => $this->firstNumeric($source, ['active_sessions', 'sessions_active', 'online_users'], 0),
            'snapshots' => $this->firstNumeric($source, ['snapshots', 'snapshots_count', 'traffic_snapshots'], 0),
            'updated_at' => Arr::get($source, 'updated_at') ?? Arr::get($source, 'generated_at') ?? Arr::get($source, 'last_snapshot_at'),
            'nodes' => $nodes,
        ];
    }

    private function trafficBytes(array $source, array $byteKeys, array $gbKeys = [], array $mbKeys = []): ?float
    {
        foreach ($byteKeys as $key) {
            $value = Arr::get($source, $key);
            if (is_numeric($value)) {
                return max(0, (float) $value);
            }
        }

        foreach ($gbKeys as $key) {
            $value = Arr::get($source, $key);
            if (is_numeric($value)) {
                return $this->gbToBytes((float) $value);
            }
        }

        foreach ($mbKeys as $key) {
            $value = Arr::get($source, $key);
            if (is_numeric($value)) {
                return max(0, (float) $value) * 1024 * 1024;
            }
        }

        return null;
    }

    private function gbToBytes(float $gb): float
    {
        return max(0, $gb) * 1024 * 1024 * 1024;
    }

    private function refreshCoreAdminSnapshots(bool $syncUsers = true, bool $syncOrders = true): void
    {
        $scope = ($syncUsers ? 'users' : '').($syncOrders ? '-orders' : '');
        $throttleKey = 'admin-core-refresh-throttle:'.$scope;

        if (Cache::has($throttleKey)) {
            return;
        }

        try {
            $refreshed = Cache::lock('admin-core-refresh', 45)->get(function () use ($syncUsers, $syncOrders): bool {
                $usersExitCode = $syncUsers ? Artisan::call('core:sync') : 0;
                $ordersExitCode = $syncOrders
                    ? Artisan::call('orders:sync', [
                        '--limit' => 500,
                        '--all' => true,
                        '--no-alerts' => true,
                    ])
                    : 0;

                if ($usersExitCode === 0 && $ordersExitCode === 0) {
                    Cache::put('admin-core-refresh-last-success', now()->toIso8601String(), now()->addDay());
                    Cache::forget('admin-core-refresh-last-error');
                    return true;
                }

                Cache::put(
                    'admin-core-refresh-last-error',
                    "core:sync={$usersExitCode}; orders:sync={$ordersExitCode}",
                    now()->addHour(),
                );

                return false;
            });

            if ($refreshed) {
                Cache::put($throttleKey, true, now()->addSeconds(20));
            }
        } catch (\Throwable $e) {
            Cache::put('admin-core-refresh-last-error', $e->getMessage(), now()->addHour());
            Log::warning('admin core snapshot refresh failed', ['error' => $e->getMessage()]);
        }
    }

    private function syncLatestSubscriptionsFromCore(): void
    {
        $coreUsers = $this->core->adminUsers();
        if (! is_array($coreUsers)) {
            return;
        }

        $items = array_is_list($coreUsers)
            ? $coreUsers
            : (Arr::get($coreUsers, 'users') ?? Arr::get($coreUsers, 'data') ?? Arr::get($coreUsers, 'items') ?? []);

        if (! is_array($items)) {
            return;
        }

        foreach (array_slice($items, 0, 200) as $coreUser) {
            if (! is_array($coreUser)) {
                continue;
            }

            $user = $this->localUserFromCorePayload($coreUser);
            if (! $user) {
                continue;
            }

            $sub = Arr::get($coreUser, 'subscription');
            $sub = is_array($sub) ? $sub : $coreUser;
            $isActive = (bool) (Arr::get($sub, 'is_active') ?? Arr::get($coreUser, 'is_active') ?? false);
            $isUnlimited = (bool) (Arr::get($sub, 'is_unlimited') ?? Arr::get($coreUser, 'is_unlimited') ?? false);
            $expiresAt = Arr::get($sub, 'expires_at') ?? Arr::get($sub, 'ends_at') ?? Arr::get($coreUser, 'expires_at');

            if (! $isActive && ! $expiresAt && ! $isUnlimited) {
                continue;
            }

            $status = (string) (Arr::get($sub, 'status') ?? ($isActive ? 'active' : 'inactive'));
            $planId = $this->resolveCorePlanId(array_merge($coreUser, $sub));
            $nodeId = Arr::get($sub, 'node_id') ?? Arr::get($coreUser, 'node_id');

            $payload = [
                'telegram' => (string) ($user->telegram_id ?? ''),
                'status' => in_array($status, ['active', 'trial', 'inactive', 'expiring_soon'], true) ? $status : ($isActive ? 'active' : 'inactive'),
                'ends_at' => $isUnlimited ? null : $expiresAt,
                'last_sync_at' => now(),
            ];

            if ($planId) {
                $payload['plan_id'] = $planId;
            }

            if (is_numeric($nodeId)) {
                $payload['node_id'] = (int) $nodeId;
            }

            $trafficUsed = $this->trafficBytes($sub, ['traffic_used_bytes', 'traffic_bytes', 'used_bytes', 'total_bytes'], ['traffic_used_gb', 'traffic_gb', 'used_gb', 'total_gb'], ['traffic_used_mb', 'traffic_mb', 'used_mb', 'total_mb']);
            $trafficLimit = $this->trafficBytes($sub, ['traffic_limit_bytes', 'limit_bytes'], ['traffic_limit_gb', 'limit_gb'], ['traffic_limit_mb', 'limit_mb']);

            if ($trafficUsed !== null) {
                $payload['traffic_used_gb'] = round($trafficUsed / 1024 / 1024 / 1024, 3);
            }

            if ($trafficLimit !== null) {
                $payload['traffic_limit_gb'] = round($trafficLimit / 1024 / 1024 / 1024, 3);
            }

            Subscription::query()->updateOrCreate(
                ['user_id' => $user->id],
                $payload,
            );
        }
    }

    private function localUserFromCorePayload(array $coreUser): ?User
    {
        $telegramId = Arr::get($coreUser, 'telegram_id');
        $coreUserId = Arr::get($coreUser, 'id') ?? Arr::get($coreUser, 'core_user_id');
        $token = Arr::get($coreUser, 'token');

        if (! $telegramId && ! $coreUserId && ! $token) {
            return null;
        }

        return User::query()
            ->when($telegramId, fn ($query) => $query->orWhere('telegram_id', $telegramId))
            ->when($coreUserId && Schema::hasColumn('users', 'core_user_id'), fn ($query) => $query->orWhere('core_user_id', $coreUserId))
            ->when($token, fn ($query) => $query->orWhere('token', $token))
            ->first();
    }

    private function resolveCorePlanId(array $payload): ?int
    {
        $duration = (int) (
            Arr::get($payload, 'duration_months')
            ?? Arr::get($payload, 'months')
            ?? Arr::get($payload, 'period_months')
            ?? Arr::get($payload, 'plan_months')
            ?? 0
        );

        if ($duration > 0) {
            $planId = Plan::query()->where('duration_months', $duration)->value('id');
            if ($planId) {
                return (int) $planId;
            }
        }

        $amount = Arr::get($payload, 'amount')
            ?? Arr::get($payload, 'price_rub')
            ?? Arr::get($payload, 'price')
            ?? Arr::get($payload, 'paid_amount');

        if (is_numeric($amount)) {
            $planId = Plan::query()
                ->where('price_rub', (int) round((float) $amount))
                ->value('id');
            if ($planId) {
                return (int) $planId;
            }
        }

        $name = Arr::get($payload, 'plan_name')
            ?? Arr::get($payload, 'tariff')
            ?? Arr::get($payload, 'tariff_name');

        if (is_string($name) && trim($name) !== '') {
            $name = trim($name);
            $planId = Plan::query()
                ->where('name', $name)
                ->orWhere('headline', $name)
                ->value('id');
            if ($planId) {
                return (int) $planId;
            }
        }

        $corePlanId = Arr::get($payload, 'plan_id');
        if (filter_var(env('CORE_PLAN_IDS_ARE_LOCAL', false), FILTER_VALIDATE_BOOL) && is_numeric($corePlanId)) {
            return Plan::query()->whereKey((int) $corePlanId)->value('id');
        }

        return null;
    }

    private function refreshNodeFromCoreResult(Node $node, array $result): void
    {
        $payload = Arr::get($result, 'node') ?? Arr::get($result, 'data') ?? $result;
        if (! is_array($payload)) {
            return;
        }

        $fillable = array_flip($node->getFillable());
        $updates = Arr::only($payload, array_keys($fillable));

        if ($updates !== []) {
            $node->forceFill($updates)->save();
        }
    }

    private function firstNumeric(array $source, array $keys, int|float $fallback): int|float
    {
        foreach ($keys as $key) {
            $value = Arr::get($source, $key);

            if (is_numeric($value)) {
                return $value + 0;
            }
        }

        return $fallback;
    }

    private function shouldSearchExactNumber(string $table, string $field, string $search, bool $isGlobalSearch): bool
    {
        if (! ctype_digit($search)) {
            return false;
        }

        if ($field === 'id' || str_ends_with($field, '_id') || $field === 'telegram_id') {
            return true;
        }

        try {
            $type = Schema::getColumnType($table, $field);
        } catch (\Throwable) {
            $type = null;
        }

        if (in_array($type, ['integer', 'bigint', 'smallint', 'decimal', 'float', 'double'], true)) {
            return true;
        }

        return ! $isGlobalSearch;
    }

    public function index(string $resource, Request $request): View
    {
        if ($resource === 'nodes') {
            $this->monitor->refresh();
        }

        if (in_array($resource, ['users', 'subscriptions'], true)) {
            $this->refreshCoreAdminSnapshots(syncOrders: false);
        } elseif (in_array($resource, ['orders', 'cp_orders'], true)) {
            $this->refreshCoreAdminSnapshots(syncUsers: false);
        }

        $config = $this->resourceConfig($resource);
        $modelClass = $config['model'];
        $model = new $modelClass();
        $table = $model->getTable();
        $query = $modelClass::query();
        $this->applyCoreTruthScope($resource, $query, $table);

        // Smart search
        if ($search = trim((string) $request->query('q'))) {
            $searchField = $request->query('search_field', 'all');
            $searchFields = $config['search_fields'] ?? $config['fields'];

            $query->where(function (Builder $builder) use ($search, $searchFields, $searchField, $table): void {
                $fields = ($searchField === 'all') ? $searchFields : [$searchField];
                $applied = false;
                foreach ($fields as $field) {
                    if (! Schema::hasColumn($table, $field)) {
                        continue;
                    }

                    if ($this->shouldSearchExactNumber($table, $field, $search, $searchField === 'all')) {
                        $builder->orWhere($field, '=', $search);
                        $applied = true;
                        continue;
                    }

                    if (! ctype_digit($search) || $searchField !== 'all') {
                        $builder->orWhere($field, 'like', "%{$search}%");
                        $applied = true;
                    }
                }

                if (! $applied) {
                    foreach ($fields as $field) {
                        if (Schema::hasColumn($table, $field)) {
                            $builder->orWhere($field, 'like', "%{$search}%");
                        }
                    }
                }
            });
        }

        // Sorting
        $sortBy = $request->query('sort', 'id');
        $sortDir = $request->query('dir', 'desc');
        $sortable = array_values(array_unique(array_merge(['id'], $config['fields'], $config['sortable'] ?? [])));
        $sortable = array_values(array_filter($sortable, fn($column) => Schema::hasColumn($table, $column)));
        if (in_array($sortBy, $sortable, true)) {
            $query->orderBy($sortBy, $sortDir === 'asc' ? 'asc' : 'desc');
        } else {
            $query->latest();
        }

        // Eager load relations defined in display_fields
        $relations = [];
        foreach ($config['display_fields'] ?? [] as $df) {
            if (isset($df['relation'])) {
                $relations[] = $df['relation'];
            }
        }
        if ($relations) {
            $query->with($relations);
        }

        if ($resource === 'users') {
            $query->withCount(['browserPushSubscriptions'])
                ->with(['latestSubscription.plan', 'latestSubscription.node'])
                ->withExists([
                    'subscriptions as has_active_subscription' => function ($query): void {
                        $query->whereIn('status', ['active', 'trial', 'expiring_soon'])
                            ->where(function ($query): void {
                                $query->whereNull('ends_at')
                                    ->orWhere('ends_at', '>', now());
                            });
                    },
                ]);
        }

        if ($resource === 'subscriptions') {
            $query->with([
                'user' => fn ($query) => $query->withCount('browserPushSubscriptions'),
                'plan',
                'node',
            ]);
        }

        if ($resource === 'plans') {
            $query->withCount('subscriptions');
        }

        $rows = $query->paginate(15)->withQueryString();
        if ($resource === 'users') {
            $this->attachCoreUserOverviews($rows);
        }
        if ($resource === 'subscriptions') {
            $this->attachCoreSubscriptionOverviews($rows);
        }

        return view('admin.resource-index', [
            'resource' => $resource,
            'config' => $config,
            'rows' => $rows,
            'resources' => self::RESOURCES,
            'serverHealth' => $this->monitor->health(),
            'coreSnapshotAt' => Cache::get('admin-core-refresh-last-success'),
            'coreSnapshotError' => Cache::get('admin-core-refresh-last-error'),
            'subscriptionPlans' => $resource === 'subscriptions'
                ? Plan::query()->orderBy('price_rub')->orderBy('name')->get()
                : collect(),
        ]);
    }

    public function create(string $resource): View
    {
        $config = $this->resourceConfig($resource);
        abort_unless(($config['creatable'] ?? true), 404);

        $row = null;
        if ($resource === 'subscriptions' && request()->query('user_id')) {
            $row = new Subscription(['user_id' => request()->query('user_id')]);
        }

        return view('admin.resource-form', [
            'resource' => $resource,
            'config' => $config,
            'row' => $row,
            'isCreate' => true,
            'resources' => self::RESOURCES,
            'serverHealth' => $this->monitor->health(),
        ]);
    }

    public function show(string $resource, int $id): View
    {
        $config = $this->resourceConfig($resource);
        $modelClass = $config['model'];
        $row = $modelClass::query()->findOrFail($id);
        $coreDevices = null;
        $coreActiveSessions = null;
        $coreTraffic = null;

        if ($resource === 'users' && $row instanceof User) {
            $coreUserId = $this->coreUserId($row);
            $coreDevices = $this->normalizeCoreList($this->core->adminUserDevices($coreUserId), ['devices', 'items', 'data']);
            $coreActiveSessions = $this->normalizeCorePayload($this->core->adminUserActiveSessions($coreUserId), ['sessions', 'data', 'summary']);
            $coreTraffic = $this->normalizeCorePayload($this->core->adminUserTraffic($coreUserId), ['traffic', 'data', 'summary', 'stats']);
        }

        return view('admin.resource-show', [
            'resource' => $resource,
            'config' => $config,
            'row' => $row,
            'resources' => self::RESOURCES,
            'serverHealth' => $this->monitor->health(),
            'coreDevices' => $coreDevices,
            'coreActiveSessions' => $coreActiveSessions,
            'coreTraffic' => $coreTraffic,
        ]);
    }

    public function store(string $resource, Request $request): RedirectResponse
    {
        $config = $this->resourceConfig($resource);
        abort_unless(($config['creatable'] ?? true), 404);
        $modelClass = $config['model'];
        $data = $this->validatedData($request, $config['create_fields'] ?? $config['fields']);
        $data = $this->normalizeResourceData($resource, $data, $config);

        // For users: hash password and generate token/uuid if missing
        if ($modelClass === User::class) {
            $data['password']    = \Illuminate\Support\Facades\Hash::make($data['password'] ?? \Illuminate\Support\Str::random(16));
            $data['token']       = $data['token']       ?? (string) \Illuminate\Support\Str::uuid();
            $data['client_uuid'] = $data['client_uuid'] ?? (string) \Illuminate\Support\Str::uuid();
            $data['trial_used']  = $data['trial_used']  ?? false;
        }

        if ($resource === 'subscriptions') {
            $targetUser = User::query()->find($data['user_id'] ?? null);
            if (! $targetUser || empty($targetUser->telegram_id)) {
                return redirect()
                    ->route('admin.resource.index', $resource)
                    ->with('error', 'Подписку нельзя выдать: у пользователя не привязан Telegram. Core API сейчас требует telegram_id для создания пользователя. Сначала попросите клиента войти/привязать Telegram, затем выдайте подписку.');
            }
        }

        $row = $modelClass::query()->create($data);
        if (! $this->syncResourceToCore($resource, $row)) {
            $row->delete();
            $coreError = $this->core->lastErrorMessage();

            return redirect()
                ->route('admin.resource.index', $resource)
                ->with('error', 'Запись не создана: Core API не принял синхронизацию. Локальная запись откатана.'
                    . ($coreError ? ' Причина: '.$coreError : ''));
        }

        if ($resource === 'nodes') {
            $this->monitor->refresh();
        }

        $this->log('create', $resource, null, $data);

        return redirect()->route('admin.resource.index', $resource)->with('success', 'Запись создана.');
    }

    public function edit(string $resource, int $id): View
    {
        $config = $this->resourceConfig($resource);
        abort_unless(($config['editable'] ?? true), 404);
        $modelClass = $config['model'];
        $row = $modelClass::query()->findOrFail($id);

        return view('admin.resource-form', [
            'resource' => $resource,
            'config' => $config,
            'row' => $row,
            'resources' => self::RESOURCES,
            'serverHealth' => $this->monitor->health(),
        ]);
    }

    public function update(string $resource, int $id, Request $request): RedirectResponse
    {
        $config = $this->resourceConfig($resource);
        abort_unless(($config['editable'] ?? true), 404);
        $modelClass = $config['model'];
        $row = $modelClass::query()->findOrFail($id);
        $before = $row->toArray();
        $data = $this->validatedData($request, $config['fields']);
        $data = $this->normalizeResourceData($resource, $data, $config);
        $row->update($data);
        if (! $this->syncResourceToCore($resource, $row->fresh())) {
            $row->forceFill($before)->save();
            $coreError = $this->core->lastErrorMessage();

            return redirect()
                ->route('admin.resource.index', $resource)
                ->with('error', 'Запись не обновлена: Core API не принял синхронизацию. Изменения откатаны.'
                    . ($coreError ? ' Причина: '.$coreError : ''));
        }

        if ($resource === 'nodes') {
            $this->monitor->refresh();
        }

        $this->log('update', $resource, $id, ['before' => $before, 'after' => $row->fresh()->toArray()]);

        return redirect()->route('admin.resource.index', $resource)->with('success', 'Запись обновлена.');
    }

    public function destroy(string $resource, int $id, Request $request): RedirectResponse
    {
        $config = $this->resourceConfig($resource);
        abort_unless(($config['deletable'] ?? true), 405, 'Удаление этой записи должно выполняться через Core API.');
        $modelClass = $config['model'];
        $row = $modelClass::query()->findOrFail($id);
        $this->log('delete', $resource, $id, $row->toArray());
        $this->deleteResourceFromCore($resource, $row);
        $row->delete();

        if ($resource === 'nodes') {
            $this->monitor->refresh();
        }

        $returnTo = $request->input('return_to');
        if (is_string($returnTo) && str_starts_with($returnTo, url('/'))) {
            return redirect()->to($returnTo)->with('success', 'Запись удалена.');
        }

        return redirect()->route('admin.resource.index', $resource)->with('success', 'Запись удалена.');
    }

    private function resourceConfig(string $resource): array
    {
        abort_unless(array_key_exists($resource, self::RESOURCES), 404);

        return self::RESOURCES[$resource];
    }

    private function applyCoreTruthScope(string $resource, Builder $query, string $table): void
    {
        if ($resource === 'users' && Schema::hasColumn($table, 'core_user_id')) {
            $query->whereNotNull('core_user_id');
            return;
        }

        if ($resource === 'subscriptions' && Schema::hasColumn($table, 'last_sync_at')) {
            $query->whereNotNull('last_sync_at');
            return;
        }

        if (in_array($resource, ['orders', 'cp_orders'], true) && Schema::hasColumn($table, 'raw_payload')) {
            $query->whereNotNull('raw_payload');
        }
    }

    private function validatedData(Request $request, array $fields): array
    {
        $rules = [];
        foreach ($fields as $field) {
            $rules[$field] = ['nullable'];
        }

        $data = $request->validate($rules);
        $data = Arr::except($data, ['password', 'remember_token']);

        // Cast boolean fields: checkboxes come as "on"/null, convert to 1/0
        $booleanFields = ['is_highlighted', 'is_active', 'trial_used', 'hidden_on_dashboard'];
        foreach ($booleanFields as $bool) {
            if (in_array($bool, $fields, true)) {
                $data[$bool] = $request->boolean($bool) ? 1 : 0;
            }
        }

        foreach ($data as $key => $value) {
            if ($value === '') {
                $data[$key] = null;
            }
        }

        if (isset($data['code'])) {
            $data['code'] = mb_strtoupper(trim((string) $data['code']));
        }

        return $data;
    }

    private function syncResourceToCore(string $resource, Model $row): bool
    {
        try {
            if ($resource === 'subscriptions' && $row instanceof Subscription) {
                return $this->syncSubscriptionToCore($row);
            }

            if ($resource === 'promo_codes' && $row instanceof PromoCode) {
                $result = $this->core->adminUpsertPromoCode($row);
                if ($result === null) {
                    Log::warning('Admin promo code Core sync failed', ['code' => $row->code]);
                    return false;
                }
            }

            if ($resource === 'nodes' && $row instanceof Node) {
                $result = $row->wasRecentlyCreated
                    ? $this->core->adminCreateNode($row)
                    : $this->core->adminUpdateNode($row);

                if ($result === null) {
                    Log::warning('Admin node Core sync failed', ['node_id' => $row->getKey()]);
                    return false;
                }

                $this->refreshNodeFromCoreResult($row, $result);
            }
        } catch (\Throwable $e) {
            Log::error('Admin Core sync exception', [
                'resource' => $resource,
                'id' => $row->getKey(),
                'error' => $e->getMessage(),
            ]);

            return false;
        }

        return true;
    }

    private function deleteResourceFromCore(string $resource, Model $row): void
    {
        try {
            if ($resource === 'promo_codes' && $row instanceof PromoCode) {
                $this->core->adminDeletePromoCode($row);
            }

            if ($resource === 'nodes' && $row instanceof Node) {
                $this->core->adminDeleteNode($row);
            }
        } catch (\Throwable $e) {
            Log::error('Admin Core delete sync exception', [
                'resource' => $resource,
                'id' => $row->getKey(),
                'error' => $e->getMessage(),
            ]);
        }
    }

    private function syncSubscriptionToCore(Subscription $subscription): bool
    {
        if (! in_array($subscription->status, ['active', 'trial', 'expiring_soon'], true)) {
            Log::warning('Unsupported subscription state change from admin panel', [
                'subscription_id' => $subscription->id,
                'status' => $subscription->status,
            ]);

            return false;
        }

        $user = $subscription->user()->first();
        if (! $user) {
            return false;
        }

        $endsAt = $subscription->ends_at
            ? Carbon::parse($subscription->ends_at)
            : null;

        if ($endsAt && $endsAt->isPast()) {
            return false;
        }

        $result = $this->core->adminUpsertSubscription($subscription);

        if ($result === null) {
            Log::warning('Admin subscription Core sync failed', [
                'subscription_id' => $subscription->id,
                'user_id' => $user->id,
                'core_user_id' => $user->core_user_id,
                'telegram_id' => $user->telegram_id,
                'plan_id' => $subscription->plan_id,
                'starts_at' => $subscription->starts_at,
                'ends_at' => $subscription->ends_at,
                'core_error' => $this->core->lastErrorMessage(),
            ]);

            return false;
        }

        $this->refreshSubscriptionFromCore($subscription, $user);

        return true;
    }

    private function refreshSubscriptionFromCore(Subscription $subscription, User $user): void
    {
        if (! $user->token) {
            return;
        }

        $status = $this->core->getSubStatus($user->token);
        if (! is_array($status) || ! ($status['is_active'] ?? false)) {
            return;
        }

        $isUnlimited = (bool) ($status['is_unlimited'] ?? false);
        $subscription->forceFill([
            'plan_id' => $status['plan_id'] ?? $subscription->plan_id,
            'status' => ($subscription->status === 'trial') ? 'trial' : 'active',
            'ends_at' => $isUnlimited ? null : ($status['expires_at'] ?? $subscription->ends_at),
            'last_sync_at' => now(),
        ])->save();
    }

    private function normalizeResourceData(string $resource, array $data, array $config): array
    {
        if ($resource === 'plans') {
            $data['features'] = $this->normalizePlanFeatures($data['features'] ?? null);
            $data['duration_months'] = max(1, (int) ($data['duration_months'] ?? 1));
            $data['price_rub'] = max(0, (int) ($data['price_rub'] ?? 0));
        }

        if ($resource === 'promo_codes') {
            foreach (['starts_at', 'expires_at'] as $field) {
                if (! empty($data[$field])) {
                    $data[$field] = str_replace('T', ' ', $data[$field]) . ':00';
                }
            }

            $data = Arr::except($data, ['used_count']);
        }

        if (isset($config['persist_fields'])) {
            $data = Arr::only($data, $config['persist_fields']);
        }

        return $data;
    }

    private function normalizePlanFeatures(mixed $value): array
    {
        if (is_array($value)) {
            return array_values(array_filter(array_map(
                static fn ($item) => trim((string) $item),
                $value,
            )));
        }

        $value = trim((string) $value);
        if ($value === '') {
            return [];
        }

        $decoded = json_decode($value, true);
        if (json_last_error() === JSON_ERROR_NONE && is_string($decoded)) {
            $decodedAgain = json_decode($decoded, true);
            if (json_last_error() === JSON_ERROR_NONE) {
                $decoded = $decodedAgain;
            }
        }

        if (is_array($decoded)) {
            return array_values(array_filter(array_map(
                static fn ($item) => trim((string) $item),
                $decoded,
            )));
        }

        return array_values(array_filter(array_map(
            static fn ($item) => trim($item),
            preg_split('/\r\n|\r|\n|,/', $value) ?: [],
        )));
    }

    private function log(string $action, string $resource, ?int $resourceId, array $changes = []): void
    {
        try {
            $adminId = session('admin_id');
            if ($adminId) {
                AdminLog::query()->create([
                    'admin_id'    => $adminId,
                    'action'      => $action,
                    'resource'    => $resource,
                    'resource_id' => $resourceId,
                    'changes'     => $changes,
                    'ip'          => request()->ip(),
                ]);
            }
        } catch (\Throwable) {}
    }

    public function sendNotification(Request $request, int $id): \Illuminate\Http\JsonResponse
    {
        $data = $request->validate([
            'message' => ['required', 'string', 'max:4096'],
            'title'   => ['nullable', 'string', 'max:255'],
        ]);

        $user = User::query()->findOrFail($id);

        \App\Models\Notification::query()->create([
            'title'     => $data['title'] ?? 'Сообщение от администратора',
            'body'      => $data['message'],
            'type'      => 'info',
            'is_global' => false,
            'user_id'   => $user->id,
        ]);

        $this->log('notify', 'users', $id, ['message' => $data['message']]);

        return response()->json(['ok' => true]);
    }

    public function userCoreDevices(User $user): JsonResponse
    {
        $result = $this->core->adminUserDevices($this->coreUserId($user));
        $devices = $this->normalizeCoreList($result, ['devices', 'items', 'data']);

        return response()->json([
            'ok' => $result !== null,
            'devices' => $devices ?? [],
            'error' => $result === null ? $this->core->lastErrorMessage() : null,
        ], $result !== null ? 200 : 502);
    }

    public function userCoreActiveSessions(User $user): JsonResponse
    {
        $result = $this->core->adminUserActiveSessions($this->coreUserId($user));
        $sessions = $this->normalizeCorePayload($result, ['sessions', 'data', 'summary']);

        return response()->json([
            'ok' => $result !== null,
            'sessions' => $sessions,
            'error' => $result === null ? $this->core->lastErrorMessage() : null,
        ], $result !== null ? 200 : 502);
    }

    public function userCoreTraffic(User $user): JsonResponse
    {
        $result = $this->core->adminUserTraffic($this->coreUserId($user));
        $traffic = $this->normalizeCorePayload($result, ['traffic', 'data', 'summary', 'stats']);

        return response()->json([
            'ok' => $result !== null,
            'traffic' => $traffic,
            'error' => $result === null ? $this->core->lastErrorMessage() : null,
        ], $result !== null ? 200 : 502);
    }

    public function deactivateUserDevice(User $user, int $device): JsonResponse
    {
        $result = $this->core->adminDeactivateUserDevice($this->coreUserId($user), $device);
        $this->log('deactivate_device', 'users', $user->id, ['device_id' => $device]);

        return response()->json([
            'ok' => $result !== null,
            'result' => $result,
            'error' => $result === null ? $this->core->lastErrorMessage() : null,
        ], $result !== null ? 200 : 502);
    }

    public function reactivateUserDevice(User $user, int $device): JsonResponse
    {
        $result = $this->core->adminReactivateUserDevice($this->coreUserId($user), $device);
        $this->log('reactivate_device', 'users', $user->id, ['device_id' => $device]);

        return response()->json([
            'ok' => $result !== null,
            'result' => $result,
            'error' => $result === null ? $this->core->lastErrorMessage() : null,
        ], $result !== null ? 200 : 502);
    }

    public function supportAppClient(Request $request): JsonResponse
    {
        $data = $request->validate([
            'support_code' => ['required', 'string', 'max:120'],
        ]);

        $supportCode = trim($data['support_code']);
        $client = $this->core->adminAppClient($supportCode);

        return response()->json([
            'ok' => $client !== null,
            'client' => $client,
            'error' => $client === null ? $this->core->lastErrorMessage() : null,
        ], $client !== null ? 200 : 404);
    }

    public function requestAppClientDiagnostics(string $supportCode): JsonResponse
    {
        $result = $this->core->adminRequestAppClientDiagnostics($supportCode);
        $this->log('request_diagnostics', 'app_clients', null, ['support_code' => $supportCode]);

        return response()->json([
            'ok' => $result !== null,
            'result' => $result,
            'error' => $result === null ? $this->core->lastErrorMessage() : null,
        ], $result !== null ? 200 : 502);
    }

    public function appClientDiagnostics(string $supportCode): JsonResponse
    {
        $diagnostics = $this->core->adminAppClientDiagnostics($supportCode);

        return response()->json([
            'ok' => $diagnostics !== null,
            'diagnostics' => $diagnostics,
            'error' => $diagnostics === null ? $this->core->lastErrorMessage() : null,
        ], $diagnostics !== null ? 200 : 404);
    }

    private function coreUserId(User $user): int
    {
        return $user->core_user_id ? (int) $user->core_user_id : (int) $user->id;
    }

    private function attachCoreUserOverviews(LengthAwarePaginator $rows): void
    {
        $users = $rows->getCollection();
        $overviews = [];
        $missingCoreIds = [];

        foreach ($users as $user) {
            if (! $user instanceof User) {
                continue;
            }

            $coreUserId = $this->coreUserId($user);
            $cacheKey = "admin-user-overview:{$coreUserId}";
            $cached = Cache::get($cacheKey);

            if (is_array($cached)) {
                $overviews[$coreUserId] = $cached;
            } else {
                $missingCoreIds[] = $coreUserId;
            }
        }

        if ($missingCoreIds !== []) {
            foreach ($this->core->adminUserOverviews($missingCoreIds) as $coreUserId => $payload) {
                $normalized = $this->normalizeCoreUserOverview($payload);
                if ($normalized !== null) {
                    Cache::put("admin-user-overview:{$coreUserId}", $normalized, now()->addSeconds(45));
                    $overviews[$coreUserId] = $normalized;
                }
            }
        }

        foreach ($users as $user) {
            if ($user instanceof User) {
                $user->setAttribute('core_overview', $overviews[$this->coreUserId($user)] ?? null);
            }
        }
    }

    private function attachCoreSubscriptionOverviews(LengthAwarePaginator $rows): void
    {
        $subscriptions = $rows->getCollection();
        $overviews = [];
        $missingCoreIds = [];

        foreach ($subscriptions as $subscription) {
            if (! $subscription instanceof Subscription || ! $subscription->user instanceof User) {
                continue;
            }

            $coreUserId = $this->coreUserId($subscription->user);
            $cacheKey = "admin-user-overview:{$coreUserId}";
            $cached = Cache::get($cacheKey);

            if (is_array($cached)) {
                $overviews[$coreUserId] = $cached;
            } else {
                $missingCoreIds[] = $coreUserId;
            }
        }

        if ($missingCoreIds !== []) {
            foreach ($this->core->adminUserOverviews($missingCoreIds) as $coreUserId => $payload) {
                $normalized = $this->normalizeCoreUserOverview($payload);
                if ($normalized !== null) {
                    Cache::put("admin-user-overview:{$coreUserId}", $normalized, now()->addSeconds(45));
                    $overviews[$coreUserId] = $normalized;
                }
            }
        }

        foreach ($subscriptions as $subscription) {
            if ($subscription instanceof Subscription && $subscription->user instanceof User) {
                $subscription->setAttribute('core_overview', $overviews[$this->coreUserId($subscription->user)] ?? null);
            }
        }
    }

    private function normalizeCoreUserOverview(?array $payload): ?array
    {
        if ($payload === null) {
            return null;
        }

        $root = Arr::get($payload, 'data') ?? Arr::get($payload, 'overview') ?? $payload;
        if (! is_array($root)) {
            return null;
        }

        $subscription = Arr::get($root, 'subscription');
        $subscription = is_array($subscription) ? $subscription : $root;

        $status = strtolower((string) (
            Arr::get($subscription, 'status')
            ?? Arr::get($root, 'subscription_status')
            ?? ''
        ));
        $isUnlimited = (bool) (
            Arr::get($subscription, 'is_unlimited')
            ?? Arr::get($root, 'is_unlimited')
            ?? false
        );
        $expiresAt = Arr::get($subscription, 'expires_at')
            ?? Arr::get($subscription, 'ends_at')
            ?? Arr::get($root, 'expires_at')
            ?? Arr::get($root, 'ends_at');
        $explicitActive = Arr::get($subscription, 'is_active');
        if ($explicitActive === null) {
            $explicitActive = Arr::get($root, 'is_active');
        }

        $isActive = $explicitActive !== null
            ? filter_var($explicitActive, FILTER_VALIDATE_BOOL)
            : in_array($status, ['active', 'trial', 'expiring_soon'], true);

        if ($explicitActive === null && ! $isActive && $expiresAt) {
            try {
                $isActive = Carbon::parse($expiresAt)->isFuture();
            } catch (\Throwable) {
                // Keep the status-derived value when Core returned an invalid date.
            }
        }

        $expiredByDate = false;

        if ($isUnlimited) {
            $isActive = true;
        } elseif ($expiresAt) {
            try {
                $expiredByDate = Carbon::parse($expiresAt)->isPast();
                if ($expiredByDate) {
                    $isActive = false;
                }
            } catch (\Throwable) {
                // Keep the Core active flag when Core returned an invalid date.
            }
        }

        if ($status === '') {
            $status = $isActive ? 'active' : 'inactive';
        } elseif ($isActive && ! in_array($status, ['active', 'trial', 'expiring_soon'], true)) {
            $status = 'active';
        } elseif (! $isActive && in_array($status, ['active', 'trial', 'expiring_soon'], true)) {
            $status = $expiredByDate ? 'expired' : 'inactive';
        }

        return [
            'is_active' => $isActive,
            'status' => $status,
            'is_unlimited' => $isUnlimited,
            'expires_at' => $isUnlimited ? null : $expiresAt,
            'starts_at' => Arr::get($subscription, 'starts_at') ?? Arr::get($root, 'starts_at'),
            'plan_name' => Arr::get($subscription, 'plan.name')
                ?? Arr::get($subscription, 'plan_name')
                ?? Arr::get($root, 'plan_name')
                ?? Arr::get($root, 'tariff'),
            'checked_at' => now()->toIso8601String(),
        ];
    }

    private function normalizeCorePayload(?array $payload, array $keys): ?array
    {
        if ($payload === null) {
            return null;
        }

        foreach ($keys as $key) {
            $value = Arr::get($payload, $key);
            if (is_array($value)) {
                return $value;
            }
        }

        return $payload;
    }

    private function normalizeCoreList(?array $payload, array $keys): ?array
    {
        if ($payload === null) {
            return null;
        }

        foreach ($keys as $key) {
            $value = Arr::get($payload, $key);
            if (is_array($value)) {
                return array_values($value);
            }
        }

        return array_is_list($payload) ? $payload : [];
    }
}
