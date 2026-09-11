<?php

namespace App\Services;

use App\Models\Node;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Schema;

/**
 * NodeMonitorService
 *
 * Fetches real-time metrics (status, load, latency, errors) for all nodes.
 *
 * Currently operates in STUB mode — returns data from the local DB.
 * When the external monitoring API is ready, replace the body of
 * fetchFromApi() with the real HTTP call and flip STUB_MODE to false.
 *
     * Core API contract:
     *   GET {core_url}/admin/nodes/health
     *   X-Admin-Key: {CORE_ADMIN_KEY}
 *
 *   Response 200:
 *   [
 *     {
 *       "name":    "NL1",
 *       "status":  "alive",          // "alive" | "dead"
 *       "load":    0.32,             // 0.0 – 1.0
 *       "latency": 31,               // ms
 *       "errors":  0
 *     },
 *     ...
 *   ]
 */
class NodeMonitorService
{
    /** Flip to false once the real monitoring API is available */
    private const STUB_MODE = false;

    /** Cache TTL in seconds */
    private const CACHE_TTL = 30;

    private const CACHE_KEY = 'node_health_data';
    private const HIDDEN_CACHE_KEY = 'node_health_hidden_names';

    /**
     * Returns health data for all nodes.
     * Result is cached for CACHE_TTL seconds to avoid hammering the API.
     *
     * @return array{
     *   alive_nodes: int,
     *   total_nodes: int,
     *   avg_load_percent: float,
     *   nodes: array<int, array{name: string, status: string, load_percent: float, latency: int|null, errors: int}>
     * }
     */
    public function health(): array
    {
        return Cache::remember(self::CACHE_KEY, self::CACHE_TTL, function (): array {
            $metrics = self::STUB_MODE
                ? $this->fetchFromDb()
                : $this->fetchFromApi();

            return $this->buildSummary($metrics);
        });
    }

    /**
     * Force-refresh the cache (call after node config changes).
     */
    public function refresh(): array
    {
        Cache::forget(self::CACHE_KEY);
        Cache::forget(self::HIDDEN_CACHE_KEY);
        return $this->health();
    }

    // ──────────────────────────────────────────────────────────────
    // STUB: reads last-known values from the local DB
    // ──────────────────────────────────────────────────────────────
    private function fetchFromDb(): Collection
    {
        $query = Node::query()
            ->where('is_active', true)
            ->select($this->availableNodeColumns([
                'name', 'ip', 'country', 'city', 'lat', 'lng', 'status',
                'load', 'latency', 'errors', 'hidden_on_dashboard',
            ]));

        if (Schema::hasColumn('nodes', 'hidden_on_dashboard')) {
            $query->where('hidden_on_dashboard', false);
        }

        return $query->get()
            ->map(fn (Node $n) => $this->normalizeNodeMetric([
                'name'    => $n->name,
                'ip'      => $n->ip ?? '',
                'country' => $n->country ?? null,
                'city'    => $n->city ?? null,
                'lat'     => $n->lat ?? null,
                'lng'     => $n->lng ?? null,
                'status'  => $n->status ?? 'dead',
                'load'    => (float) ($n->load ?? 0),
                'latency' => $n->latency ? (int) round((float) $n->latency) : null,
                'errors'  => (int) ($n->errors ?? 0),
            ]));
    }

    // ──────────────────────────────────────────────────────────────
    // REAL: replace with actual monitoring API call
    // ──────────────────────────────────────────────────────────────
    private function fetchFromApi(): Collection
    {
        try {
            $request = Http::withHeaders(['X-Admin-Key' => config('services.core.admin_key')])
                ->timeout(5);

            foreach (['/admin/nodes/health', '/admin/nodes'] as $path) {
                $response = $request->get(rtrim((string) config('services.core.url'), '/') . $path);

                if (! $response->successful()) {
                    continue;
                }

                $json = $response->json();
                $items = is_array($json)
                    ? ($json['nodes'] ?? $json['data'] ?? $json['items'] ?? $json)
                    : [];

                if (! is_array($items)) {
                    continue;
                }

                $data = collect($items)->map(fn (array $item) => [
                        'name'    => $item['name']    ?? 'unknown',
                        'ip'      => $item['ip']      ?? '',
                        'port'    => $item['port']    ?? 443,
                        'api_port' => $item['api_port'] ?? 8443,
                        'api_secret' => $item['api_secret'] ?? $item['pubkey'] ?? '',
                        'status'  => $item['status']  ?? 'dead',
                        'load'    => $this->normalizeApiLoad($item['load'] ?? $item['load_percent'] ?? 0),
                        'latency' => isset($item['latency']) ? (int) round((float) $item['latency']) : null,
                        'errors'  => (int) ($item['errors'] ?? 0),
                        'is_active' => (bool) ($item['is_active'] ?? true),
                        'country' => $item['country'] ?? null,
                        'city' => $item['city'] ?? null,
                        'lat' => $item['lat'] ?? $item['latitude'] ?? null,
                        'lng' => $item['lng'] ?? $item['lon'] ?? $item['longitude'] ?? null,
                        'hidden_on_dashboard' => (bool) ($item['hidden_on_dashboard'] ?? false),
                    ]);

                $this->syncLocalNodes($data);

                return $this->withoutHiddenDashboardNodes($data)
                    ->map(fn (array $node) => $this->normalizeNodeMetric($node));
            }
        } catch (\Throwable $e) {
            Log::warning('NodeMonitorService: API unreachable — falling back to DB', [
                'error' => $e->getMessage(),
            ]);
        }

        return $this->fetchFromDb();
    }

    private function normalizeApiLoad(mixed $value): float
    {
        if (! is_numeric($value)) {
            return 0.0;
        }

        $load = (float) $value;

        return $load > 1 ? $load / 100 : $load;
    }

