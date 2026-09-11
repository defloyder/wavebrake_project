@extends('layout')

@section('title', 'WAVEBREAK - тарифы')
@section('body_class', 'wb-shell')

@section('content')
<header class="wb-header">
    <div class="wb-container wb-nav">
        <a href="/" class="wb-brand" aria-label="WAVEBREAK">
            <img src="{{ asset('images/wavebreak-logo.png') }}" class="wb-logo" alt="">
            <span class="wb-brand-word"><span>WAVEBREAK</span><small>Access Platform</small></span>
        </a>
        <nav class="wb-links" aria-label="Основная навигация">
            <a href="/">Главная</a>
            <a href="/pricing" class="is-active">Тарифы</a>
            <a href="/access">Доступ</a>
            <a href="/login">Вход</a>
        </nav>
        <div class="wb-actions">
            <a href="/login" class="wb-btn wb-btn--ghost">Войти</a>
            <a href="/register" class="wb-btn wb-btn--primary">Начать</a>
        </div>
    </div>
</header>

<main class="wb-section wb-page-slab">
    <div class="wb-container">
        <div class="wb-section-head">
            <p class="wb-kicker">Тарифы</p>
            <h1 class="wb-page-title">Тариф под ваш объем доступа</h1>
            <p>
                Стартуйте с личного подключения, расширяйте доступ для регулярной работы или управляйте несколькими нодами.
                Подписка активируется в кабинете, а выдача доступа проходит через Core API.
            </p>
        </div>

        <div class="wb-pricing-grid">
            @forelse($plans as $plan)
                @php
                    $code = strtolower($plan['code'] ?? '');
                    if (str_contains($code, 'starter')) {
                        $planCopy = ['Для одного пользователя или тестового запуска.', 'Личный кабинет без лишних экранов', 'Выбор активной ноды', 'Быстрый старт без ручной настройки'];
                    } elseif (str_contains($code, 'plus')) {
                        $planCopy = ['Для постоянного доступа и работы с локациями.', 'Больше места для access grants', 'Удобно переключаться между нодами', 'Хороший вариант для небольшой команды'];
                    } elseif (str_contains($code, 'fleet')) {
                        $planCopy = ['Для эксплуатации, где важны контроль и предсказуемость.', 'Несколько нод в едином контуре', 'Видимость heartbeat и статусов', 'Подходит для рабочих нагрузок'];
                    } else {
                        $planCopy = ['Доступ через WAVEBREAK.', 'Подписка хранится в Core', 'Кабинет выпускает grants', 'Ноды подтверждают применение'];
                    }
                @endphp
                <article class="wb-card wb-plan-card">
                    <span class="wb-plan-code">{{ strtoupper($plan['code']) }}</span>
                    <h3>{{ $plan['name'] }}</h3>
                    <p>{{ $planCopy[0] }}</p>
                    <div class="wb-price">
                        <strong>${{ number_format($plan['price_cents'] / 100, 2) }}</strong>
                        <span>/ {{ $plan['interval'] }}</span>
                    </div>
                    <ul>
                        <li>{{ $planCopy[1] }}</li>
                        <li>{{ $planCopy[2] }}</li>
                        <li>{{ $planCopy[3] }}</li>
                    </ul>
                    <div class="wb-card-action">
                        <a href="/register" class="wb-btn {{ $loop->first ? 'wb-btn--primary' : '' }}">Выбрать тариф</a>
                    </div>
                </article>
            @empty
                <article class="wb-card"><h3>Тарифы временно недоступны</h3><p>Core не вернул список планов. Проверьте состояние API и повторите запрос.</p></article>
            @endforelse
        </div>

        <section class="wb-note-panel">
            <div>
                <p class="wb-kicker">После выбора</p>
                <h2>После выбора открывается выдача доступа</h2>
            </div>
            <p>В кабинете выбирается нода и протокол. Core создает grant, node-agent применяет состояние, а пользователь видит результат без переписок и ручных конфигов.</p>
        </section>
    </div>
</main>
@endsection

