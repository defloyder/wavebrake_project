<!doctype html>
<html lang="ru">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="csrf-token" content="{{ csrf_token() }}">
    <title>@yield('title', 'Admin') | Auralith</title>
    <link rel="icon" type="image/png" sizes="32x32" href="{{ asset('images/favicon-32.png') }}?v=brand4">
    <link rel="apple-touch-icon" sizes="180x180" href="{{ asset('images/apple-touch-icon.png') }}?v=brand4">
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    <link rel="manifest" href="{{ route('admin.manifest') }}">
    <meta name="theme-color" content="#0f1825">
    <link href="https://fonts.googleapis.com/css2?family=Manrope:wght@400;500;600;700;800&family=Inter:wght@400;500;600;700&family=Montserrat:wght@600;700&display=swap" rel="stylesheet">
    <link href="https://cdn.jsdelivr.net/npm/simple-datatables@9.0.3/dist/style.css" rel="stylesheet">
    <link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css"/>
    <link rel="stylesheet" href="{{ asset('css/admin.css') }}?v={{ filemtime(public_path('css/admin.css')) }}">
    @stack('styles')
</head>
<body class="@yield('body_class')">
<div class="adm-overlay" id="adm-overlay" onclick="admCloseSidebar()"></div>
<div class="adm-loader-modal" id="adm-loader-modal" aria-live="polite" aria-busy="true" hidden>
    <div class="adm-loader-card" role="status">
        <div class="adm-loader-orbit" aria-hidden="true">
            <span></span>
            <span></span>
            <span></span>
        </div>
        <strong id="adm-loader-title">Загружаем</strong>
        <p id="adm-loader-detail">Пожалуйста, подождите несколько секунд.</p>
        <div class="adm-loader-bar" aria-hidden="true"><span></span></div>
    </div>
