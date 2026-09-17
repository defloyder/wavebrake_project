<!doctype html>
<html lang="ru">
<head>
    @php
        $assetVersion = fn (string $path) => file_exists(public_path($path)) ? filemtime(public_path($path)) : time();
    @endphp
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="csrf-token" content="{{ csrf_token() }}">
    <title>@yield('title', 'Admin') | WAVEBREAK</title>
    <link rel="icon" href="{{ asset('favicon.ico') }}">
    <link rel="icon" type="image/png" sizes="192x192" href="{{ asset('images/favicon.png') }}">
    <link rel="apple-touch-icon" href="{{ asset('images/apple-touch-icon.png') }}">
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800&display=swap" rel="stylesheet">
    <link rel="stylesheet" href="{{ asset('css/admin.css') }}?v={{ $assetVersion('css/admin.css') }}">
    <link rel="stylesheet" href="{{ asset('css/auth.css') }}?v={{ $assetVersion('css/auth.css') }}">
    <script src="{{ asset('js/chart.min.js') }}?v={{ $assetVersion('js/chart.min.js') }}" defer></script>
</head>
<body class="@yield('body_class')">
@hasSection('auth_content')
    <main class="adm-auth-shell">
        @yield('auth_content')
    </main>
@else
@php
    $nodeList = $nodes ?? [];
    $onlineNodes = collect($nodeList)->where('status', 'online')->count();
    $activeSection = $section ?? request()->segment(1) ?: 'dashboard';
