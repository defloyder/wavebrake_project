@extends('layout')

@section('title', 'WAVEBREAK - кабинет')
@section('body_class', 'wb-dashboard-body')

@section('content')
@php
    $section = $section ?? 'overview';
    $email = $me['email'] ?? 'user@wavebreak.local';
    $hasSubscription = (bool) $subscription;
    $activeConnections = collect($grants)->where('status', 'active')->count();
    $activeDevices = collect($devices ?? [])->filter(fn ($device) => empty($device['revoked_at']))->count();
    $telegramIdentities = collect($overview['telegram'] ?? [])->where('provider', 'telegram');
    $usedBytes = (int) ($usage['bytes_total'] ?? 0);
    $limitBytes = $usage['limit_bytes'] ?? null;
    $usagePercent = $usage['percent_used'] ?? null;
    $planById = collect($plans)->keyBy('id');
    $currentPlan = $hasSubscription ? $planById->get($subscription['plan_id'] ?? '') : null;
    $titles = [
        'overview' => 'Личный кабинет',
        'subscription' => 'Подписка',
        'access' => 'Подключения',
        'devices' => 'Устройства',
    ];
@endphp

<div class="wb-overlay" id="wb-overlay"></div>
<div class="wb-app-layout">
    <aside class="wb-sidebar" id="wb-sidebar">
        <a href="/" class="wb-brand" aria-label="WAVEBREAK">
            <img src="{{ asset('images/wavebreak-logo.png') }}" class="wb-logo" alt="">
            <span class="wb-brand-word"><span>WAVEBREAK</span><small>Cabinet</small></span>
        </a>
        <button type="button" class="wb-sidebar-close" id="wb-sidebar-close" aria-label="Закрыть меню">
            <svg viewBox="0 0 24 24" fill="none" width="16" height="16"><path d="M18 6 6 18M6 6l12 12" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></svg>
        </button>

        <div class="wb-user-box">
            <strong>{{ $email }}</strong>
            <span>{{ $me['role'] ?? 'user' }}</span>
        </div>

        <nav class="wb-side-nav" aria-label="Навигация кабинета">
            <a href="/dashboard" class="{{ $section === 'overview' ? 'is-active' : '' }}">
                <svg viewBox="0 0 24 24" fill="none"><path d="M4 10.5 12 4l8 6.5V20H4v-9.5Z" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"/><path d="M9 20v-6h6v6" stroke="currentColor" stroke-width="1.8"/></svg>
                Обзор
            </a>
            <a href="/dashboard/subscription" class="{{ $section === 'subscription' ? 'is-active' : '' }}">
                <svg viewBox="0 0 24 24" fill="none"><path d="M5 5h14v14H5z" stroke="currentColor" stroke-width="1.8"/><path d="M8 9h8M8 13h8M8 17h5" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/></svg>
                Подписка
            </a>
            <a href="/dashboard/access" class="{{ $section === 'access' ? 'is-active' : '' }}">
                <svg viewBox="0 0 24 24" fill="none"><path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10Z" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"/><path d="M9 12l2 2 4-4" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/></svg>
                Подключения
            </a>
            <a href="/dashboard/devices" class="{{ $section === 'devices' ? 'is-active' : '' }}">
                <svg viewBox="0 0 24 24" fill="none"><rect x="6" y="3" width="12" height="18" rx="2.5" stroke="currentColor" stroke-width="1.8"/><path d="M10 18h4" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/></svg>
                Устройства
            </a>
        </nav>

        <form action="/logout" method="post" class="wb-logout">
            @csrf
            <button type="submit">
                <svg viewBox="0 0 24 24" fill="none"><path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4M16 17l5-5-5-5M21 12H9" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/></svg>
                Выйти
            </button>
        </form>
    </aside>

    <main class="wb-app-main">
        <button type="button" class="wb-burger wb-burger--open" id="wb-burger-open" aria-label="Открыть меню">
            <svg viewBox="0 0 24 24" fill="none" width="16" height="16"><path d="M4 6h16M4 12h16M4 18h16" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></svg>
        </button>
        @if (session('success'))
            <div class="wb-alert wb-alert--success">{{ session('success') }}</div>
        @endif
        @if($errors->any())
            <div class="wb-alert">
                @foreach($errors->all() as $error)<p>{{ $error }}</p>@endforeach
            </div>
        @endif

        <div class="wb-app-top">
            <div>
                <p class="wb-kicker">WAVEBREAK Cabinet</p>
                <h1>{{ $titles[$section] ?? 'Личный кабинет' }}</h1>
                <p>Тариф, устройства и подключение — всё в одном месте.</p>
            </div>
            <span class="wb-pill">{{ $hasSubscription ? 'подписка активна' : 'подписка не выбрана' }}</span>
        </div>

        @if($section === 'overview')
            <section class="wb-dashboard-grid">
                <article class="wb-card wb-metric"><strong>{{ $hasSubscription ? 'Активна' : 'Нет' }}</strong><p>Статус подписки</p></article>
                <article class="wb-card wb-metric"><strong>{{ $currentPlan['name'] ?? 'Не выбран' }}</strong><p>Текущий тариф</p></article>
                <article class="wb-card wb-metric"><strong>{{ $activeConnections }}</strong><p>Подключения</p></article>
                <article class="wb-card wb-metric"><strong>{{ $activeDevices }}</strong><p>Устройства</p></article>
            </section>

            <section class="wb-workspace">
                <article class="wb-card">
                    <h3>Готовность доступа</h3>
                    @if($hasSubscription)
                        <p>Подписка активна. Можно выпускать персональные подключения для выбранных серверов доступа.</p>
                        <div class="wb-card-action"><a href="/dashboard/access" class="wb-btn wb-btn--primary">Создать подключение</a></div>
                    @else
                        <p>Выберите тариф, чтобы открыть выдачу подключений и зафиксировать условия обслуживания.</p>
                        <div class="wb-card-action"><a href="/dashboard/subscription" class="wb-btn wb-btn--primary">Выбрать тариф</a></div>
                    @endif
                </article>
                <article class="wb-card">
                    <h3>Использование трафика</h3>
                    <p>{{ number_format($usedBytes / 1073741824, 2) }} GB использовано{{ $limitBytes ? ' из '.number_format($limitBytes / 1073741824, 0).' GB' : '' }}.</p>
                    <div class="wb-card-action"><span class="wb-pill">{{ $usagePercent === null ? 'без лимита' : $usagePercent.'%' }}</span></div>
                </article>
            </section>
        @endif

        @if($section === 'subscription')
            <section class="wb-workspace">
                <article class="wb-card">
                    <h3>Текущая подписка</h3>
                    @if($hasSubscription)
                        <p><strong>Статус:</strong> {{ $subscription['status'] }}</p>
                        <p><strong>Тариф:</strong> {{ $currentPlan['name'] ?? $subscription['plan_id'] }}</p>
                        <p><strong>Период до:</strong> {{ $subscription['current_period_end'] }}</p>
                        <p><strong>Устройства:</strong> {{ $subscription['device_limit_override'] ?? $subscription['device_limit_snapshot'] ?? 'по тарифу' }}</p>
                        <p><strong>Трафик:</strong> {{ $limitBytes ? number_format($limitBytes / 1073741824, 0).' GB' : 'без лимита' }}</p>
                    @else
                        <p>Активной подписки пока нет. Выберите тариф, чтобы открыть выдачу подключений.</p>
                    @endif
                </article>
                <article class="wb-card">
                    <h3>Активировать тариф</h3>
                    @if($hasSubscription)
                        <p>У аккаунта уже есть активная подписка. Можно переходить к выдаче подключений.</p>
                    @else
                        <form method="post" action="/subscriptions" class="wb-form">
                            @csrf
                            <label>Тариф
                                <select name="plan_id" required>
                                    @foreach($plans as $plan)
                                        <option value="{{ $plan['id'] }}">{{ $plan['name'] }} - ${{ number_format($plan['price_cents'] / 100, 2) }} / {{ $plan['interval'] }}</option>
                                    @endforeach
                                </select>
                            </label>
                            <button type="submit" class="wb-btn wb-btn--primary">Активировать</button>
                        </form>
                    @endif
                </article>
            </section>
        @endif

        @if($section === 'access')
            @if(!$hasSubscription)
                <section class="wb-card wb-access-empty">
                    <h3>Сначала нужен тариф</h3>
                    <p>Выберите тариф, чтобы получить подключение.</p>
                    <div class="wb-card-action"><a href="/dashboard/subscription" class="wb-btn wb-btn--primary">Выбрать тариф</a></div>
                </section>
            @elseif($activeGrant && $subLink)
                <section class="wb-connect">
                    <article class="wb-card wb-connect-card">
                        <h3>Ваше подключение готово</h3>
                        <p>Отсканируйте QR-код в приложении или скопируйте ссылку — она обновляется сама, ничего не нужно менять вручную.</p>
                        <div class="wb-qr-wrap">
                            <div id="wb-qr" class="wb-qr"></div>
                        </div>
                        <div class="wb-link-row">
                            <input type="text" readonly value="{{ $subLink }}" id="wb-sub-link" onclick="this.select()">
                            <button type="button" class="wb-btn wb-btn--primary" onclick="navigator.clipboard.writeText(document.getElementById('wb-sub-link').value).then(() => { this.textContent = 'Скопировано'; setTimeout(() => this.textContent = 'Копировать', 1500); })">Копировать</button>
                        </div>
                        <p class="wb-hint">Приложение: <strong>Happ</strong> (iOS/Android) — добавить подписку по этой ссылке.</p>
                        <form method="post" action="/access/grants/{{ $activeGrant['id'] }}/revoke" class="wb-connect-revoke">
                            @csrf
                            <button type="submit" class="wb-link-button">Отключить это подключение</button>
                        </form>
                    </article>
                </section>
                @push('scripts')
                <script src="{{ asset('js/qrcode.min.js') }}"></script>
                <script>
                    new QRCode(document.getElementById('wb-qr'), {
                        text: @json($subLink),
                        width: 176,
                        height: 176,
                        colorDark: '#04111a',
                        colorLight: '#e8fbff',
                    });
                </script>
                @endpush
            @else
                <section class="wb-card wb-access-empty">
                    <h3>Подключение ещё не выпущено</h3>
                    <p>Один клик — и ссылка с QR-кодом будут готовы для вашего устройства.</p>
                    <form method="post" action="/access/grants">
                        @csrf
                        <input type="hidden" name="node_id" value="{{ $primaryNodeId }}">
                        <input type="hidden" name="protocol" value="vless">
                        <button type="submit" class="wb-btn wb-btn--primary" {{ $primaryNodeId ? '' : 'disabled' }}>Получить подключение</button>
                    </form>
                    @unless($primaryNodeId)
                        <p class="wb-hint">Серверы доступа сейчас недоступны, попробуйте чуть позже.</p>
                    @endunless
                </section>
            @endif
        @endif

        @if($section === 'devices')
            <section class="wb-workspace">
                <article class="wb-card">
                    <h3>Добавить устройство</h3>
                    <form method="post" action="/devices" class="wb-form">
                        @csrf
                        <label>Название
                            <input name="name" required placeholder="MacBook / iPhone / Router">
                        </label>
                        <label>Платформа
                            <input name="platform" placeholder="macOS / iOS / Android / Linux">
                        </label>
                        <button type="submit" class="wb-btn wb-btn--primary">Добавить</button>
                    </form>
                </article>
                <article class="wb-card">
                    <h3>Telegram</h3>
                    @if(session('telegram_link_token'))
                        <p><strong>Код привязки:</strong> {{ session('telegram_link_token') }}</p>
                    @elseif($telegramIdentities->isNotEmpty())
                        <p>Telegram подключен: {{ $telegramIdentities->first()['username'] ?? $telegramIdentities->first()['provider_user_id'] }}.</p>
                        <form method="post" action="/telegram">
                            @csrf
                            @method('DELETE')
                            <button type="submit" class="wb-btn">Отвязать Telegram</button>
                        </form>
                    @else
                        <p>Создайте одноразовый код и передайте его в Telegram-бот. После подтверждения бот будет связан с этим аккаунтом.</p>
                        <form method="post" action="/telegram/link">
                            @csrf
                            <button type="submit" class="wb-btn wb-btn--primary">Создать код привязки</button>
                        </form>
                    @endif
                </article>
            </section>

            <section class="wb-card">
                <h3>Устройства аккаунта</h3>
                <div class="wb-table-wrap">
                    <table class="wb-table">
                        <thead><tr><th>Название</th><th>Платформа</th><th>Статус</th><th>Последняя активность</th></tr></thead>
                        <tbody>
                        @forelse($devices ?? [] as $device)
                            <tr>
                                <td>{{ $device['name'] }}</td>
                                <td>{{ $device['platform'] ?? '-' }}</td>
                                <td><span class="wb-pill">{{ empty($device['revoked_at']) ? 'active' : 'revoked' }}</span></td>
                                <td>{{ $device['last_seen_at'] ?? '-' }}</td>
                            </tr>
                        @empty
                            <tr><td colspan="4">Устройства пока не добавлены.</td></tr>
                        @endforelse
                        </tbody>
                    </table>
                </div>
            </section>
        @endif
    </main>
</div>

@push('scripts')
<script>
(() => {
    const sidebar = document.getElementById('wb-sidebar');
    const overlay = document.getElementById('wb-overlay');
    const openBtn = document.getElementById('wb-burger-open');
    const closeBtn = document.getElementById('wb-sidebar-close');
    if (!sidebar || !overlay || !openBtn) return;
    const open = () => { sidebar.classList.add('open'); overlay.classList.add('open'); };
    const close = () => { sidebar.classList.remove('open'); overlay.classList.remove('open'); };
    openBtn.addEventListener('click', open);
    closeBtn?.addEventListener('click', close);
    overlay.addEventListener('click', close);
    sidebar.querySelectorAll('a, button[type="submit"]').forEach((el) => el.addEventListener('click', close));
})();
</script>
@endpush
@endsection
