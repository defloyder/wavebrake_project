@php($active = $active ?? '')

<header class="wb-header">
    <div class="wb-container wb-nav">
        <a href="/" class="wb-brand" aria-label="WAVEBREAK">
            <img src="{{ asset('images/wavebreak-logo.png') }}" class="wb-logo wb-logo-full" alt="">
            <span class="wb-brand-name"><span class="wb-brand-wave">WAVE</span><span class="wb-brand-break">BREAK</span></span>
        </a>

        <button type="button" class="wb-burger" id="wb-burger" aria-label="Открыть меню" aria-expanded="false" aria-controls="wb-nav-panel">
            <svg viewBox="0 0 24 24" fill="none"><path d="M4 6h16M4 12h16M4 18h16" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></svg>
        </button>

        <div class="wb-nav-panel" id="wb-nav-panel">
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
    </div>
</header>

<script>
(() => {
    const burger = document.getElementById('wb-burger');
    const panel = document.getElementById('wb-nav-panel');
    if (!burger || !panel) return;
    const close = () => { panel.classList.remove('open'); burger.setAttribute('aria-expanded', 'false'); };
    burger.addEventListener('click', () => {
        const open = panel.classList.toggle('open');
        burger.setAttribute('aria-expanded', open ? 'true' : 'false');
    });
    panel.querySelectorAll('a').forEach((link) => link.addEventListener('click', close));
    document.addEventListener('keydown', (e) => { if (e.key === 'Escape') close(); });
})();
</script>