@endphp
<div class="adm-overlay" id="adm-overlay" onclick="admCloseSidebar()"></div>
<div class="adm-layout">
    <aside class="adm-sidebar" id="adm-sidebar">
        <div class="adm-sidebar-header">
            <a href="/" class="adm-brand">
                <img src="{{ asset('images/wavebreak-logo.png') }}" class="wavebreak-logo" alt="">
                <span class="adm-brand-word"><strong>WAVEBREAK</strong><small>Admin</small></span>
            </a>
            <button class="adm-hamburger adm-close-btn" onclick="admCloseSidebar()" aria-label="Закрыть меню">
                <svg viewBox="0 0 24 24" fill="none" width="16" height="16">
                    <path d="M18 6L6 18M6 6l12 12" stroke="currentColor" stroke-width="2" stroke-linecap="round"/>
                </svg>
            </button>
        </div>

        <nav class="adm-nav">
            <a href="/dashboard" class="adm-link {{ $activeSection === 'dashboard' ? 'active' : '' }}">
                <svg viewBox="0 0 24 24" fill="none"><rect x="3" y="3" width="7" height="7" rx="1.5" stroke="currentColor" stroke-width="1.7"/><rect x="14" y="3" width="7" height="7" rx="1.5" stroke="currentColor" stroke-width="1.7"/><rect x="3" y="14" width="7" height="7" rx="1.5" stroke="currentColor" stroke-width="1.7"/><rect x="14" y="14" width="7" height="7" rx="1.5" stroke="currentColor" stroke-width="1.7"/></svg>
                <span>Dashboard</span>
            </a>
            <a href="/nodes" class="adm-link {{ $activeSection === 'nodes' ? 'active' : '' }}">
                <svg viewBox="0 0 24 24" fill="none"><circle cx="12" cy="12" r="3" stroke="currentColor" stroke-width="1.7"/><path d="M12 2v3m0 14v3M2 12h3m14 0h3m-3.5-7.5-2.1 2.1M6.6 17.4l-2.1 2.1m0-13.1 2.1 2.1m8.7 8.7 2.1 2.1" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"/></svg>
                <span>Nodes</span>
            </a>
            <a href="/plans" class="adm-link {{ $activeSection === 'plans' ? 'active' : '' }}">
                <svg viewBox="0 0 24 24" fill="none"><path d="M9 5H7a2 2 0 0 0-2 2v12a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V7a2 2 0 0 0-2-2h-2M9 5a2 2 0 0 0 2 2h2a2 2 0 0 0 2-2M9 5a2 2 0 0 1 2-2h2a2 2 0 0 1 2 2" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"/></svg>
                <span>Plans</span>
            </a>
            <a href="/users" class="adm-link {{ $activeSection === 'users' ? 'active' : '' }}">
                <svg viewBox="0 0 24 24" fill="none"><path d="M16 21v-2a4 4 0 0 0-4-4H7a4 4 0 0 0-4 4v2M9.5 11a4 4 0 1 0 0-8 4 4 0 0 0 0 8ZM21 21v-2a4 4 0 0 0-3-3.87M16 3.13a4 4 0 0 1 0 7.75" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"/></svg>
                <span>Users</span>
            </a>
            <a href="/subscriptions" class="adm-link {{ $activeSection === 'subscriptions' ? 'active' : '' }}">
                <svg viewBox="0 0 24 24" fill="none"><path d="M4 6h16M6 10h12M8 14h8M10 18h4" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"/></svg>
                <span>Subscriptions</span>
            </a>
            <a href="/grants" class="adm-link {{ $activeSection === 'grants' ? 'active' : '' }}">
                <svg viewBox="0 0 24 24" fill="none"><path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10Z" stroke="currentColor" stroke-width="1.7" stroke-linejoin="round"/><path d="M9 12l2 2 4-4" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"/></svg>
                <span>Grants</span>
            </a>
            <a href="/devices" class="adm-link {{ $activeSection === 'devices' ? 'active' : '' }}">
                <svg viewBox="0 0 24 24" fill="none"><rect x="6" y="3" width="12" height="18" rx="2.5" stroke="currentColor" stroke-width="1.7"/><path d="M10 18h4" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"/></svg>
                <span>Devices</span>
            </a>
            <a href="/traffic" class="adm-link {{ $activeSection === 'traffic' ? 'active' : '' }}">
                <svg viewBox="0 0 24 24" fill="none"><path d="M4 17h4l3-10 4 14 3-8h2" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"/></svg>
                <span>Traffic</span>
            </a>
            <a href="/audit" class="adm-link {{ $activeSection === 'audit' ? 'active' : '' }}">
                <svg viewBox="0 0 24 24" fill="none"><path d="M6 3h9l3 3v15H6z" stroke="currentColor" stroke-width="1.7" stroke-linejoin="round"/><path d="M9 10h6M9 14h6M9 18h4" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"/></svg>
                <span>Audit</span>
            </a>
            <a href="/enroll" class="adm-link {{ $activeSection === 'enroll' ? 'active' : '' }}">
                <svg viewBox="0 0 24 24" fill="none"><path d="M4 7h16M4 12h10M4 17h7" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"/><path d="M17 15l2 2 3-4" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"/></svg>
                <span>Enroll</span>
            </a>
        </nav>

        <form method="post" action="/logout" class="adm-logout-form">
            @csrf
            <button type="submit" class="adm-logout-btn">
                <svg viewBox="0 0 24 24" fill="none"><path d="M17 16l4-4m0 0l-4-4m4 4H7m6 4v1a3 3 0 0 1-3 3H6a3 3 0 0 1-3-3V7a3 3 0 0 1 3-3h4a3 3 0 0 1 3 3v1" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"/></svg>
                <span>Выйти</span>
            </button>
        </form>
    </aside>

    <main class="adm-main">
        <button class="adm-hamburger adm-hamburger--open" onclick="admToggleSidebar()" aria-label="Открыть меню">
            <svg viewBox="0 0 24 24" fill="none" width="16" height="16">
                <path d="M4 6h16M4 12h16M4 18h16" stroke="currentColor" stroke-width="2" stroke-linecap="round"/>
            </svg>
        </button>
        <div class="health-bar">
            <div class="health-bar-stats">
                <strong>Core:</strong>
                <span class="health-stat">Status <span>{{ $health['status'] ?? 'unavailable' }}</span></span>
                <span class="health-stat">Nodes <span>{{ $onlineNodes }}/{{ count($nodeList) }}</span></span>
            </div>
            <div class="health-bar-nodes">
                @foreach($nodeList as $node)
                    <span class="node-chip {{ ($node['status'] ?? '') === 'online' ? 'alive' : 'dead' }}">
                        <span class="node-chip__dot"></span>
                        {{ $node['code'] ?? 'node' }}
                        <span class="hb-load">{{ $node['region'] ?? '-' }}</span>
                    </span>
                @endforeach
            </div>
        </div>

        @if (session('success'))
            <div class="adm-alert">{{ session('success') }}</div>
        @endif
        @if (session('error'))
            <div class="adm-alert adm-alert--error">{{ session('error') }}</div>
        @endif
        @if($errors->any())
            <div class="adm-alert adm-alert--error">
                @foreach($errors->all() as $error)<p>{{ $error }}</p>@endforeach
            </div>
        @endif

        @yield('content')
        @stack('scripts')
    </main>
</div>

<script src="{{ asset('js/admin-table.js') }}?v={{ $assetVersion('js/admin-table.js') }}" defer></script>
<script>
function admToggleSidebar() {
    document.getElementById('adm-sidebar')?.classList.toggle('open');
    document.getElementById('adm-overlay')?.classList.toggle('open');
}
function admCloseSidebar() {
    document.getElementById('adm-sidebar')?.classList.remove('open');
    document.getElementById('adm-overlay')?.classList.remove('open');
}
document.querySelectorAll('.adm-link').forEach(function (link) {
    link.addEventListener('click', admCloseSidebar);
});
</script>
@endif
</body>
</html>