</div>
<div class="adm-layout">
    <aside class="adm-sidebar" id="adm-sidebar">
        <div class="adm-sidebar-header">
            <a href="{{ route('admin.dashboard') }}" class="adm-brand">
                <img src="{{ asset('images/logo-mark.png') }}?v=brand4" alt="Auralith">
                <span>Auralith Admin</span>
            </a>
            <button class="adm-hamburger adm-close-btn" onclick="admCloseSidebar()" aria-label="Закрыть меню">
                <svg viewBox="0 0 24 24" fill="none" width="16" height="16">
                    <path d="M18 6L6 18M6 6l12 12" stroke="currentColor" stroke-width="2" stroke-linecap="round"/>
                </svg>
            </button>
        </div>

        <nav class="adm-nav">
            <a href="{{ route('admin.dashboard') }}"
               class="adm-link {{ request()->routeIs('admin.dashboard') ? 'active' : '' }}">
                <svg viewBox="0 0 24 24" fill="none"><rect x="3" y="3" width="7" height="7" rx="1.5" stroke="currentColor" stroke-width="1.7"/><rect x="14" y="3" width="7" height="7" rx="1.5" stroke="currentColor" stroke-width="1.7"/><rect x="3" y="14" width="7" height="7" rx="1.5" stroke="currentColor" stroke-width="1.7"/><rect x="14" y="14" width="7" height="7" rx="1.5" stroke="currentColor" stroke-width="1.7"/></svg>
                <span>Dashboard</span>
            </a>
            <a href="{{ route('admin.car-cards.index') }}"
               class="adm-link {{ request()->routeIs('admin.car-cards.*') ? 'active' : '' }}">
                <svg viewBox="0 0 24 24" fill="none"><path d="M4 7h16v10H4V7Z" stroke="currentColor" stroke-width="1.7" stroke-linejoin="round"/><path d="M7 10h4v4H7v-4Zm7 0h3m-3 3h3M8 20h8" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"/></svg>
                <span>Авто QR</span>
            </a>
            @foreach($resources as $key => $resource)
                @if($resource['hidden'] ?? false)
                    @continue
                @endif
                <a href="{{ route('admin.resource.index', $key) }}"
                   class="adm-link {{ request()->is('admin/'.$key.'*') ? 'active' : '' }}">
                    @php
                        $icons = [
                            'users'         => '<svg viewBox="0 0 24 24" fill="none"><circle cx="9" cy="7" r="4" stroke="currentColor" stroke-width="1.7"/><path d="M2 21v-1a7 7 0 0114 0v1" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"/><path d="M16 3.13a4 4 0 010 7.75M22 21v-1a4 4 0 00-3-3.87" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"/></svg>',
                            'plans'         => '<svg viewBox="0 0 24 24" fill="none"><path d="M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"/></svg>',
                            'nodes'         => '<svg viewBox="0 0 24 24" fill="none"><circle cx="12" cy="12" r="3" stroke="currentColor" stroke-width="1.7"/><path d="M12 2v3m0 14v3M2 12h3m14 0h3m-3.5-7.5-2.1 2.1M6.6 17.4l-2.1 2.1m0-13.1 2.1 2.1m8.7 8.7 2.1 2.1" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"/></svg>',
                            'subscriptions' => '<svg viewBox="0 0 24 24" fill="none"><path d="M12 2l3.09 6.26L22 9.27l-5 4.87 1.18 6.88L12 17.77l-6.18 3.25L7 14.14 2 9.27l6.91-1.01L12 2z" stroke="currentColor" stroke-width="1.7" stroke-linejoin="round"/></svg>',
                            'orders'        => '<svg viewBox="0 0 24 24" fill="none"><rect x="2" y="5" width="20" height="14" rx="2" stroke="currentColor" stroke-width="1.7"/><path d="M2 10h20" stroke="currentColor" stroke-width="1.7"/></svg>',
                            'promo_codes'   => '<svg viewBox="0 0 24 24" fill="none"><path d="M20 12v8a2 2 0 01-2 2H6a2 2 0 01-2-2v-8M2 7h20v5H2V7zM12 22V7M12 7H8.5a2.5 2.5 0 110-5C12 2 12 7 12 7zm0 0h3.5a2.5 2.5 0 100-5C12 2 12 7 12 7z" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"/></svg>',
                        ];
                        $icon = $icons[$key] ?? '<svg viewBox="0 0 24 24" fill="none"><circle cx="12" cy="12" r="9" stroke="currentColor" stroke-width="1.7"/></svg>';
                    @endphp
                    {!! $icon !!}
                    <span>{{ $resource['title'] }}</span>
                </a>
            @endforeach
            <a href="{{ route('admin.logs') }}"
               class="adm-link {{ request()->routeIs('admin.logs') ? 'active' : '' }}">
                <svg viewBox="0 0 24 24" fill="none"><path d="M8 7h8M8 12h8M8 17h6" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"/><rect x="4" y="3" width="16" height="18" rx="2" stroke="currentColor" stroke-width="1.7"/></svg>
                <span>Журнал</span>
            </a>
            <a href="{{ route('admin.system.index') }}"
               class="adm-link {{ request()->routeIs('admin.system.*') ? 'active' : '' }}">
                <svg viewBox="0 0 24 24" fill="none"><path d="M4 7h16M4 12h10M4 17h7" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"/><path d="M17 15l2 2 3-4" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"/></svg>
                <span>Система</span>
            </a>
            <a href="{{ route('admin.diagnostics') }}"
               class="adm-link {{ request()->routeIs('admin.diagnostics') || request()->routeIs('admin.support.*') ? 'active' : '' }}">
                <svg viewBox="0 0 24 24" fill="none"><path d="M4 5h16v11H4V5Z" stroke="currentColor" stroke-width="1.7" stroke-linejoin="round"/><path d="M8 20h8M12 16v4M8 9h3M8 12h6M17 9h.01" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"/></svg>
                <span>Диагностика</span>
            </a>
            <a href="{{ route('admin.settings.index') }}"
               class="adm-link {{ request()->routeIs('admin.settings.*') ? 'active' : '' }}">
                <svg viewBox="0 0 24 24" fill="none"><circle cx="12" cy="12" r="3" stroke="currentColor" stroke-width="1.7"/><path d="M19.4 15a1.7 1.7 0 00.34 1.87l.06.06a2 2 0 01-2.83 2.83l-.06-.06a1.7 1.7 0 00-1.87-.34 1.7 1.7 0 00-1 1.55V21a2 2 0 01-4 0v-.09a1.7 1.7 0 00-1-1.55 1.7 1.7 0 00-1.87.34l-.06.06a2 2 0 01-2.83-2.83l.06-.06A1.7 1.7 0 004.6 15a1.7 1.7 0 00-1.55-1H3a2 2 0 010-4h.09a1.7 1.7 0 001.55-1 1.7 1.7 0 00-.34-1.87l-.06-.06a2 2 0 012.83-2.83l.06.06A1.7 1.7 0 009 4.6a1.7 1.7 0 001-1.55V3a2 2 0 014 0v.09a1.7 1.7 0 001 1.55 1.7 1.7 0 001.87-.34l.06-.06a2 2 0 012.83 2.83l-.06.06A1.7 1.7 0 0019.4 9c.21.6.78 1 1.42 1H21a2 2 0 010 4h-.09c-.64 0-1.21.4-1.51 1z" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"/></svg>
                <span>Настройки</span>
            </a>
        </nav>

        <form method="post" action="{{ route('admin.logout') }}" class="adm-logout-form">
            @csrf
            <button type="submit" class="adm-logout-btn">
                <svg viewBox="0 0 24 24" fill="none"><path d="M17 16l4-4m0 0l-4-4m4 4H7m6 4v1a3 3 0 01-3 3H6a3 3 0 01-3-3V7a3 3 0 013-3h4a3 3 0 013 3v1" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"/></svg>
                <span>Выйти</span>
            </button>
        </form>
    </aside>

    <main class="adm-main">
        {{-- Mobile open button --}}
        <button class="adm-hamburger adm-hamburger--open" onclick="admToggleSidebar()" aria-label="Открыть меню">
            <svg viewBox="0 0 24 24" fill="none" width="16" height="16">
                <path d="M4 6h16M4 12h16M4 18h16" stroke="currentColor" stroke-width="2" stroke-linecap="round"/>
            </svg>
        </button>
        {{-- Health / Node monitoring bar --}}
        <div class="health-bar">
            <div class="health-bar-stats">
                <strong>Ноды:</strong>
                <span class="health-stat">
                    Alive <span id="hb-alive">{{ $serverHealth['alive_nodes'] }}/{{ $serverHealth['total_nodes'] }}</span>
                </span>
                <span class="health-stat">
                    Avg Load <span id="hb-avg-load">{{ $serverHealth['avg_load_percent'] }}%</span>
                </span>
            </div>
            <div class="health-bar-nodes">
                @foreach(collect($serverHealth['nodes'])->reject(fn($n) => $n['hidden_on_dashboard'] ?? false) as $n)
                @php
                    $alive = $n['status'] === 'alive';
                    $nName = strtoupper($n['name']);
                    if (preg_match('/^NL\d*$/', $nName) || str_starts_with($nName, 'NETHER') || str_starts_with($nName, 'AMS')) {
                        $nodeCode = 'NL';
                    } elseif (preg_match('/^DE\d*$/', $nName) || str_starts_with($nName, 'GERMANY') || str_starts_with($nName, 'FRANKFURT')) {
                        $nodeCode = 'DE';
                    } elseif (preg_match('/^FI\d*$/', $nName) || preg_match('/^FIN\d*$/', $nName) || str_starts_with($nName, 'FINLAND') || str_starts_with($nName, 'HELSINKI')) {
                        $nodeCode = 'FI';
                    } elseif (preg_match('/^UK\d*$/', $nName) || preg_match('/^GB\d*$/', $nName) || str_starts_with($nName, 'LONDON') || str_starts_with($nName, 'UNITED')) {
                        $nodeCode = 'GB';
                    } elseif (preg_match('/^TR\d*$/', $nName) || str_starts_with($nName, 'TURKEY') || str_starts_with($nName, 'ISTANBUL')) {
                        $nodeCode = 'TR';
                    } else {
                        $nodeCode = $n['name'];
                    }
                @endphp
                <span class="node-chip {{ $alive ? 'alive' : 'dead' }}"
                      data-node-code="{{ $nodeCode }}"
                      data-node-name="{{ $n['name'] }}"
                      onclick="admFocusNode('{{ $nodeCode }}');"
                      title="{{ $n['name'] }} · {{ $alive ? 'ALIVE' : 'DEAD' }} · {{ $n['load_percent'] }}% load{{ isset($n['latency']) && $n['latency'] ? ' · '.$n['latency'].' ms' : '' }}">
                    <span class="node-chip__dot"></span>
                    {{ $n['name'] }}
                    <span class="hb-load" style="opacity:.7">{{ $n['load_percent'] }}%</span>
                    @if(isset($n['latency']) && $n['latency'])
                        <span class="hb-latency" style="opacity:.55">{{ $n['latency'] }}ms</span>
                    @else
                        <span class="hb-latency" style="opacity:.55"></span>
                    @endif
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

        {{-- WebAuthn registration prompt --}}
        <div id="webauthn-prompt" style="display:none;background:rgba(79,126,181,.1);border:1px solid rgba(79,126,181,.25);border-radius:12px;padding:14px 18px;margin-bottom:20px;align-items:center;justify-content:space-between;gap:12px;flex-wrap:wrap">
            <div>
                <strong style="font-size:.9rem">Включить вход по отпечатку / Face ID</strong>
                <p style="margin:2px 0 0;color:var(--muted);font-size:.8rem">Быстрый вход без пароля на этом устройстве</p>
            </div>
            <div style="display:flex;gap:8px">
                <button onclick="registerWebAuthn()" style="padding:7px 16px;background:rgba(79,126,181,.2);border:1px solid rgba(79,126,181,.4);border-radius:8px;color:#6b93c0;font-size:.83rem;font-weight:600;cursor:pointer">Включить</button>
                <button onclick="dismissWebAuthnPrompt()" style="padding:7px 12px;background:transparent;border:1px solid var(--line);border-radius:8px;color:var(--muted);font-size:.83rem;cursor:pointer">Позже</button>
            </div>
        </div>

        <script>
        // Show WebAuthn registration prompt if supported and not dismissed
        (async function() {
            if (!window.PublicKeyCredential) return;
            if (localStorage.getItem('webauthn_dismissed_{{ session("admin_id") }}')) return;
            if (localStorage.getItem('webauthn_registered_{{ session("admin_id") }}')) return;
            // Check if platform authenticator available
            const available = await PublicKeyCredential.isUserVerifyingPlatformAuthenticatorAvailable().catch(() => false);
            if (!available) return;
            const el = document.getElementById('webauthn-prompt');
            if (el) el.style.display = 'flex';
        })();

        function dismissWebAuthnPrompt() {
            localStorage.setItem('webauthn_dismissed_{{ session("admin_id") }}', '1');
            document.getElementById('webauthn-prompt').style.display = 'none';
        }

        async function registerWebAuthn() {
            const prompt = document.getElementById('webauthn-prompt');
            window.admShowLoader?.('Подключаем вход', 'Ожидаем подтверждение устройства и сохраняем ключ.');
            try {
                const cr = await fetch('{{ route("admin.webauthn.register.challenge") }}', {
                    method: 'POST',
                    headers: {'X-CSRF-TOKEN': '{{ csrf_token() }}', 'Accept': 'application/json'}
                });
                const opts = await cr.json();

                const credential = await navigator.credentials.create({
                    publicKey: {
                        challenge: base64ToBuffer(opts.challenge),
                        rp: opts.rp,
                        user: {
                            id: base64ToBuffer(opts.user.id),
                            name: opts.user.name,
                            displayName: opts.user.displayName,
                        },
                        pubKeyCredParams: opts.pubKeyCredParams,
                        timeout: opts.timeout,
                        authenticatorSelection: opts.authenticatorSelection,
                        attestation: opts.attestation,
                    }
                });

                // Use attestationObject as public_key storage (contains all needed data)
                const publicKeyData = bufferToBase64(credential.response.attestationObject);
                const deviceName = /iPhone|iPad/.test(navigator.userAgent) ? 'iPhone/iPad'
                    : /Android/.test(navigator.userAgent) ? 'Android'
                    : 'Desktop';

                const vr = await fetch('{{ route("admin.webauthn.register.verify") }}', {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json',
                        'X-CSRF-TOKEN': '{{ csrf_token() }}',
                        'Accept': 'application/json',
                    },
                    body: JSON.stringify({
                        credential_id: bufferToBase64(credential.rawId),
                        public_key:    publicKeyData,
                        device_name:   deviceName,
                    }),
                });

                const result = await vr.json();
                if (result.ok) {
                    prompt.style.display = 'none';
                    localStorage.setItem('webauthn_registered_{{ session("admin_id") }}', '1');
                    // Show success inline
                    const s = document.createElement('div');
                    s.style.cssText = 'background:rgba(74,222,128,.1);border:1px solid rgba(74,222,128,.3);border-radius:12px;padding:12px 18px;margin-bottom:20px;color:#4ade80;font-size:.88rem';
                    s.textContent = '✓ Биометрия настроена. Теперь можно входить по отпечатку.';
                    prompt.parentNode.insertBefore(s, prompt);
                } else {
                    alert('Ошибка сервера: ' + JSON.stringify(result));
                }
            } catch(e) {
                alert('Ошибка: ' + e.name + ' — ' + e.message);
            } finally {
                window.admHideLoader?.();
            }
        }

        function base64ToBuffer(base64) {
            const b = base64.replace(/-/g,'+').replace(/_/g,'/');
            const bin = atob(b);
            const buf = new Uint8Array(bin.length);
            for (let i = 0; i < bin.length; i++) buf[i] = bin.charCodeAt(i);
            return buf.buffer;
        }
        function bufferToBase64(buffer) {
            if (!buffer) return '';
            const bytes = new Uint8Array(buffer);
            let str = '';
            for (const b of bytes) str += String.fromCharCode(b);
            return btoa(str).replace(/\+/g,'-').replace(/\//g,'_').replace(/=/g,'');
        }
        </script>

        @yield('content')
    </main>
</div>

<script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.3/dist/chart.umd.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/simple-datatables@9.0.3"></script>
<script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>
<script src="{{ asset('js/admin-dashboard.js') }}?v={{ filemtime(public_path('js/admin-dashboard.js')) }}"></script>
<script>
    // Start live polling for node health (15s interval)
    admStartPolling('{{ route('admin.api.nodes.health') }}');
</script>
@stack('scripts')
<script>
function admShowLoader(title, detail) {
    const modal = document.getElementById('adm-loader-modal');
    const titleEl = document.getElementById('adm-loader-title');
    const detailEl = document.getElementById('adm-loader-detail');
    if (!modal) return;

    if (titleEl) titleEl.textContent = title || 'Загружаем';
    if (detailEl) detailEl.textContent = detail || 'Пожалуйста, подождите несколько секунд.';
    modal.hidden = false;
    document.body.classList.add('adm-loading');
}

function admHideLoader() {
    const modal = document.getElementById('adm-loader-modal');
    if (!modal) return;

    modal.hidden = true;
    document.body.classList.remove('adm-loading');
}

window.admShowLoader = admShowLoader;
window.admHideLoader = admHideLoader;

function admToggleSidebar() {
    document.getElementById('adm-sidebar').classList.toggle('open');
    document.getElementById('adm-overlay').classList.toggle('open');
}
function admCloseSidebar() {
    document.getElementById('adm-sidebar').classList.remove('open');
    document.getElementById('adm-overlay').classList.remove('open');
}
// Close sidebar on nav link click (mobile)
document.querySelectorAll('.adm-link').forEach(function(el) {
    el.addEventListener('click', admCloseSidebar);
});

document.addEventListener('submit', function(event) {
    const form = event.target.closest('form');
    if (!form || form.dataset.noLoader === '1') return;

    setTimeout(function() {
        if (event.defaultPrevented) return;

        const method = (form.getAttribute('method') || 'GET').toUpperCase();
        const title = form.dataset.loaderTitle || (method === 'GET' ? 'Загружаем данные' : 'Выполняем действие');
        const detail = form.dataset.loaderDetail || 'Запрос уже ушёл на сервер.';
        admShowLoader(title, detail);
    }, 0);
});

document.addEventListener('click', function(event) {
    const link = event.target.closest('a[href]');
    if (!link || link.dataset.noLoader === '1') return;
    if (event.defaultPrevented || event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
    if (link.target && link.target !== '_self') return;
    if (link.hasAttribute('download')) return;

    const href = link.getAttribute('href') || '';
    if (!href || href.startsWith('#') || href.startsWith('javascript:') || href.startsWith('mailto:') || href.startsWith('tel:')) return;

    const url = new URL(link.href, window.location.href);
    if (url.origin !== window.location.origin) return;

    admShowLoader(link.dataset.loaderTitle || 'Открываем раздел', link.dataset.loaderDetail || 'Готовим страницу админки.');
});
</script>
</body>
</html>
