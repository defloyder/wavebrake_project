@extends('layout')

@section('title', 'Dashboard')
@section('body_class', 'adm-page-dashboard')

@section('content')
@php
    $section = $section ?? 'dashboard';
    $onlineNodes = collect($nodes)->where('status', 'online')->count();
    $offlineNodes = count($nodes) - $onlineNodes;
    $sectionTitles = [
        'dashboard' => 'Operations Dashboard',
        'nodes' => 'Server Network',
        'plans' => 'Plans',
        'enroll' => 'Enroll Node',
        'users' => 'Users',
        'subscriptions' => 'Subscriptions',
        'grants' => 'Access Grants',
        'devices' => 'Devices',
        'traffic' => 'Traffic',
        'audit' => 'Audit',
    ];
    $bytesGB = fn ($bytes) => number_format(($bytes ?? 0) / 1073741824, 2);
@endphp

<div class="adm-dashboard-lite">
    <div>
        <p class="adm-kicker">WAVEBREAK Admin</p>
        <h2 class="adm-section-title">{{ $sectionTitles[$section] ?? 'Operations Dashboard' }}</h2>
    </div>

    @if($section === 'dashboard')
        <section class="adm-kpi-grid">
            <article class="adm-stat"><span>Core</span><strong>{{ strtoupper($health['status'] ?? 'unknown') }}</strong></article>
            <article class="adm-stat"><span>Users</span><strong>{{ $dashboard['users'] ?? count($users ?? []) }}</strong></article>
            <article class="adm-stat"><span>Active subs</span><strong>{{ $dashboard['active_subscriptions'] ?? count($subscriptions ?? []) }}</strong></article>
            <article class="adm-stat"><span>Nodes online</span><strong>{{ $dashboard['nodes_online'] ?? $onlineNodes }}</strong></article>
        </section>

        <section class="adm-card adm-chart-card">
            <div class="adm-card-head adm-card-head--row">
                <div>
                    <h6>Трафик</h6>
                    <p>Суммарно по всем подпискам, up + down, за сутки.</p>
                </div>
                @if(count($trafficHistory ?? []) > 0)
                    <div class="adm-range-toggle" data-range-for="chart-traffic-overview">
                        <button type="button" data-range="1">Сегодня</button>
                        <button type="button" data-range="7">7 дней</button>
                        <button type="button" data-range="30" class="is-active">30 дней</button>
                    </div>
                @endif
            </div>
            <div class="adm-chart-wrap">
                @if(count($trafficHistory ?? []) > 0)
                    <canvas id="chart-traffic-overview"></canvas>
                @else
                    <p class="adm-chart-empty">Пока нет данных: ни одна подписка ещё не сообщила суточный трафик.</p>
                @endif
            </div>
        </section>

        <section class="adm-grid">
            <a href="/nodes" class="adm-card adm-menu-card">
                <div>
                    <h6>Server Network</h6>
                    <p>Node heartbeat, desired revision and applied revision from Core.</p>
                </div>
                <span class="adm-settings-status">{{ $onlineNodes }}/{{ count($nodes) }} online</span>
            </a>
            <a href="/plans" class="adm-card adm-menu-card">
                <div>
                    <h6>Plans</h6>
                    <p>Tariffs fetched directly from WAVEBREAK Core API.</p>
                </div>
                <span class="adm-settings-status">{{ count($plans) }} plans</span>
            </a>
            <a href="/enroll" class="adm-card adm-menu-card">
                <div>
                    <h6>Enroll Node</h6>
                    <p>Create a node enrollment through Core, then let the node agent sync.</p>
                </div>
                <span class="adm-settings-status">Core API</span>
            </a>
            <a href="/users" class="adm-card adm-menu-card">
                <div>
                    <h6>Users</h6>
                    <p>Accounts and roles from Core, including Telegram-first identities.</p>
                </div>
                <span class="adm-settings-status">{{ count($users ?? []) }} loaded</span>
            </a>
            <a href="/subscriptions" class="adm-card adm-menu-card">
                <div>
                    <h6>Subscriptions</h6>
                    <p>Owner, source, status and effective limits captured at activation.</p>
                </div>
                <span class="adm-settings-status">{{ count($subscriptions ?? []) }} loaded</span>
            </a>
            <a href="/grants" class="adm-card adm-menu-card">
                <div>
                    <h6>Access Grants</h6>
                    <p>Issued access, revoke lifecycle and desired-state revision tracking.</p>
                </div>
                <span class="adm-settings-status">{{ count($grants ?? []) }} loaded</span>
            </a>
            <a href="/traffic" class="adm-card adm-menu-card">
                <div>
                    <h6>Traffic</h6>
                    <p>Subscription usage aggregated from node monotonic counters.</p>
                </div>
                <span class="adm-settings-status">{{ count($traffic ?? []) }} rows</span>
            </a>
            <a href="/audit" class="adm-card adm-menu-card">
                <div>
                    <h6>Audit</h6>
                    <p>Core-written operational audit events for admin actions.</p>
                </div>
                <span class="adm-settings-status">{{ count($auditEvents ?? []) }} events</span>
            </a>
        </section>

        @push('scripts')
        <script>
        document.addEventListener('DOMContentLoaded', () => {
            const raw = @json($trafficHistory ?? []);
            window.admInitRangeChart('chart-traffic-overview', raw, (rows) => ({
                datasets: [{
                    label: 'GB / день',
                    data: rows.map(r => ((r.bytes_up || 0) + (r.bytes_down || 0)) / 1073741824),
                    borderColor: '#00D6FF',
                    backgroundColor: 'rgba(0,214,255,.12)',
                    fill: true,
                    tension: .35,
                    pointRadius: 2,
                    pointBackgroundColor: '#00D6FF',
                }],
                plugins: { legend: { display: false } },
            }));
        });
        </script>
        @endpush
    @endif

    @if($section === 'enroll')
        <section class="adm-card" id="enroll">
            <div class="adm-card-head">
                <div>
                    <h6>Enroll Node</h6>
                    <p>Создает node enrollment через WAVEBREAK Core API.</p>
                </div>
            </div>
            <form method="post" action="/nodes/enroll" class="adm-form">
                @csrf
                <label>Code
                    <input name="code" class="adm-input" value="TR-IST-01" required>
                </label>
                <label>Region
                    <input name="region" class="adm-input" value="TR" required>
                </label>
                <button type="submit" class="adm-btn adm-btn-primary">Enroll</button>
            </form>
        </section>
    @endif

    @if($section === 'plans')
        <section class="adm-card" id="plans">
            <div class="adm-card-head adm-card-head--row">
                <div>
                    <h6>Plans</h6>
                    <p>Тарифы, полученные напрямую из Core.</p>
                </div>
                <button type="button" class="adm-btn adm-btn-primary" onclick="admOpenPlanModal()">+ Новый тариф</button>
            </div>

            <div class="adm-table-toolbar">
                <div class="adm-table-search">
                    <input type="search" data-table-search placeholder="Поиск по коду или названию...">
                </div>
                <span class="adm-table-count" data-table-count></span>
            </div>
            <div class="adm-table-wrap" data-enhance>
                <table class="adm-table">
                    <thead>
                        <tr>
                            <th>Code</th>
                            <th>Name</th>
                            <th>Price</th>
                            <th>Interval</th>
                            <th>Devices</th>
                            <th>Traffic</th>
                            <th>Active</th>
                            <th data-sortable="false"></th>
                        </tr>
                    </thead>
                    <tbody>
                    @forelse($plans as $plan)
                        <tr data-row data-search="{{ $plan['code'] }} {{ $plan['name'] }}">
                            <td>{{ strtoupper($plan['code']) }}</td>
                            <td>{{ $plan['name'] }}</td>
                            <td data-sort="{{ $plan['price_minor'] ?? 0 }}">${{ number_format(($plan['price_minor'] ?? $plan['price_cents'] ?? 0) / 100, 2) }}</td>
                            <td>{{ $plan['interval'] ?? 'month' }}</td>
                            <td class="num-cell" data-sort="{{ $plan['device_limit'] ?? 0 }}">{{ $plan['device_limit'] ?? '-' }}</td>
                            <td>{{ isset($plan['traffic_limit_bytes']) && $plan['traffic_limit_bytes'] ? number_format($plan['traffic_limit_bytes'] / 1073741824, 0).' GB' : 'unlimited' }}</td>
                            <td><span class="node-chip {{ ($plan['is_active'] ?? true) ? 'alive' : 'dead' }}"><span class="node-chip__dot"></span>{{ ($plan['is_active'] ?? true) ? 'active' : 'inactive' }}</span></td>
                            <td>
                                <div class="adm-row-actions">
                                    <button type="button" class="adm-icon-btn" title="Редактировать" onclick='admOpenPlanModal(@json($plan))'>
                                        <svg viewBox="0 0 24 24" width="14" height="14" fill="none"><path d="M12 20h9M16.5 3.5a2.1 2.1 0 0 1 3 3L7 19l-4 1 1-4Z" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/></svg>
                                    </button>
                                    <form method="post" action="/plans/{{ $plan['id'] }}/delete" onsubmit="return confirm('Удалить тариф {{ $plan['code'] }}?')">
                                        @csrf
                                        <button type="submit" class="adm-icon-btn" title="Удалить" style="color: var(--danger);">
                                            <svg viewBox="0 0 24 24" width="14" height="14" fill="none"><path d="M3 6h18M8 6V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2m3 0-1 14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2L4 6h16Z" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/></svg>
                                        </button>
                                    </form>
                                </div>
                            </td>
                        </tr>
                    @empty
                        <tr><td colspan="8">Core пока не вернул тарифы.</td></tr>
                    @endforelse
                    </tbody>
                </table>
            </div>
        </section>

        <div class="adm-modal-backdrop" id="adm-plan-modal">
            <div class="adm-modal">
                <div class="adm-modal-head">
                    <h6 id="adm-plan-modal-title">Новый тариф</h6>
                    <button type="button" class="adm-modal-close" onclick="admClosePlanModal()">
                        <svg viewBox="0 0 24 24" width="14" height="14" fill="none"><path d="M18 6 6 18M6 6l12 12" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></svg>
                    </button>
                </div>
                <form method="post" id="adm-plan-form" class="adm-form" action="/plans">
                    @csrf
                    <div class="adm-form-row">
                        <label>Code
                            <input name="code" id="pf-code" class="adm-input" required>
                        </label>
                        <label>Interval
                            <select name="interval" id="pf-interval" class="adm-compact-select">
                                <option value="month">month</option>
                                <option value="year">year</option>
                            </select>
                        </label>
                    </div>
                    <label>Name
                        <input name="name" id="pf-name" class="adm-input" required>
                    </label>
                    <label>Description
                        <input name="description" id="pf-description" class="adm-input">
                    </label>
                    <div class="adm-form-row">
                        <label>Price (cents)
                            <input name="price_minor" id="pf-price" type="number" min="0" class="adm-input" required>
                        </label>
                        <label>Device limit
                            <input name="device_limit" id="pf-devices" type="number" min="1" class="adm-input" required>
                        </label>
                    </div>
                    <label>Traffic limit, bytes (пусто = unlimited)
                        <input name="traffic_limit_bytes" id="pf-traffic" type="number" min="0" class="adm-input">
                    </label>
                    <div class="adm-form-row">
                        <label class="adm-form-check"><input type="checkbox" name="is_active" id="pf-active" value="1" checked> Active</label>
                        <label class="adm-form-check"><input type="checkbox" name="is_public" id="pf-public" value="1" checked> Public</label>
                    </div>
                    <div class="adm-form-actions">
                        <button type="submit" class="adm-btn adm-btn-primary">Сохранить</button>
                        <button type="button" class="adm-btn" onclick="admClosePlanModal()">Отмена</button>
                    </div>
                </form>
            </div>
        </div>

        @push('scripts')
        <script>
        function admOpenPlanModal(plan) {
            const form = document.getElementById('adm-plan-form');
            const title = document.getElementById('adm-plan-modal-title');
            form.reset();
            if (plan && plan.id) {
                title.textContent = 'Редактировать тариф';
                form.action = '/plans/' + plan.id;
                document.getElementById('pf-code').value = plan.code || '';
                document.getElementById('pf-name').value = plan.name || '';
                document.getElementById('pf-description').value = plan.description || '';
                document.getElementById('pf-price').value = plan.price_minor ?? plan.price_cents ?? 0;
                document.getElementById('pf-devices').value = plan.device_limit ?? 1;
                document.getElementById('pf-traffic').value = plan.traffic_limit_bytes ?? '';
                document.getElementById('pf-interval').value = plan.interval || 'month';
                document.getElementById('pf-active').checked = plan.is_active !== false;
                document.getElementById('pf-public').checked = plan.is_public !== false;
            } else {
                title.textContent = 'Новый тариф';
                form.action = '/plans';
            }
            document.getElementById('adm-plan-modal').classList.add('open');
        }
        function admClosePlanModal() {
            document.getElementById('adm-plan-modal').classList.remove('open');
        }
        document.getElementById('adm-plan-modal')?.addEventListener('click', (e) => {
            if (e.target.id === 'adm-plan-modal') admClosePlanModal();
        });
        </script>
        @endpush
    @endif

    @if($section === 'nodes')
        <section class="adm-card" id="nodes">
            <div class="adm-card-head adm-card-head--row">
                <div>
                    <h6>Server Network</h6>
                    <p>Состояние нод из Core, включая heartbeat/applied revision.</p>
                </div>
                <span class="adm-settings-status">{{ $onlineNodes }}/{{ count($nodes) }} online</span>
            </div>
            <div class="adm-table-toolbar">
                <div class="adm-table-search">
                    <input type="search" data-table-search placeholder="Поиск по коду или региону...">
                </div>
                <span class="adm-table-count" data-table-count></span>
            </div>
            <div class="adm-table-wrap" data-enhance>
                <table class="adm-table">
                    <thead>
                        <tr>
                            <th>Code</th>
                            <th>Region</th>
                            <th>Status</th>
                            <th>Desired</th>
                            <th>Applied</th>
                            <th>Last heartbeat</th>
                        </tr>
                    </thead>
                    <tbody>
                    @forelse($nodes as $node)
                        <tr data-row data-search="{{ $node['code'] }} {{ $node['region'] }} {{ $node['status'] }}">
                            <td>{{ $node['code'] }}</td>
                            <td>{{ $node['region'] }}</td>
                            <td>
                                <span class="node-chip {{ $node['status'] === 'online' ? 'alive' : 'dead' }}">
                                    <span class="node-chip__dot"></span>{{ $node['status'] }}
                                </span>
                            </td>
                            <td class="num-cell">{{ $node['desired_revision'] ?? 0 }}</td>
                            <td class="num-cell">{{ $node['applied_revision'] ?? 0 }}</td>
                            <td class="date-cell" data-sort="{{ $node['last_heartbeat_at'] ?? '' }}">{{ $node['last_heartbeat_at'] ?? '-' }}</td>
                        </tr>
                    @empty
                        <tr><td colspan="6">Ноды пока не зарегистрированы.</td></tr>
                    @endforelse
                    </tbody>
                </table>
            </div>
        </section>
    @endif

    @if($section === 'users')
        <section class="adm-card">
            <div class="adm-card-head">
                <div>
                    <h6>Users</h6>
                    <p>Core remains the source of truth for account status, role and login activity.</p>
                </div>
            </div>
            <div class="adm-table-toolbar">
                <div class="adm-table-search">
                    <input type="search" data-table-search placeholder="Поиск по email или username...">
                </div>
                <span class="adm-table-count" data-table-count></span>
            </div>
            <div class="adm-table-wrap" data-enhance>
                <table class="adm-table">
                    <thead><tr><th>Email</th><th>Username</th><th>Role</th><th>Status</th><th>Last login</th><th data-sortable="false"></th></tr></thead>
                    <tbody>
                    @forelse($users ?? [] as $user)
                        <tr data-row data-search="{{ $user['email'] ?? '' }} {{ $user['username'] ?? '' }}">
                            <td>{{ ($user['email'] ?? '') ?: '-' }}</td>
                            <td>{{ ($user['username'] ?? '') ?: '-' }}</td>
                            <td>
                                <form method="post" action="/users/{{ $user['id'] }}/role" class="adm-inline-form">
                                    @csrf
                                    <select name="role" class="adm-role-select" onchange="this.form.submit()">
                                        @foreach(['user','support','admin','superadmin'] as $role)
                                            <option value="{{ $role }}" @selected(($user['role'] ?? 'user') === $role)>{{ $role }}</option>
                                        @endforeach
                                    </select>
                                </form>
                            </td>
                            <td>
                                <span class="node-chip {{ empty($user['disabled_at']) ? 'alive' : 'dead' }}"><span class="node-chip__dot"></span>{{ empty($user['disabled_at']) ? 'active' : 'disabled' }}</span>
                            </td>
                            <td class="date-cell" data-sort="{{ $user['last_login_at'] ?? '' }}">{{ $user['last_login_at'] ?? '-' }}</td>
                            <td>
                                @if(empty($user['disabled_at']))
                                    <form method="post" action="/users/{{ $user['id'] }}/disable" class="adm-inline-form" onsubmit="return confirm('Заблокировать {{ $user['email'] ?? 'пользователя' }}?')">
                                        @csrf
                                        <button type="submit" class="adm-link-button">Заблокировать</button>
                                    </form>
                                @else
                                    <form method="post" action="/users/{{ $user['id'] }}/enable" class="adm-inline-form">
                                        @csrf
                                        <button type="submit" class="adm-link-button" style="color: var(--success);">Разблокировать</button>
                                    </form>
                                @endif
                            </td>
                        </tr>
                    @empty
                        <tr><td colspan="6">No users returned by Core.</td></tr>
                    @endforelse
                    </tbody>
                </table>
            </div>
        </section>
    @endif

    @if($section === 'subscriptions')
        <section class="adm-card">
            <div class="adm-card-head">
                <div>
                    <h6>Subscriptions</h6>
                    <p>Activation source, period and frozen limits are stored in Core.</p>
                </div>
            </div>
            <div class="adm-table-toolbar">
                <div class="adm-table-search">
                    <input type="search" data-table-search placeholder="Поиск по user/plan/status...">
                </div>
                <span class="adm-table-count" data-table-count></span>
            </div>
            <div class="adm-table-wrap" data-enhance>
                <table class="adm-table">
                    <thead><tr><th>User</th><th>Plan</th><th>Status</th><th>Source</th><th>Devices</th><th>Ends</th><th></th></tr></thead>
                    <tbody>
                    @forelse($subscriptions ?? [] as $subscription)
                        <tr data-row data-search="{{ $subscription['user_id'] }} {{ $subscription['plan_id'] }} {{ $subscription['status'] }}">
                            <td>{{ $subscription['user_id'] }}</td>
                            <td>{{ $subscription['plan_id'] }}</td>
                            <td><span class="node-chip {{ $subscription['status'] === 'active' ? 'alive' : 'dead' }}"><span class="node-chip__dot"></span>{{ $subscription['status'] }}</span></td>
                            <td>{{ $subscription['source'] ?? '-' }}</td>
                            <td class="num-cell">{{ $subscription['device_limit_override'] ?? $subscription['device_limit_snapshot'] ?? '-' }}</td>
                            <td class="date-cell" data-sort="{{ $subscription['current_period_end'] }}">{{ $subscription['current_period_end'] }}</td>
                            <td>
                                <form method="post" action="/subscriptions/{{ $subscription['id'] }}/status" class="adm-inline-form">
                                    @csrf
                                    <select name="status" class="adm-compact-select" onchange="this.form.submit()">
                                        @foreach(['active','suspended','cancelled','expired'] as $status)
                                            <option value="{{ $status }}" @selected($subscription['status'] === $status)>{{ $status }}</option>
                                        @endforeach
                                    </select>
                                </form>
                            </td>
                        </tr>
                    @empty
                        <tr><td colspan="7">No subscriptions returned by Core.</td></tr>
                    @endforelse
                    </tbody>
                </table>
            </div>
        </section>
    @endif

    @if($section === 'grants')
        <section class="adm-card">
            <div class="adm-card-head">
                <div>
                    <h6>Access Grants</h6>
                    <p>Revoking a grant publishes an event and updates node desired-state.</p>
                </div>
            </div>
            <div class="adm-table-toolbar">
                <div class="adm-table-search">
                    <input type="search" data-table-search placeholder="Поиск по user/node/protocol...">
                </div>
                <span class="adm-table-count" data-table-count></span>
            </div>
            <div class="adm-table-wrap" data-enhance>
                <table class="adm-table">
                    <thead><tr><th>User</th><th>Node</th><th>Protocol</th><th>Status</th><th>Revision</th><th></th></tr></thead>
                    <tbody>
                    @forelse($grants ?? [] as $grant)
                        <tr data-row data-search="{{ $grant['user_id'] }} {{ $grant['node_id'] }} {{ $grant['protocol'] }} {{ $grant['status'] }}">
                            <td>{{ $grant['user_id'] }}</td>
                            <td>{{ $grant['node_id'] }}</td>
                            <td>{{ $grant['protocol'] }}</td>
                            <td><span class="node-chip {{ $grant['status'] === 'active' ? 'alive' : 'dead' }}"><span class="node-chip__dot"></span>{{ $grant['status'] }}</span></td>
                            <td class="num-cell">{{ $grant['desired_revision'] ?? 0 }}</td>
                            <td>
                                @if($grant['status'] === 'active')
                                    <form method="post" action="/grants/{{ $grant['id'] }}/revoke" class="adm-inline-form">
                                        @csrf
                                        <input type="hidden" name="reason" value="admin">
                                        <button type="submit" class="adm-link-button">Revoke</button>
                                    </form>
                                @endif
                            </td>
                        </tr>
                    @empty
                        <tr><td colspan="6">No grants returned by Core.</td></tr>
                    @endforelse
                    </tbody>
                </table>
            </div>
        </section>
    @endif

    @if($section === 'devices')
        <section class="adm-card">
            <div class="adm-card-head">
                <div>
                    <h6>Devices</h6>
                    <p>Registered and revoked devices from Core.</p>
                </div>
            </div>
            <div class="adm-table-toolbar">
                <div class="adm-table-search">
                    <input type="search" data-table-search placeholder="Поиск по user/name/platform...">
                </div>
                <span class="adm-table-count" data-table-count></span>
            </div>
            <div class="adm-table-wrap" data-enhance>
                <table class="adm-table">
                    <thead><tr><th>User</th><th>Name</th><th>Platform</th><th>Status</th><th>Last seen</th><th></th></tr></thead>
                    <tbody>
                    @forelse($devices ?? [] as $device)
                        <tr data-row data-search="{{ $device['user_id'] }} {{ $device['name'] }} {{ $device['platform'] ?? '' }}">
                            <td>{{ $device['user_id'] }}</td>
                            <td>{{ $device['name'] }}</td>
                            <td>{{ $device['platform'] ?? '-' }}</td>
                            <td><span class="node-chip {{ empty($device['revoked_at']) ? 'alive' : 'dead' }}"><span class="node-chip__dot"></span>{{ empty($device['revoked_at']) ? 'active' : 'revoked' }}</span></td>
                            <td class="date-cell" data-sort="{{ $device['last_seen_at'] ?? '' }}">{{ $device['last_seen_at'] ?? '-' }}</td>
                            <td>
                                @if(empty($device['revoked_at']))
                                    <form method="post" action="/devices/{{ $device['id'] }}/revoke" class="adm-inline-form" onsubmit="return confirm('Отозвать устройство {{ $device['name'] }}?')">
                                        @csrf
                                        <button type="submit" class="adm-link-button">Revoke</button>
                                    </form>
                                @endif
                            </td>
                        </tr>
                    @empty
                        <tr><td colspan="6">No devices returned by Core.</td></tr>
                    @endforelse
                    </tbody>
                </table>
            </div>
        </section>
    @endif

    @if($section === 'traffic')
        <section class="adm-card adm-chart-card">
            <div class="adm-card-head adm-card-head--row">
                <div>
                    <h6>Трафик</h6>
                    <p>Сумма bytes_up + bytes_down по всем подпискам за сутки — здесь видна просадка.</p>
                </div>
                @if(count($trafficHistory ?? []) > 0)
                    <div class="adm-range-toggle" data-range-for="chart-traffic-detail">
                        <button type="button" data-range="1">Сегодня</button>
                        <button type="button" data-range="7">7 дней</button>
                        <button type="button" data-range="30" class="is-active">30 дней</button>
                    </div>
                @endif
            </div>
            <div class="adm-chart-wrap">
                @if(count($trafficHistory ?? []) > 0)
                    <canvas id="chart-traffic-detail"></canvas>
                @else
                    <p class="adm-chart-empty">Пока нет исторических данных по трафику.</p>
                @endif
            </div>
        </section>

        <section class="adm-card">
            <div class="adm-card-head">
                <div>
                    <h6>Traffic (current)</h6>
                    <p>Usage rows are subscription-level aggregates, not raw packet logs.</p>
                </div>
            </div>
            <div class="adm-table-toolbar">
                <div class="adm-table-search">
                    <input type="search" data-table-search placeholder="Поиск по user/subscription...">
                </div>
                <span class="adm-table-count" data-table-count></span>
            </div>
            <div class="adm-table-wrap" data-enhance>
                <table class="adm-table">
                    <thead><tr><th>User</th><th>Subscription</th><th>Status</th><th>Used</th><th>Limit</th></tr></thead>
                    <tbody>
                    @forelse($traffic ?? [] as $row)
                        <tr data-row data-search="{{ $row['user_id'] }} {{ $row['subscription_id'] }} {{ $row['status'] }}">
                            <td>{{ $row['user_id'] }}</td>
                            <td>{{ $row['subscription_id'] }}</td>
                            <td>{{ $row['status'] }}</td>
                            <td class="num-cell" data-sort="{{ $row['bytes_total'] ?? 0 }}">{{ $bytesGB($row['bytes_total'] ?? 0) }} GB</td>
                            <td>{{ isset($row['limit_bytes']) ? number_format($row['limit_bytes'] / 1073741824, 0).' GB' : 'unlimited' }}</td>
                        </tr>
                    @empty
                        <tr><td colspan="5">No traffic rows returned by Core.</td></tr>
                    @endforelse
                    </tbody>
                </table>
            </div>
        </section>

        @push('scripts')
        <script>
        document.addEventListener('DOMContentLoaded', () => {
            const raw = @json($trafficHistory ?? []);
            window.admInitRangeChart('chart-traffic-detail', raw, (rows) => ({
                datasets: [
                    { label: 'Upload, GB', data: rows.map(r => (r.bytes_up || 0) / 1073741824), borderColor: '#00D6FF', backgroundColor: 'rgba(0,214,255,.1)', fill: true, tension: .35, pointRadius: 2 },
                    { label: 'Download, GB', data: rows.map(r => (r.bytes_down || 0) / 1073741824), borderColor: '#35E0A1', backgroundColor: 'rgba(53,224,161,.1)', fill: true, tension: .35, pointRadius: 2 },
                ],
                plugins: { legend: { labels: { color: 'rgba(230,242,247,.8)' } } },
            }));
        });
        </script>
        @endpush
    @endif

    @if($section === 'audit')
        <section class="adm-card">
            <div class="adm-card-head">
                <div>
                    <h6>Audit</h6>
                    <p>Recent Core audit events.</p>
                </div>
            </div>
            <div class="adm-table-toolbar">
                <div class="adm-table-search">
                    <input type="search" data-table-search placeholder="Поиск по action/target...">
                </div>
                <span class="adm-table-count" data-table-count></span>
            </div>
            <div class="adm-table-wrap" data-enhance>
                <table class="adm-table">
                    <thead><tr><th>Action</th><th>Target</th><th>Actor</th><th>Created</th></tr></thead>
                    <tbody>
                    @forelse($auditEvents ?? [] as $event)
                        <tr data-row data-search="{{ $event['action'] }} {{ $event['target_type'] }} {{ $event['target_id'] ?? '' }}">
                            <td>{{ $event['action'] }}</td>
                            <td>{{ $event['target_type'] }} / {{ $event['target_id'] ?? '-' }}</td>
                            <td>{{ $event['actor_user_id'] ?? '-' }}</td>
                            <td class="date-cell" data-sort="{{ $event['created_at'] }}">{{ $event['created_at'] }}</td>
                        </tr>
                    @empty
                        <tr><td colspan="4">No audit events returned by Core.</td></tr>
                    @endforelse
                    </tbody>
                </table>
            </div>
        </section>
    @endif
</div>
@endsection