    private function buildSummary(Collection $metrics): array
    {
        $metrics = $this->withoutHiddenDashboardNodes($metrics);

        $nodes = $metrics->map(fn (array $m) => [
            'name'         => $m['name'],
            'ip'           => $m['ip'] ?? '',
            'country'      => $m['country'] ?? null,
            'city'         => $m['city'] ?? null,
            'lat'          => isset($m['lat']) ? (float) $m['lat'] : null,
            'lng'          => isset($m['lng']) ? (float) $m['lng'] : null,
            'status'       => $m['status'],
            'load_percent' => round($m['load'] * 100, 1),
            'latency'      => $m['latency'],
            'errors'       => $m['errors'],
        ])->values()->all();

        $alive = collect($nodes)->where('status', 'alive')->count();
        $total = count($nodes);
        $avgLoad = $total
            ? round(collect($nodes)->avg('load_percent'), 1)
            : 0;

        return [
            'alive_nodes'      => $alive,
            'total_nodes'      => $total,
            'avg_load_percent' => $avgLoad,
            'nodes'            => $nodes,
        ];
    }

    private function syncLocalNodes(Collection $nodes): void
    {
        if (! Schema::hasTable('nodes')) {
            return;
        }

        $columns = collect(Schema::getColumnListing('nodes'))->flip();

        $nodes->each(function (array $node) use ($columns): void {
            if (empty($node['name'])) {
                return;
            }

            $payload = [
                'ip' => $node['ip'] ?? '',
                'country' => $node['country'] ?? null,
                'city' => $node['city'] ?? null,
                'lat' => $node['lat'] ?? null,
                'lng' => $node['lng'] ?? null,
                'port' => $node['port'] ?? 443,
                'api_port' => $node['api_port'] ?? 8443,
                'api_secret' => $node['api_secret'] ?? '',
                'status' => $node['status'] ?? 'unknown',
                'latency' => $node['latency'] ?? null,
                'load' => $node['load'] ?? 0,
                'errors' => $node['errors'] ?? 0,
                'is_active' => $node['is_active'] ?? true,
            ];

            $payload = array_intersect_key($payload, $columns->all());

            Node::query()->updateOrCreate(
                ['name' => $node['name']],
                $payload,
            );
        });
    }

    private function availableNodeColumns(array $columns): array
    {
        $available = collect(Schema::getColumnListing('nodes'))->flip();

        return array_values(array_filter($columns, fn (string $column) => isset($available[$column])));
    }

    private function withoutHiddenDashboardNodes(Collection $nodes): Collection
    {
        if (! Schema::hasTable('nodes') || ! Schema::hasColumn('nodes', 'hidden_on_dashboard')) {
            return $nodes;
        }

        $hiddenNames = Cache::remember(self::HIDDEN_CACHE_KEY, self::CACHE_TTL, function () {
            return Node::query()
                ->where('hidden_on_dashboard', true)
                ->pluck('name')
                ->map(fn (string $name) => mb_strtolower($name))
                ->flip()
                ->all();
        });

        return $nodes->reject(function (array $node) use ($hiddenNames): bool {
            $name = mb_strtolower((string) ($node['name'] ?? ''));
            return $name !== '' && isset($hiddenNames[$name]);
        })->values();
    }

    private function normalizeNodeMetric(array $node): array
    {
        $geo = $this->inferGeo($node);

        return array_merge($node, [
            'country' => $node['country'] ?? $geo['country'],
            'city' => $node['city'] ?? $geo['city'],
            'lat' => $node['lat'] ?? $geo['lat'],
            'lng' => $node['lng'] ?? $geo['lng'],
        ]);
    }

    private function inferGeo(array $node): array
    {
        $tokens = $this->geoTokens($node);

        if ($tokens->intersect(['de', 'ger', 'germany', 'deu', 'fra', 'frankfurt'])->isNotEmpty()) {
            return ['country' => 'Germany', 'city' => 'Frankfurt', 'lat' => 50.1109, 'lng' => 8.6821];
        }

        if ($tokens->intersect(['nl', 'netherlands', 'ams', 'amsterdam'])->isNotEmpty()) {
            return ['country' => 'Netherlands', 'city' => 'Amsterdam', 'lat' => 52.37, 'lng' => 4.90];
        }

        if ($tokens->intersect(['uk', 'gb', 'london', 'united', 'kingdom'])->isNotEmpty()) {
            return ['country' => 'United Kingdom', 'city' => 'London', 'lat' => 51.51, 'lng' => -0.13];
        }

        if ($tokens->intersect(['fi', 'fin', 'finland', 'helsinki'])->isNotEmpty()) {
            return ['country' => 'Finland', 'city' => 'Helsinki', 'lat' => 60.17, 'lng' => 24.94];
        }

        if ($tokens->intersect(['ru', 'msk', 'moscow', 'russia', 'москва', 'россия'])->isNotEmpty()) {
            return ['country' => 'Russia', 'city' => 'Moscow', 'lat' => 55.76, 'lng' => 37.62];
        }

        if ($tokens->intersect(['tr', 'turkey', 'istanbul'])->isNotEmpty()) {
            return ['country' => 'Turkey', 'city' => 'Istanbul', 'lat' => 41.01, 'lng' => 28.97];
        }

        return ['country' => null, 'city' => null, 'lat' => null, 'lng' => null];
    }

    private function geoTokens(array $node): Collection
    {
        $text = collect([
            $node['name'] ?? '',
            $node['ip'] ?? '',
            $node['country'] ?? '',
            $node['city'] ?? '',
        ])->filter()->implode(' ');

        return collect(preg_split('/[^a-zа-яё0-9]+/iu', mb_strtolower($text)) ?: [])
            ->filter()
            ->values();
    }
}
