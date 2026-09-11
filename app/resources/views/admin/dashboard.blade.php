@extends('admin.layout')

@section('title', 'Dashboard')
@section('body_class', 'adm-page-dashboard')

@section('content')

<div class="adm-dashboard">
{{-- Page header --}}
<div style="margin-bottom:20px">
    <p style="margin:0;font-size:.72rem;color:var(--muted);letter-spacing:.1em;text-transform:uppercase">Auralith Admin</p>
    <h2 style="margin:4px 0 0;font-family:'Montserrat',sans-serif;font-size:1.5rem">Dashboard</h2>
</div>

{{-- Stat cards --}}
@php
$revenueLabels = ['week' => 'неделя', 'month' => 'месяц', 'year' => 'год', 'all' => 'всё время'];
$statCards = [
    [
        'label' => 'Пользователи',
        'value' => $stats['users'],
        'color' => '#4f7eb5',
        'bg'    => 'rgba(79,126,181,.12)',
        'link'  => route('admin.resource.index', 'users'),
        'icon'  => '<path d="M17 21v-2a4 4 0 00-4-4H5a4 4 0 00-4 4v2" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"/><circle cx="9" cy="7" r="4" stroke="currentColor" stroke-width="1.7"/>',
    ],
    [
        'label' => 'Активных подписок',
        'value' => $stats['active_subscriptions'],
        'color' => '#4ade80',
        'bg'    => 'rgba(74,222,128,.1)',
        'link'  => route('admin.resource.index', 'subscriptions'),
        'icon'  => '<path d="M12 2l3.09 6.26L22 9.27l-5 4.87 1.18 6.88L12 17.77l-6.18 3.25L7 14.14 2 9.27l6.91-1.01L12 2z" stroke="currentColor" stroke-width="1.7" stroke-linejoin="round"/>',
    ],
    [
        'label' => 'Заказов',
        'value' => $stats['orders'],
        'color' => '#fbbf24',
        'bg'    => 'rgba(251,191,36,.1)',
        'link'  => route('admin.resource.index', 'orders'),
        'icon'  => '<rect x="2" y="5" width="20" height="14" rx="2" stroke="currentColor" stroke-width="1.7"/><path d="M2 10h20" stroke="currentColor" stroke-width="1.7"/>',
    ],
    [
        'label' => 'Выручка (' . ($revenueLabels[$revenuePeriod] ?? 'месяц') . ')',
        'value' => '₽' . number_format($stats['revenue'], 0, '.', ','),
        'color' => '#a78bfa',
        'bg'    => 'rgba(167,139,250,.1)',
        'link'  => null,
        'icon'  => '<circle cx="12" cy="12" r="9" stroke="currentColor" stroke-width="1.7"/><path d="M9 9h4.5a1.5 1.5 0 010 3H9m0 0h4.5a1.5 1.5 0 010 3H9m0-6v6m3-9v1m0 8v1" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"/>',
        'revenue_filter' => true,
    ],
    [
        'label' => 'Нод онлайн',
        'value' => $stats['nodes_alive'] . '/' . $stats['nodes_total'],
        'color' => '#38bdf8',
        'bg'    => 'rgba(56,189,248,.1)',
        'link'  => route('admin.resource.index', 'nodes'),
        'icon'  => '<circle cx="12" cy="12" r="3" stroke="currentColor" stroke-width="1.7"/><path d="M12 2v3m0 14v3M2 12h3m14 0h3m-3.5-7.5-2.1 2.1M6.6 17.4l-2.1 2.1m0-13.1 2.1 2.1m8.7 8.7 2.1 2.1" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"/>',
    ],
];
@endphp

