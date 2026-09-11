@extends('layout')

@section('title', 'WAVEBREAK - приватный доступ для клиентов и команды')
@section('body_class', 'wb-shell wb-shell--signal')

@section('content')
<header class="wb-header">
    <div class="wb-container wb-nav">
        <a href="/" class="wb-brand" aria-label="WAVEBREAK">
            <img src="{{ asset('images/wavebreak-logo.png') }}" class="wb-logo" alt="">
            <span class="wb-brand-word">
                <span>WAVEBREAK</span>
                <small>Access Platform</small>
            </span>
        </a>
        <nav class="wb-links" aria-label="Основная навигация">
            <a href="/" class="is-active">Главная</a>
            <a href="/pricing">Тарифы</a>
            <a href="/access">Доступ</a>
            <a href="/login">Вход</a>
        </nav>
        <div class="wb-actions">
            <a href="/login" class="wb-btn wb-btn--ghost">Войти</a>
            <a href="/register" class="wb-btn wb-btn--primary">Начать</a>
        </div>
    </div>
</header>

<main>
    <section class="wb-hero wb-hero--signature">
        <div class="wb-container wb-signature-grid">
            <div class="wb-title-panel">
                <p class="wb-kicker">Защищенный доступ</p>
                <h1 class="wb-title-stack">
                    <span>Приватный</span>
                    <span>доступ</span>
                    <span><em>без ручной</em> настройки</span>
                </h1>
                <p class="wb-lead">
                    Клиент выбирает тариф и локацию в кабинете. WAVEBREAK выпускает access grant через Core,
                    отправляет нужное состояние на ноду и показывает, что конфигурация действительно применена.
                </p>
                <div class="wb-hero-actions">
                    <a href="/register" class="wb-btn wb-btn--primary">Создать аккаунт</a>
                    <a href="/pricing" class="wb-btn">Выбрать тариф</a>
                    <a href="/login" class="wb-btn wb-btn--ghost">Войти</a>
                </div>
                <div class="wb-signal-readout" aria-label="Состояние платформы">
                    <span><b>{{ $health['status'] ?? 'offline' }}</b> Core</span>
                    <span><b>{{ count($plans) }}</b> тарифа</span>
                    <span><b>ACK</b> применение</span>
                </div>
            </div>

            <div class="wb-signal-machine" aria-label="Маршрут доступа WAVEBREAK">
                <div class="wb-machine-top">
                    <span class="wb-live">сеть активна</span>
                    <span>core.wavebreak.local</span>
                </div>
                <div class="wb-waveform">
                    @for ($i = 0; $i < 28; $i++)
                        <span style="--i: {{ $i }}"></span>
                    @endfor
                    <img src="{{ asset('images/wavebreak-logo.png') }}" alt="">
                </div>
                <div class="wb-route-badges">
                    <span>вход</span>
                    <span>тариф</span>
                    <span>grant</span>
                    <span>ACK</span>
                </div>
                <div class="wb-terminal wb-terminal--compact">
                    <div class="wb-terminal-bar"><span></span><span></span><span></span></div>
                    <pre><code>register -> subscription -> grant
core outbox -> desired-state
node heartbeat -> applied ack</code></pre>
                </div>
            </div>
        </div>
    </section>

    <section class="wb-section wb-route-section">
        <div class="wb-container">
            <div class="wb-section-head wb-section-head--wide">
                <p class="wb-kicker">Как это работает</p>
                <h2>Клиент нажимает кнопку, инфраструктура применяет доступ</h2>
                <p>
                    Витрина и кабинет работают с тем же Core API, который хранит подписки, ноды и grants.
                    Пользователь видит понятный сценарий, а оператор получает проверяемое состояние системы.
                </p>
            </div>

            <div class="wb-route-board">
                <div class="wb-route-line" aria-hidden="true"></div>
                <article class="wb-route-step">
                    <span class="wb-step-index">01</span>
                    <h3>Регистрация</h3>
                    <p>Email и пароль создают аккаунт в Core. После входа пользователь попадает в кабинет с тарифами и текущим статусом.</p>
                    <a href="/register">Создать аккаунт</a>
                </article>
                <article class="wb-route-step">
                    <span class="wb-step-index">02</span>
                    <h3>Тариф</h3>
                    <p>Подписка определяет уровень доступа. Если тариф не выбран, кабинет сразу ведет пользователя к активации.</p>
                    <a href="/pricing">Смотреть тарифы</a>
                </article>
                <article class="wb-route-step">
                    <span class="wb-step-index">03</span>
                    <h3>Доступ</h3>
                    <p>Пользователь выбирает ноду и протокол. Core выпускает grant для конкретной локации и готовит desired-state.</p>
                    <a href="/dashboard/access">Создать grant</a>
                </article>
                <article class="wb-route-step">
                    <span class="wb-step-index">04</span>
                    <h3>Подтверждение</h3>
                    <p>Node-agent применяет состояние и возвращает heartbeat. Команда видит, что доступ не просто создан, а применен.</p>
                    <a href="/access">Посмотреть схему</a>
                </article>
            </div>
        </div>
    </section>

    <section class="wb-section wb-pricing-lane">
        <div class="wb-container">
            <div class="wb-section-head">
                <p class="wb-kicker">Тарифы</p>
                <h2>Тарифы под разный объем доступа</h2>
                <p>Один человек, постоянная работа или эксплуатация сети: меняется масштаб, но логика выдачи доступа остается единой.</p>
            </div>
            <div class="wb-pricing-grid wb-pricing-grid--signal">
                @forelse($plans as $plan)
                    <article class="wb-card wb-plan-card">
                        <span class="wb-plan-code">{{ strtoupper($plan['code']) }}</span>
                        <h3>{{ $plan['name'] }}</h3>
                        <div class="wb-price">
                            <strong>${{ number_format($plan['price_cents'] / 100, 2) }}</strong>
                            <span>/ {{ $plan['interval'] }}</span>
                        </div>
                        <p>Кабинет, активные ноды и выпуск access grants через Core.</p>
                        <div class="wb-card-action">
                            <a href="/register" class="wb-btn {{ $loop->first ? 'wb-btn--primary' : '' }}">Выбрать</a>
                        </div>
                    </article>
                @empty
                    <article class="wb-card"><h3>Тарифы временно недоступны</h3><p>Core не вернул список планов. Проверьте API и повторите запрос.</p></article>
                @endforelse
            </div>
        </div>
    </section>
</main>
@endsection
