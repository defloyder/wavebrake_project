@php($active = $active ?? '')

<header class="wb-header">
    <div class="wb-container wb-nav">
        <a href="/" class="wb-brand" aria-label="WAVEBREAK">
            <img src="{{ asset('images/wavebreak-logo.png') }}" class="wb-logo wb-logo-full" alt="">
            <span class="wb-brand-name">WAVEBREAK</span>
        </a>
        <nav class="wb-links" aria-label="Основная навигация">
            <a href="/" class="{{ $active === 'home' ? 'is-active' : '' }}">Главная</a>
            <a href="/pricing" class="{{ $active === 'pricing' ? 'is-active' : '' }}">Тарифы</a>
            <a href="/access" class="{{ $active === 'access' ? 'is-active' : '' }}">Технология</a>
        </nav>
        <div class="wb-actions">
            <a href="/login" class="wb-btn wb-btn--ghost">Войти</a>
            <a href="/register" class="wb-btn wb-btn--primary">Начать</a>
        </div>
    </div>
</header>