<div id="stat-grid">
    @foreach($statCards as $sc)
    @if($sc['link'])
    <a href="{{ $sc['link'] }}" class="stat-card stat-card--link">
    @else
    <div class="stat-card">
    @endif
        <div class="stat-card__icon" style="background:{{ $sc['bg'] }}">
            <svg viewBox="0 0 24 24" fill="none" width="17" height="17" style="color:{{ $sc['color'] }}">
                {!! $sc['icon'] !!}
            </svg>
        </div>
        <div class="stat-card__label">{{ $sc['label'] }}</div>
        <div class="stat-card__value" style="color:{{ $sc['color'] }}">{{ $sc['value'] }}</div>
        @if($sc['revenue_filter'] ?? false)
            <div class="adm-revenue-filter">
                @foreach(['week' => 'Нед', 'month' => 'Мес', 'year' => 'Год', 'all' => 'Всё'] as $period => $label)
                    <a href="{{ request()->fullUrlWithQuery(['revenue_period' => $period]) }}" class="{{ $revenuePeriod === $period ? 'is-active' : '' }}">{{ $label }}</a>
                @endforeach
            </div>
        @endif
    @if($sc['link'])
    </a>
    @else
    </div>
    @endif
    @endforeach
</div>

{{-- Traffic and load --}}
@php
    $fmtBytes = static function ($bytes): string {
        if ($bytes === null) return '—';
        $bytes = max(0, (float) $bytes);
        $units = ['Б', 'КБ', 'МБ', 'ГБ', 'ТБ', 'ПБ'];
        $power = $bytes > 0 ? min((int) floor(log($bytes, 1024)), count($units) - 1) : 0;
        $value = $power > 0 ? $bytes / (1024 ** $power) : $bytes;
        $precision = $power >= 3 ? 1 : 0;
        return number_format($value, $precision, '.', ' ') . ' ' . $units[$power];
    };
    $fmtTrafficDate = static function ($value): string {
        if (!$value) return '—';
        try {
            return \Carbon\Carbon::parse($value)->format('d.m.Y H:i');
        } catch (\Throwable $e) {
            return (string) $value;
        }
    };
    $trafficPct = $trafficSummary['used_percent'];
    $trafficDash = $trafficSummary['total_bytes'] > 0 ? 238 : 0;
    $trafficSource = $trafficSummary['source'] === 'core' ? 'Core live' : 'Local cache';
    $trafficUpdated = $fmtTrafficDate($trafficSummary['updated_at']);
@endphp
<section class="adm-card adm-traffic-card adm-traffic-card--summary">
    <div class="adm-card-head adm-card-head--row">
        <div>
            <h6>Трафик и нагрузка</h6>
            <p>{{ $trafficSource }} · обновлено: {{ $trafficUpdated }}</p>
        </div>
    </div>

    <div class="adm-traffic-meter">
        <div class="adm-traffic-orb">
            <svg viewBox="0 0 120 120" aria-hidden="true">
                <circle cx="60" cy="60" r="50"></circle>
                <circle cx="60" cy="60" r="50" style="--traffic-dash: {{ $trafficDash }}"></circle>
            </svg>
            <div>
                <span>Всего</span>
                <strong>{{ $fmtBytes($trafficSummary['total_bytes']) }}</strong>
            </div>
        </div>
    </div>

    <div class="adm-traffic-kpis">
        <div>
            <span>Трафик за сутки</span>
            <strong>{{ $fmtBytes($trafficSummary['today_bytes']) }}</strong>
        </div>
        <div>
            <span>Трафик за 7 дней</span>
            <strong>{{ $fmtBytes($trafficSummary['week_bytes']) }}</strong>
        </div>
        <div>
            <span>Трафик за 30 дней</span>
            <strong>{{ $fmtBytes($trafficSummary['month_bytes']) }}</strong>
        </div>
    </div>
</section>

