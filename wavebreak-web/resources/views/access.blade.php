@extends('layout')

@section('title', 'WAVEBREAK - маршрут доступа')
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
            <a href="/pricing">Тарифы</a>
            <a href="/access" class="is-active">Доступ</a>
            <a href="/login">Вход</a>
        </nav>
        <div class="wb-actions">
            <a href="/login" class="wb-btn wb-btn--ghost">Войти</a>
            <a href="/register" class="wb-btn wb-btn--primary">Начать</a>
        </div>
    </div>
</header>

<main>
    <section class="wb-hero">
        <div class="wb-container wb-hero-grid">
            <div>
                <p class="wb-kicker">Маршрут доступа</p>
                <h1>Доступ выдается из кабинета и доходит до ноды</h1>
                <p class="wb-lead">
                    Пользователь выбирает локацию и протокол, а Core выпускает grant и передает новое состояние агенту.
                    Кабинет показывает не обещание доступа, а результат применения.
                </p>
                <div class="wb-hero-actions">
                    <a href="/register" class="wb-btn wb-btn--primary">Создать аккаунт</a>
                    <a href="/login" class="wb-btn">Войти в кабинет</a>
                </div>
            </div>
            <div class="wb-board">
                <div class="wb-board-top">
                    <span class="wb-live">готово к выдаче</span>
                    <strong>Laravel Web -> Core -> Node</strong>
                    <span class="wb-pill">{{ $health['status'] ?? 'status' }}</span>
                </div>
                <div class="wb-canvas">
                    <span class="wb-map-line"></span>
                    <span class="wb-map-line"></span>
                    <span class="wb-map-line"></span>
                    <span class="wb-node wb-node--core"><span class="wb-dot"></span>Auth</span>
                    <span class="wb-node wb-node--access"><span class="wb-dot"></span>Grant</span>
                    <span class="wb-node wb-node--edge"><span class="wb-dot"></span>ACK</span>
                    <span class="wb-core-mark"><img src="{{ asset('images/wavebreak-logo.png') }}" alt=""></span>
                </div>
                <div class="wb-terminal">
                    <div class="wb-terminal-bar"><span></span><span></span><span></span></div>
                    <pre><code>POST /subscriptions
POST /access/grants
desired-state -> node ack</code></pre>
                </div>
            </div>
        </div>
    </section>

    <section class="wb-section wb-page-slab">
        <div class="wb-container">
            <div class="wb-feature-grid">
                <article class="wb-card">
                    <h3>Профиль и тариф</h3>
                    <p>Кабинет получает данные аккаунта и подписку из Core. Если тариф не активен, пользователь видит, что нужно сделать дальше.</p>
                </article>
                <article class="wb-card">
                    <h3>Локация и протокол</h3>
                    <p>Core возвращает доступные ноды со статусами. Пользователь выбирает подходящую локацию и нужный способ подключения.</p>
                </article>
                <article class="wb-card">
                    <h3>Применение на ноде</h3>
                    <p>Node-agent получает desired-state, применяет конфигурацию и отправляет heartbeat с актуальной ревизией.</p>
                </article>
            </div>
        </div>
    </section>
</main>
@endsection

