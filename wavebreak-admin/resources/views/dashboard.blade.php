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
            <div class="adm-card-head">
                <div>
                    <h6>Plans</h6>
                    <p>Тарифы, полученные напрямую из Core.</p>
                </div>
            </div>
            @forelse($plans as $plan)
                <div class="adm-core-snapshot">
                    <span class="adm-core-snapshot__dot"></span>
                    <strong>{{ $plan['name'] }}</strong>
                    <span>{{ strtoupper($plan['code']) }} · ${{ number_format($plan['price_cents'] / 100, 2) }} / {{ $plan['interval'] }}</span>
                </div>
            @empty
                <p class="adm-empty-state">Core пока не вернул тарифы.</p>
            @endforelse
        </section>
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
            <div class="adm-table-wrap">
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
                        <tr>
                            <td>{{ $node['code'] }}</td>
                            <td>{{ $node['region'] }}</td>
                            <td>
                                <span class="node-chip {{ $node['status'] === 'online' ? 'alive' : 'dead' }}">
                                    <span class="node-chip__dot"></span>{{ $node['status'] }}
                                </span>
                            </td>
                            <td>{{ $node['desired_revision'] ?? 0 }}</td>
                            <td>{{ $node['applied_revision'] ?? 0 }}</td>
                            <td class="date-cell">{{ $node['last_heartbeat_at'] ?? '-' }}</td>
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
            <div class="adm-table-wrap">
                <table class="adm-table">
                    <thead><tr><th>Email</th><th>Username</th><th>Role</th><th>Status</th><th>Last login</th></tr></thead>
                    <tbody>
                    @forelse($users ?? [] as $user)
                        <tr>
                            <td>{{ ($user['email'] ?? '') ?: '-' }}</td>
                            <td>{{ ($user['username'] ?? '') ?: '-' }}</td>
                            <td>{{ $user['role'] ?? 'user' }}</td>
                            <td><span class="node-chip {{ ($user['status'] ?? '') === 'active' ? 'alive' : 'dead' }}"><span class="node-chip__dot"></span>{{ $user['status'] ?? 'unknown' }}</span></td>
                            <td class="date-cell">{{ $user['last_login_at'] ?? '-' }}</td>
                        </tr>
                    @empty
                        <tr><td colspan="5">No users returned by Core.</td></tr>
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
            <div class="adm-table-wrap">
                <table class="adm-table">
                    <thead><tr><th>User</th><th>Plan</th><th>Status</th><th>Source</th><th>Devices</th><th>Ends</th><th></th></tr></thead>
                    <tbody>
                    @forelse($subscriptions ?? [] as $subscription)
                        <tr>
                            <td>{{ $subscription['user_id'] }}</td>
                            <td>{{ $subscription['plan_id'] }}</td>
                            <td><span class="node-chip {{ $subscription['status'] === 'active' ? 'alive' : 'dead' }}"><span class="node-chip__dot"></span>{{ $subscription['status'] }}</span></td>
                            <td>{{ $subscription['source'] ?? '-' }}</td>
                            <td>{{ $subscription['device_limit_override'] ?? $subscription['device_limit_snapshot'] ?? '-' }}</td>
                            <td class="date-cell">{{ $subscription['current_period_end'] }}</td>
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
            <div class="adm-table-wrap">
                <table class="adm-table">
                    <thead><tr><th>User</th><th>Node</th><th>Protocol</th><th>Status</th><th>Revision</th><th></th></tr></thead>
                    <tbody>
                    @forelse($grants ?? [] as $grant)
                        <tr>
                            <td>{{ $grant['user_id'] }}</td>
                            <td>{{ $grant['node_id'] }}</td>
                            <td>{{ $grant['protocol'] }}</td>
                            <td><span class="node-chip {{ $grant['status'] === 'active' ? 'alive' : 'dead' }}"><span class="node-chip__dot"></span>{{ $grant['status'] }}</span></td>
                            <td>{{ $grant['desired_revision'] ?? 0 }}</td>
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
            <div class="adm-table-wrap">
                <table class="adm-table">
                    <thead><tr><th>User</th><th>Name</th><th>Platform</th><th>Status</th><th>Last seen</th></tr></thead>
                    <tbody>
                    @forelse($devices ?? [] as $device)
                        <tr>
                            <td>{{ $device['user_id'] }}</td>
                            <td>{{ $device['name'] }}</td>
                            <td>{{ $device['platform'] ?? '-' }}</td>
                            <td><span class="node-chip {{ empty($device['revoked_at']) ? 'alive' : 'dead' }}"><span class="node-chip__dot"></span>{{ empty($device['revoked_at']) ? 'active' : 'revoked' }}</span></td>
                            <td class="date-cell">{{ $device['last_seen_at'] ?? '-' }}</td>
                        </tr>
                    @empty
                        <tr><td colspan="5">No devices returned by Core.</td></tr>
                    @endforelse
                    </tbody>
                </table>
            </div>
        </section>
    @endif

    @if($section === 'traffic')
        <section class="adm-card">
            <div class="adm-card-head">
                <div>
                    <h6>Traffic</h6>
                    <p>Usage rows are subscription-level aggregates, not raw packet logs.</p>
                </div>
            </div>
            <div class="adm-table-wrap">
                <table class="adm-table">
                    <thead><tr><th>User</th><th>Subscription</th><th>Status</th><th>Used</th><th>Limit</th></tr></thead>
                    <tbody>
                    @forelse($traffic ?? [] as $row)
                        <tr>
                            <td>{{ $row['user_id'] }}</td>
                            <td>{{ $row['subscription_id'] }}</td>
                            <td>{{ $row['status'] }}</td>
                            <td>{{ number_format(($row['bytes_total'] ?? 0) / 1073741824, 2) }} GB</td>
                            <td>{{ isset($row['limit_bytes']) ? number_format($row['limit_bytes'] / 1073741824, 0).' GB' : 'unlimited' }}</td>
                        </tr>
                    @empty
                        <tr><td colspan="5">No traffic rows returned by Core.</td></tr>
                    @endforelse
                    </tbody>
                </table>
            </div>
        </section>
    @endif

    @if($section === 'audit')
        <section class="adm-card">
            <div class="adm-card-head">
                <div>
                    <h6>Audit</h6>
                    <p>Recent Core audit events.</p>
                </div>
            </div>
            <div class="adm-table-wrap">
                <table class="adm-table">
                    <thead><tr><th>Action</th><th>Target</th><th>Actor</th><th>Created</th></tr></thead>
                    <tbody>
                    @forelse($auditEvents ?? [] as $event)
                        <tr>
                            <td>{{ $event['action'] }}</td>
                            <td>{{ $event['target_type'] }} / {{ $event['target_id'] ?? '-' }}</td>
                            <td>{{ $event['actor_user_id'] ?? '-' }}</td>
                            <td class="date-cell">{{ $event['created_at'] }}</td>
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