{{-- Client versions --}}
<div class="adm-card adm-release-card" data-release-card>
    <div class="adm-card-head adm-card-head--row">
        <div>
            <h6>Версии клиента</h6>
            <p>Актуальная, предрелизная и тестовая версии для Windows/Android клиента.</p>
        </div>
        @if(! $clientReleases->isEmpty())
            <button type="button" class="adm-btn adm-btn-ghost adm-btn-sm adm-release-toggle-btn" data-release-toggle>
                Управлять версиями
            </button>
        @endif
    </div>

    @if($clientReleases->isEmpty())
        <p class="adm-empty-state">Таблица версий ещё не создана. Запустите миграции, чтобы включить управление релизами.</p>
    @else
        <div class="adm-release-summary">
            @foreach($clientReleaseChannels as $channel => $label)
                @php
                    $release = $clientReleases->firstWhere('channel', $channel);
                    $accentClass = match ($channel) {
                        'stable' => 'is-stable',
                        'prerelease' => 'is-prerelease',
                        default => 'is-test',
                    };
                @endphp
                <div class="adm-release-chip {{ $accentClass }}">
                    <span>{{ $label }}</span>
                    <strong>{{ $release?->version ?: 'Не указана' }}</strong>
                    @if(! ($release?->is_enabled ?? true))
                        <em>выкл</em>
                    @endif
                </div>
            @endforeach
        </div>

        <form method="POST" action="{{ route('admin.client-releases.update') }}" class="adm-release-form" data-release-form hidden>
            @csrf
            @method('PUT')

            <div class="adm-release-grid">
                @foreach($clientReleaseChannels as $channel => $label)
                    @php
                        $release = $clientReleases->firstWhere('channel', $channel);
                        $accentClass = match ($channel) {
                            'stable' => 'is-stable',
                            'prerelease' => 'is-prerelease',
                            default => 'is-test',
                        };
                    @endphp
                    <section class="adm-release-item {{ $accentClass }}">
                        <div class="adm-release-top">
                            <div>
                                <span>{{ $label }}</span>
                                <strong>{{ $release?->version ?: 'Не указана' }}</strong>
                            </div>
                            <label class="adm-release-toggle">
                                <input type="checkbox" name="releases[{{ $channel }}][is_enabled]" value="1" @checked($release?->is_enabled ?? true)>
                                <span>Вкл</span>
                            </label>
                        </div>

                        <label>
                            Версия
                            <input type="text" name="releases[{{ $channel }}][version]" class="adm-input" value="{{ old("releases.{$channel}.version", $release?->version) }}" placeholder="Например: 1.4.0">
                        </label>
                        <label>
                            Путь загрузки
                            <input type="text" name="releases[{{ $channel }}][download_path]" class="adm-input" value="{{ old("releases.{$channel}.download_path", $release?->download_path) }}" placeholder="/downloads/auralith-windows.exe">
                        </label>
                        <label>
                            latest.json
                            <input type="text" name="releases[{{ $channel }}][latest_json_path]" class="adm-input" value="{{ old("releases.{$channel}.latest_json_path", $release?->latest_json_path) }}" placeholder="/downloads/latest.json">
                        </label>
                        <label>
                            Заметка
                            <textarea name="releases[{{ $channel }}][notes]" class="adm-input" rows="2" placeholder="Коротко: что изменилось или для кого канал">{{ old("releases.{$channel}.notes", $release?->notes) }}</textarea>
                        </label>
                    </section>
                @endforeach
            </div>

            <div class="adm-release-actions">
                <button type="submit" class="adm-btn">Сохранить версии</button>
            </div>
        </form>
    @endif
</div>

