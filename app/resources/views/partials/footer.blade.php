<footer class="site-footer-simple">
    <div class="container footer-bottom">
        <div class="footer-bottom-inner">
            <div class="footer-brand-block">
                <a href="{{ route('home') }}" class="footer-logo">
                    <img src="{{ asset('images/logo-mark.png') }}?v=brand4" alt="Auralith" width="32" height="32">
                    <span>Auralith</span>
                </a>
                <p class="footer-tagline">IT для всех</p>
            </div>

            <div class="footer-nav-block">
                <p class="footer-nav-title">Навигация</p>
                <a href="{{ route('home') }}#pricing" class="footer-nav-link">Тарифы</a>
                <a href="{{ route('home') }}#services" class="footer-nav-link">Услуги</a>
                <a href="{{ route('b2b') }}" class="footer-nav-link">B2B</a>
                <a href="{{ route('faq') }}" class="footer-nav-link">FAQ</a>
                <a href="{{ route('home') }}#contact" class="footer-nav-link">Контакты</a>
                <a href="{{ route('profile.index') }}" class="footer-nav-link">Профиль</a>
            </div>

            <div class="footer-nav-block">
                <p class="footer-nav-title">Контакты</p>
                <a href="https://t.me/auralith_support" target="_blank" class="footer-tg-pill">
                    <svg viewBox="0 0 24 24" width="14" height="14" fill="currentColor"><path d="M11.944 0A12 12 0 0 0 0 12a12 12 0 0 0 12 12 12 12 0 0 0 12-12A12 12 0 0 0 12 0a12 12 0 0 0-.056 0zm4.962 7.224c.1-.002.321.023.465.14a.506.506 0 0 1 .171.325c.016.093.036.306.02.472-.18 1.898-.962 6.502-1.36 8.627-.168.9-.499 1.201-.82 1.23-.696.065-1.225-.46-1.9-.902-1.056-.693-1.653-1.124-2.678-1.8-1.185-.78-.417-1.21.258-1.91.177-.184 3.247-2.977 3.307-3.23.007-.032.014-.15-.056-.212s-.174-.041-.249-.024c-.106.024-1.793 1.14-5.061 3.345-.48.33-.913.49-1.302.48-.428-.008-1.252-.241-1.865-.44-.752-.245-1.349-.374-1.297-.789.027-.216.325-.437.893-.663 3.498-1.524 5.83-2.529 6.998-3.014 3.332-1.386 4.025-1.627 4.476-1.635z"/></svg>
                    Поддержка
                </a>
                <a href="https://t.me/auralith_it" target="_blank" class="footer-tg-pill">
                    <svg viewBox="0 0 24 24" width="14" height="14" fill="currentColor"><path d="M11.944 0A12 12 0 0 0 0 12a12 12 0 0 0 12 12 12 12 0 0 0 12-12A12 12 0 0 0 12 0a12 12 0 0 0-.056 0zm4.962 7.224c.1-.002.321.023.465.14a.506.506 0 0 1 .171.325c.016.093.036.306.02.472-.18 1.898-.962 6.502-1.36 8.627-.168.9-.499 1.201-.82 1.23-.696.065-1.225-.46-1.9-.902-1.056-.693-1.653-1.124-2.678-1.8-1.185-.78-.417-1.21.258-1.91.177-.184 3.247-2.977 3.307-3.23.007-.032.014-.15-.056-.212s-.174-.041-.249-.024c-.106.024-1.793 1.14-5.061 3.345-.48.33-.913.49-1.302.48-.428-.008-1.252-.241-1.865-.44-.752-.245-1.349-.374-1.297-.789.027-.216.325-.437.893-.663 3.498-1.524 5.83-2.529 6.998-3.014 3.332-1.386 4.025-1.627 4.476-1.635z"/></svg>
                    Канал
                </a>
            </div>
        </div>

        <div class="footer-divider"></div>
        <div class="footer-bottom-row">
            <p class="footer-copy">© <span class="footer-year"></span> Auralith. Все права защищены.</p>
            <div class="footer-legal-links">
                <a href="{{ route('offer') }}" class="footer-legal-link">Публичная оферта</a>
                <a href="{{ route('privacy_policy') }}" class="footer-legal-link">Политика конфиденциальности</a>
            </div>
        </div>
        <p class="footer-requisites">ИП Пустовойтов П.А. &nbsp;·&nbsp; ИНН: 772972664547 &nbsp;·&nbsp; ОГРНИП: 326774600310655</p>
    </div>
</footer>
<script>document.querySelectorAll('.footer-year').forEach(el => el.textContent = new Date().getFullYear());</script>
