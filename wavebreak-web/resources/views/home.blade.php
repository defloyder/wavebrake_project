@extends('layout')

@section('title', 'WAVEBREAK - защищенная инфраструктура для бизнеса')
@section('description', 'WAVEBREAK собирает тарифы, серверы доступа и внешние ссылки подключения в одном спокойном приложении для бизнеса и личных рабочих профилей.')
@section('body_class', 'wb-shell wb-public wb-art-page')

@push('schema')
<script type="application/ld+json">
{
  "@@context": "https://schema.org",
  "@@type": "Organization",
  "name": "WAVEBREAK",
  "url": "{{ rtrim(config('app.url'), '/') }}",
  "logo": "{{ asset('images/wavebreak-logo.png') }}",
  "description": "Защищенная инфраструктура для бизнеса: кабинет, тарифы, серверы доступа и внешние ссылки подключения."
}
</script>
@endpush

@section('content')
@include('partials.public-header', ['active' => 'home'])

<main class="art-site">
    <section class="art-hero" id="top">
        <div class="art-noise" aria-hidden="true"></div>

        <div class="wb-container art-hero-grid">
            <div class="art-copy" data-reveal>
                <p class="art-kicker">WAVEBREAK</p>
                <h1>Тише. Понятнее. Под контролем.</h1>
                <p>
                    Защищенный доступ, тарифы и рабочие профили в одном приложении.
                    Без лишнего шума. Без ручной суеты.
                </p>
                <div class="art-actions">
                    <a href="/register" class="wb-btn wb-btn--primary">Начать</a>
                    <a href="#reveal" class="wb-btn">Раскрыть</a>
                    <a href="/login" class="wb-btn wb-btn--ghost">Войти</a>
                </div>
            </div>

            <div class="art-square-scene" aria-label="WAVEBREAK" data-reveal data-reveal-delay="120">
                <div class="art-square">
                    <img src="{{ asset('images/wavebreak-logo.png') }}" alt="WAVEBREAK">
                    <span class="art-cut art-cut--one" aria-hidden="true"></span>
                    <span class="art-cut art-cut--two" aria-hidden="true"></span>
                </div>
                <p>одна точка входа</p>
            </div>
        </div>

        <div class="art-wave-floor" aria-hidden="true">
            <span></span>
            <span></span>
            <span></span>
        </div>
    </section>

    <section class="art-reveal" id="reveal">
        <div class="wb-container art-reveal-grid" data-reveal>
            <div class="art-index">01</div>
            <div>
                <p class="art-kicker">сначала главное</p>
                <h2>Клиент видит простой путь. Команда видит систему.</h2>
            </div>
            <p>
                WAVEBREAK нужен там, где доступ должен выглядеть как продукт:
                тариф выбран, профиль готов, состояние понятно.
            </p>
        </div>
    </section>

    <section class="art-three">
        <div class="wb-container art-three-grid" data-reveal="stagger">
            <article>
                <span>01</span>
                <h3>Свой сервис</h3>
                <p>Тарифы, локации и выдача профиля в личном кабинете.</p>
            </article>
            <article>
                <span>02</span>
                <h3>Свои ссылки</h3>
                <p>Внешние ссылки подключения остаются внутри приложения.</p>
            </article>
            <article>
                <span>03</span>
                <h3>Контроль</h3>
                <p>Статусы, активные подключения и серверы доступа видны команде.</p>
            </article>
        </div>
    </section>

    <section class="art-details">
        <div class="wb-container art-details-grid" data-reveal>
            <div>
                <p class="art-kicker">глубже</p>
                <h2>Если нужно больше, сайт раскрывается.</h2>
            </div>
            <div class="art-accordion">
                <details open>
                    <summary>Для бизнеса</summary>
                    <p>Запускаете тарифы, показываете клиенту понятный кабинет и убираете ручную сборку каждого подключения.</p>
                </details>
                <details>
                    <summary>Для личного использования</summary>
                    <p>Добавляете внешние ссылки от разных продавцов и держите рабочие профили в одном месте.</p>
                </details>
                <details>
                    <summary>Для команды</summary>
                    <p>Видите локации, статусы и активность без хаоса в чатах, таблицах и заметках.</p>
                </details>
            </div>
        </div>
    </section>

    <section class="art-final">
        <div class="wb-container" data-reveal>
            <h2>WAVEBREAK оставляет на экране только то, что нужно.</h2>
            <a href="/register" class="wb-btn wb-btn--primary">Начать</a>
        </div>
    </section>
</main>

<footer class="art-footer">
    <div class="wb-container art-footer-grid">
        <img src="{{ asset('images/wavebreak-logo.png') }}" alt="WAVEBREAK">
        <nav aria-label="Нижняя навигация">
            <a href="/">Главная</a>
            <a href="/pricing">Тарифы</a>
            <a href="/access">Инфраструктура</a>
            <a href="/login">Вход</a>
        </nav>
        <span>© {{ date('Y') }}</span>
    </div>
</footer>
@endsection