{{-- Middle row: Server Network + Orders by status --}}
<div id="mid-row">

    {{-- Server Network --}}
    <div class="adm-card">
        <div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:4px">
            <h6 style="margin:0">Server Network</h6>
            <div class="vt-bar">
                <button class="vt-btn active" id="btn-map" title="Карта" onclick="admSwitchView('map')">
                    <svg viewBox="0 0 20 20" fill="none" width="14" height="14">
                        <path d="M1 4l6-2 6 2 6-2v14l-6 2-6-2-6 2V4z" stroke="currentColor" stroke-width="1.5" stroke-linejoin="round"/>
                        <path d="M7 2v14M13 4v14" stroke="currentColor" stroke-width="1.5"/>
                    </svg>
                </button>
                <button class="vt-btn" id="btn-list" title="Список" onclick="admSwitchView('list')">
                    <svg viewBox="0 0 20 20" fill="none" width="14" height="14">
                        <path d="M4 5h12M4 10h12M4 15h12" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/>
                    </svg>
                </button>
            </div>
        </div>

        {{-- MAP VIEW --}}
        <div id="adm-view-map">
            <div id="node-map"></div>
        </div>

        {{-- LIST VIEW --}}
        <div id="adm-view-list" style="display:none;margin-top:12px">
            @php
            // Resolve node data by IP prefix from Core API
            $geoMeta = [
                'NL' => ['label' => 'Netherlands — Amsterdam', 'flag' => '🇳🇱', 'lat' => 52.37, 'lng' => 4.90],
                'GB' => ['label' => 'United Kingdom — London', 'flag' => '🇬🇧', 'lat' => 51.51, 'lng' => -0.13],
                'DE' => ['label' => 'Germany — Frankfurt', 'flag' => '🇩🇪', 'lat' => 50.1109, 'lng' => 8.6821],
            ];
            $nodeMap = [];
            foreach ($serverHealth['nodes'] as $n) {
                $ip = strtolower($n['ip'] ?? '');
                $tokens = collect(preg_split('/[^a-z0-9а-яё]+/iu', strtolower(($n['name'] ?? '').' '.($n['ip'] ?? '').' '.($n['country'] ?? '').' '.($n['city'] ?? ''))) ?: [])->filter();
                if (str_starts_with($ip, 'nl')) {
                    $nodeMap['NL'] = $n;
                } elseif ($tokens->intersect(['de', 'ger', 'germany', 'deu', 'fra', 'frankfurt'])->isNotEmpty()) {
                    $nodeMap['DE'] = $n;
                } elseif (str_starts_with($ip, 'uk') || str_starts_with($ip, 'gb')) {
                    $nodeMap['GB'] = $n;
                } else {
                    $name = mb_strtolower($n['name'] ?? '');
                    $city = mb_strtolower($n['city'] ?? '');
                    $country = mb_strtolower($n['country'] ?? '');
                    $key = 'NODE_' . ($n['id'] ?? count($nodeMap) + 1);

                    $geoMeta[$key] = [
                        'label' => $n['name'] ?? 'Node',
                        'flag' => strtoupper(substr(preg_replace('/[^a-z0-9]/i', '', $n['country'] ?? $n['name'] ?? 'N'), 0, 3)) ?: 'N',
                        'lat' => $n['lat'] ?? 50 + count($nodeMap) * 2,
                        'lng' => $n['lng'] ?? 10 + count($nodeMap) * 6,
                    ];

                    if (
                        str_contains($ip, 'ru') ||
                        str_contains($ip, 'msk') ||
                        str_contains($name, 'moscow') ||
                        str_contains($name, 'москва') ||
                        str_contains($city, 'moscow') ||
                        str_contains($city, 'москва') ||
                        str_contains($country, 'russia') ||
                        str_contains($country, 'россия')
                    ) {
                        $geoMeta[$key]['flag'] = 'RU';
                        $geoMeta[$key]['lat'] = $n['lat'] ?? 55.76;
                        $geoMeta[$key]['lng'] = $n['lng'] ?? 37.62;
                    }

                    $nodeMap[$key] = $n;
                }
            }
            // Build Leaflet marker data
            $mapNodeData = [];
            foreach ($geoMeta as $code => $geo) {
                $mapNodeData[] = [
                    'code'  => $code,
                    'lat'   => $geo['lat'],
                    'lng'   => $geo['lng'],
                    'label' => $geo['label'],
                    'node'  => $nodeMap[$code] ?? null,
                ];
            }
            @endphp

            @foreach($geoMeta as $code => $geo)
                @php
                    $nd    = $nodeMap[$code] ?? null;
                    $alive = $nd ? ($nd['status'] === 'alive') : false;
                    $load  = $nd ? $nd['load_percent'] : 0;
                    $lat   = $nd ? ($nd['latency'] ?? '—') : '—';
                @endphp
                <div class="node-row">
                    <span class="node-dot {{ $alive ? 'alive' : 'dead' }}"></span>
                    <span class="node-flag">{{ $geo['flag'] }}</span>
                    <span class="node-name">{{ $nd['name'] ?? $geo['label'] }}</span>
                    <span class="node-meta">{{ $load }}% · {{ $lat }}ms</span>
                    <div class="load-bar">
                        <div class="load-fill" style="width:{{ $load }}%;background:{{ $alive ? 'var(--green)' : 'var(--red)' }}"></div>
                    </div>
                    <span class="pill {{ $alive ? 'pill-active' : 'pill-inactive' }}" style="font-size:.68rem">
                        {{ $alive ? 'ONLINE' : 'OFFLINE' }}
                    </span>
                </div>
            @endforeach
        </div>
    </div>

    {{-- Orders by status --}}
    <div class="adm-card">
        <h6>Orders by status</h6>
        <div style="position:relative;height:200px;display:flex;align-items:center;justify-content:center">
            <canvas id="ordersStatusChart"></canvas>
        </div>
        @php
            $statusMap    = $ordersByStatus->toArray();
            $statusTotal  = max(array_sum($statusMap), 1);
            $statusColors = ['paid' => '#4ade80', 'pending' => '#fbbf24', 'cancelled' => '#f87171', 'failed' => '#f87171'];
        @endphp
        <div style="margin-top:14px;display:flex;flex-direction:column;gap:8px">
            @foreach($statusMap as $status => $count)
                @php $pct = round($count / $statusTotal * 100); @endphp
                <div>
                    <div style="display:flex;justify-content:space-between;margin-bottom:4px">
                        <span style="font-size:.78rem;text-transform:uppercase;letter-spacing:.06em">{{ $status }}</span>
                        <span style="font-size:.78rem;color:var(--muted)">{{ $count }} ({{ $pct }}%)</span>
                    </div>
                    <div class="prog-track">
                        <div class="prog-fill" style="width:{{ $pct }}%;background:{{ $statusColors[$status] ?? 'var(--accent)' }}"></div>
                    </div>
                </div>
            @endforeach
            @if(empty($statusMap))
                <p style="color:var(--muted);font-size:.85rem;text-align:center">Нет данных</p>
            @endif
        </div>
    </div>
</div>

{{-- Bottom row: Latest orders and subscriptions --}}
@php
function fmtDate($val): string {
    if (!$val) return '—';
    $months = ['01'=>'янв','02'=>'фев','03'=>'мар','04'=>'апр','05'=>'май','06'=>'июн','07'=>'июл','08'=>'авг','09'=>'сен','10'=>'окт','11'=>'ноя','12'=>'дек'];
    try {
        $dt = \Carbon\Carbon::parse($val);
        return $dt->format('d') . ' ' . ($months[$dt->format('m')] ?? $dt->format('m')) . ' ' . $dt->format('Y') . ' ' . $dt->format('H:i');
    } catch (\Throwable $e) { return (string)$val; }
}
@endphp
<div id="bot-row">

    {{-- Latest subscriptions --}}
    <div class="adm-card adm-dashboard-list-card adm-dashboard-list-card--subscriptions">
        <div class="adm-card-head adm-card-head--row">
            <div>
                <h6>Последние подписки</h6>
                <p>Недавно выданные доступы из актуального снимка Core.</p>
            </div>
            <a href="{{ route('admin.resource.index', 'subscriptions') }}" class="adm-card-link">Все</a>
        </div>
        <div class="adm-dashboard-list">
            @forelse($latestSubscriptions as $sub)
                @php $subUser = optional($sub->user)->name ?: optional($sub->user)->username ?: 'Пользователь'; @endphp
                <a href="{{ route('admin.resource.index', ['resource' => 'subscriptions', 'q' => $sub->user_id]) }}" class="adm-dashboard-list__item">
                    <span class="adm-user-avatar">{{ mb_strtoupper(mb_substr($subUser, 0, 1)) }}</span>
                    <span class="adm-dashboard-list__body">
                        <strong>{{ $subUser }}</strong>
                        <small>{{ optional($sub->plan)->name ?? 'Тариф не определён' }} · {{ fmtDate($sub->starts_at) }}</small>
                    </span>
                    <span class="adm-subscription-badge {{ in_array($sub->status, ['active', 'trial', 'expiring_soon'], true) ? 'is-active' : 'is-expired' }}">
                        {{ strtoupper($sub->status) }}
                    </span>
                </a>
            @empty
                <p class="adm-empty-state">Подписки ещё не синхронизированы.</p>
            @endforelse
        </div>
    </div>

    {{-- Latest orders --}}
    <div class="adm-card adm-dashboard-list-card adm-dashboard-list-card--orders">
        <div class="adm-card-head adm-card-head--row">
            <div>
                <h6>Последние заказы</h6>
                <p>Недавние операции CloudPayments.</p>
            </div>
            <a href="{{ route('admin.resource.index', 'orders') }}" class="adm-card-link">Все</a>
        </div>
        <div style="overflow-x:auto">
            <table class="adm-table">
                <thead>
                    <tr>
                        <th>Order ID</th>
                        <th>User</th>
                        <th>Plan</th>
                        <th>Amount</th>
                        <th>Status</th>
                    </tr>
                </thead>
                <tbody>
                @foreach($latestOrders as $order)
                    <tr>
                        <td style="font-size:.78rem;color:var(--muted)">#{{ $order->invoice_id ?? $order->order_id ?? $order->id }}</td>
                        <td>{{ optional($order->user)->username ?? optional($order->user)->name ?? '—' }}</td>
                        <td>{{ optional($order->plan)->name ?? '—' }}</td>
                        <td>{{ $order->amount ? '₽' . number_format($order->amount, 0, '.', ',') : '—' }}</td>
                        <td><span class="pill pill-{{ $order->status }}">{{ strtoupper($order->status) }}</span></td>
                    </tr>
                @endforeach
                </tbody>
            </table>
        </div>
    </div>
</div>

{{-- Notifications row --}}
<div class="adm-notifications">
    <div class="adm-card adm-notify-compose">
        <div class="adm-card-head">
            <div>
                <h6>Отправить уведомление</h6>
                <p>Рассылка создаст запись в личном кабинете и отправит browser push подписанным устройствам.</p>
            </div>
        </div>

        <form method="POST" action="{{ route('admin.notifications.send') }}" class="adm-form adm-notify-form" data-loader-title="Отправляем уведомление" data-loader-detail="Создаём запись и отправляем push подписанным устройствам.">
            @csrf
            <label>
                Заголовок
                <input type="text" name="title" class="adm-input" placeholder="Например: Плановые работы" required maxlength="255">
            </label>
            <label>
                Текст уведомления
                <textarea name="body" class="adm-input adm-notify-textarea" rows="5" placeholder="Коротко и понятно: что случилось, кого касается, что делать пользователю." required maxlength="2000"></textarea>
            </label>
            <label>
                Тип
                <select name="type" class="adm-input">
                    <option value="info">Информация</option>
                    <option value="success">Успех</option>
                    <option value="warning">Предупреждение</option>
                </select>
            </label>
            <button type="submit" class="adm-btn adm-notify-submit">Отправить всем пользователям</button>
        </form>
    </div>

    <div class="adm-card adm-notify-list-card">
        <div class="adm-card-head adm-card-head--row">
            <div>
                <h6>Последние уведомления</h6>
                <p>Выберите несколько записей, чтобы удалить их одним действием.</p>
            </div>
            @if(! $recentNotifications->isEmpty())
                <button type="button" class="adm-btn adm-btn-ghost adm-btn-sm" id="admNotifSelectAll">Выбрать все</button>
            @endif
        </div>

        @if($recentNotifications->isEmpty())
            <p class="adm-empty-state">Уведомлений нет</p>
        @else
            <form method="POST" action="{{ route('admin.notifications.destroy-many') }}" id="admNotifBulkForm" class="adm-notify-bulk-form">
                @csrf
                @method('DELETE')

                <div class="adm-notify-list">
                    @foreach($recentNotifications as $notif)
                        <article class="adm-notify-item" data-notification-id="{{ $notif->id }}">
                            <label class="adm-check adm-notify-check" title="Выбрать уведомление">
                                <input type="checkbox" name="ids[]" value="{{ $notif->id }}" class="adm-notif-checkbox">
                                <span></span>
                            </label>

                            <div class="adm-notify-content">
                                <div class="adm-notify-meta">
                                    <span class="adm-notify-type adm-notify-type--{{ $notif->type }}">{{ strtoupper($notif->type) }}</span>
                                    <span>{{ $notif->created_at->diffForHumans() }}</span>
                                    @if($notif->is_global)
                                        <span>Всем</span>
                                    @elseif($notif->user_id)
                                        <span>User #{{ $notif->user_id }}</span>
                                    @endif
                                </div>
                                <strong>{{ $notif->title }}</strong>
                                <p>{{ $notif->body }}</p>
                            </div>

                            <button
                                type="button"
                                class="adm-icon-btn adm-icon-btn--danger"
                                title="Удалить уведомление"
                                data-notif-delete="{{ $notif->id }}"
                            >
                                <svg viewBox="0 0 24 24" fill="none" aria-hidden="true">
                                    <path d="M18 6L6 18M6 6l12 12" stroke="currentColor" stroke-width="2" stroke-linecap="round"/>
                                </svg>
                            </button>
                        </article>
                    @endforeach
                </div>

                <div class="adm-notify-bulkbar">
                    <span id="admNotifSelectedCount">Ничего не выбрано</span>
                    <button type="submit" class="adm-btn adm-btn-danger adm-btn-sm" id="admNotifBulkDelete" disabled>
                        Удалить выбранные
                    </button>
                </div>
            </form>

        @endif
    </div>
</div>
</div>

@endsection

@push('scripts')
<script>
// Pass server-side data to JS functions defined in admin-dashboard.js
try {
    admInitMap(@json($mapNodeData));
} catch(e) { console.warn('Map init error', e); }

try {
    admInitChart(
        @json(array_keys($ordersByStatus->toArray())),
        @json(array_values($ordersByStatus->toArray()))
    );
} catch(e) {}

(function () {
    const card = document.querySelector('[data-release-card]');
    const button = document.querySelector('[data-release-toggle]');
    const form = document.querySelector('[data-release-form]');

    if (!card || !button || !form) return;

    function setOpen(isOpen) {
        form.hidden = !isOpen;
        card.classList.toggle('is-open', isOpen);
        button.textContent = isOpen ? 'Скрыть настройки' : 'Управлять версиями';
    }

    button.addEventListener('click', function () {
        setOpen(form.hidden);
    });
})();

(function () {
    let checkboxes = Array.from(document.querySelectorAll('.adm-notif-checkbox'));
    const list = document.querySelector('.adm-notify-list');
    const dashboardScroller = document.querySelector('.adm-dashboard');
    const form = document.getElementById('admNotifBulkForm');
    const countEl = document.getElementById('admNotifSelectedCount');
    const bulkDelete = document.getElementById('admNotifBulkDelete');
    const selectAll = document.getElementById('admNotifSelectAll');
    const csrf = document.querySelector('meta[name="csrf-token"]')?.content || '';
    const deleteUrlTemplate = @json(route('admin.notifications.destroy', ['id' => '__ID__']));

    if (!list || !form || !countEl || !bulkDelete) return;

    let preservedScroll = null;

    function rememberScroll() {
        preservedScroll = {
            windowX: window.scrollX,
            windowY: window.scrollY,
            dashboard: dashboardScroller ? dashboardScroller.scrollTop : null,
            list: list.scrollTop,
        };
    }

    function restoreScroll() {
        if (!preservedScroll) return;

        const snapshot = preservedScroll;
        requestAnimationFrame(function () {
            if (dashboardScroller && snapshot.dashboard !== null) dashboardScroller.scrollTop = snapshot.dashboard;
            list.scrollTop = snapshot.list;
            window.scrollTo(snapshot.windowX, snapshot.windowY);

            requestAnimationFrame(function () {
                if (dashboardScroller && snapshot.dashboard !== null) dashboardScroller.scrollTop = snapshot.dashboard;
                list.scrollTop = snapshot.list;
                window.scrollTo(snapshot.windowX, snapshot.windowY);
                if (preservedScroll === snapshot) preservedScroll = null;
            });
        });
    }

    function updateBulkState() {
        checkboxes = Array.from(document.querySelectorAll('.adm-notif-checkbox'));
        checkboxes.forEach((checkbox) => {
            checkbox.closest('.adm-notify-item')?.classList.toggle('is-selected', checkbox.checked);
        });
        const selected = checkboxes.filter((checkbox) => checkbox.checked).length;
        countEl.textContent = selected ? `Выбрано: ${selected}` : 'Ничего не выбрано';
        bulkDelete.disabled = selected === 0;

        if (selectAll) {
            selectAll.textContent = selected === checkboxes.length ? 'Снять выбор' : 'Выбрать все';
        }
    }

    function setBusy(isBusy) {
        bulkDelete.disabled = isBusy || checkboxes.every((checkbox) => !checkbox.checked);
        list.classList.toggle('is-busy', isBusy);
    }

    async function deleteNotifications(ids) {
        if (!ids.length) return;

        const scrollTop = list.scrollTop;
        setBusy(true);
        window.admShowLoader?.(
            ids.length > 1 ? 'Удаляем уведомления' : 'Удаляем уведомление',
            'Обновляем список без перезагрузки страницы.'
        );

        try {
            const isBulk = ids.length > 1;
            const url = isBulk ? form.action : deleteUrlTemplate.replace('__ID__', encodeURIComponent(ids[0]));
            const body = isBulk ? JSON.stringify({ ids }) : null;
            const response = await fetch(url, {
                method: 'DELETE',
                headers: {
                    'Accept': 'application/json',
                    'Content-Type': 'application/json',
                    'X-CSRF-TOKEN': csrf,
                },
                body,
            });

            if (!response.ok) throw new Error('delete failed');

            ids.forEach((id) => {
                document.querySelector(`[data-notification-id="${id}"]`)?.remove();
            });

            list.scrollTop = Math.min(scrollTop, list.scrollHeight);
            updateBulkState();

            if (!document.querySelector('.adm-notify-item')) {
                form.insertAdjacentHTML('beforebegin', '<p class="adm-empty-state">Уведомлений нет</p>');
                form.remove();
            }
        } catch (error) {
            alert('Не удалось удалить уведомление. Обновите страницу и попробуйте снова.');
            updateBulkState();
        } finally {
            setBusy(false);
            window.admHideLoader?.();
        }
    }

    list.addEventListener('change', function (event) {
        if (event.target.classList.contains('adm-notif-checkbox')) {
            updateBulkState();
            restoreScroll();
        }
    });

    list.addEventListener('pointerdown', function (event) {
        if (event.target.closest('.adm-check')) {
            rememberScroll();
        }
    });

    list.addEventListener('click', function (event) {
        const button = event.target.closest('[data-notif-delete]');
        if (!button) return;

        event.preventDefault();
        const id = button.dataset.notifDelete;
        if (confirm('Удалить это уведомление?')) {
            deleteNotifications([id]);
        }
    });

    form.addEventListener('submit', function (event) {
        event.preventDefault();
        const ids = checkboxes
            .filter((checkbox) => checkbox.checked)
            .map((checkbox) => checkbox.value);

        if (ids.length && confirm('Удалить выбранные уведомления?')) {
            deleteNotifications(ids);
        }
    });

    if (selectAll) {
        selectAll.addEventListener('click', function () {
            rememberScroll();
            checkboxes = Array.from(document.querySelectorAll('.adm-notif-checkbox'));
            const shouldSelect = checkboxes.some((checkbox) => !checkbox.checked);
            checkboxes.forEach((checkbox) => { checkbox.checked = shouldSelect; });
            updateBulkState();
            restoreScroll();
        });
    }

    updateBulkState();
})();
</script>
@endpush
