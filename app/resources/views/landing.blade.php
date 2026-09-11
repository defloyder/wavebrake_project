<!DOCTYPE html>
<html lang="ru" prefix="og: https://ogp.me/ns#">
<head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />

    {{-- Primary SEO --}}
    <title>Auralith / Ауралит — защищённый доступ, тарифы и IT-инфраструктура для бизнеса</title>
    <meta name="description" content="Auralith, Ауралит — защищённый интернет-доступ с тарифами от 169 ₽ и B2B-сопровождение IT-инфраструктуры: аудит, отказоустойчивость, мониторинг и поддержка." />
    <meta name="keywords" content="Auralith, Ауралит, ауралит, auralit, auralith vpn, защищенный доступ, защищённый интернет, тарифы Auralith, IT инфраструктура для бизнеса, HA архитектура, Telegram бот Auralith" />
    <meta name="author" content="Auralith" />
    <meta name="robots" content="index, follow, max-snippet:-1, max-image-preview:large, max-video-preview:-1" />
    <link rel="canonical" href="https://auralith.ru/" />

    {{-- Open Graph --}}
    <meta property="og:type" content="website" />
    <meta property="og:url" content="https://auralith.ru/" />
    <meta property="og:title" content="Auralith / Ауралит — защищённый доступ и IT-инфраструктура" />
    <meta property="og:description" content="Тарифы защищённого доступа для пользователей и B2B-решения Auralith для стабильной инфраструктуры." />
    <meta property="og:image" content="https://auralith.ru/images/logo-mark.png" />
    <meta property="og:locale" content="ru_RU" />
    <meta property="og:site_name" content="Auralith" />

    {{-- Twitter Card --}}
    <meta name="twitter:card" content="summary_large_image" />
    <meta name="twitter:title" content="Auralith / Ауралит — тарифы и IT-инфраструктура" />
    <meta name="twitter:description" content="Защищённый доступ, понятные тарифы, Telegram-бот и B2B-сопровождение инфраструктуры." />
    <meta name="twitter:image" content="https://auralith.ru/images/logo-mark.png" />

    {{-- Favicon --}}
    <link rel="icon" type="image/png" sizes="32x32" href="{{ asset('images/favicon-32.png') }}?v=brand4">
    <link rel="apple-touch-icon" sizes="180x180" href="{{ asset('images/apple-touch-icon.png') }}?v=brand4">

    {{-- Schema.org JSON-LD --}}
    <script type="application/ld+json">
    {
        "@@context": "https://schema.org",
        "@@type": "Organization",
        "name": "Auralith",
        "alternateName": ["Ауралит", "Auralit", "Auralith Access"],
        "url": "https://auralith.ru",
        "logo": "https://auralith.ru/images/logo-mark.png",
        "description": "Auralith, Ауралит — сервис защищённого интернет-доступа и сопровождения IT-инфраструктуры.",
        "contactPoint": {
            "@@type": "ContactPoint",
            "contactType": "customer support",
            "availableLanguage": "Russian"
        },
        "sameAs": [
            "https://t.me/auralithaccessbot"
        ]
    }
    </script>

    <script type="application/ld+json">
    {
        "@@context": "https://schema.org",
        "@@type": "WebSite",
        "name": "Auralith",
        "alternateName": ["Ауралит", "Auralit"],
        "url": "https://auralith.ru/",
        "potentialAction": {
            "@@type": "SearchAction",
            "target": "https://auralith.ru/faq?q={search_term_string}",
            "query-input": "required name=search_term_string"
        }
    }
    </script>
    
    <script type="application/ld+json">
    {
        "@@context": "https://schema.org",
        "@@type": "Service",
        "name": "Auralith — доступ к интернету",
        "provider": {
            "@@type": "Organization",
            "name": "Auralith"
        },
        "description": "Стабильный и быстрый доступ к интернету с защитой данных. Серверы в Европе и Азии.",
        "offers": [
            {
                "@@type": "Offer",
                "name": "1 месяц",
                "price": "169",
                "priceCurrency": "RUB"
            },
            {
                "@@type": "Offer",
                "name": "3 месяца",
                "price": "449",
                "priceCurrency": "RUB"
            },
            {
                "@@type": "Offer",
                "name": "1 год",
                "price": "1490",
                "priceCurrency": "RUB"
            }
        ]
    }
    </script>

    {{-- Performance --}}
    <link rel="preconnect" href="https://fonts.googleapis.com" />
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />
    <link href="https://fonts.googleapis.com/css2?family=Manrope:wght@400;500;600;700;800&family=Inter:wght@400;500;600;700&family=Montserrat:wght@600;700&display=swap" rel="stylesheet" />
    <link rel="stylesheet" href="{{ asset('css/landing.css') }}?v=50" />
    <link rel="stylesheet" href="{{ asset('css/faq.css') }}" />
    <link rel="stylesheet" href="{{ asset('css/public-redesign.css') }}?v=28" />
</head>
<body class="home-apple">
<div class="page-glow page-glow-top"></div>
<div class="page-glow page-glow-bottom"></div>

<header class="site-header">
    <div class="container nav">
        <a href="{{ route('home') }}" class="brand" aria-label="Auralith — главная страница">
            <img src="{{ asset('images/logo-mark.png') }}?v=brand4" alt="Auralith логотип" class="brand-logo" width="44" height="44" />
            <span>Auralith</span>
        </a>
        <nav class="nav-links" aria-label="Основная навигация">
            <a href="#pricing">Тарифы</a>
            <a href="#services">Услуги</a>
            <a href="{{ route('b2b') }}">B2B</a>
            <a href="{{ route('faq') }}">FAQ</a>
            <a href="#contact">Контакты</a>
        </nav>
        <a href="{{ route('profile.index') }}" class="profile-icon-btn" aria-label="Открыть профиль" title="Профиль">
            <svg viewBox="0 0 24 24" aria-hidden="true">
                <path d="M20 21a8 8 0 0 0-16 0" />
                <circle cx="12" cy="7" r="4" />
            </svg>
        </a>
    </div>
</header>

<main>
    <section class="hero home-hero">
        <div class="container hero-grid">
            <div class="hero-content">
                <p class="eyebrow">Auralith Access + B2B</p>
                <h1>Доступ, который держит нагрузку</h1>
                <p class="hero-text">
                    Auralith объединяет быстрый защищённый доступ, Core-синхронизацию,
                    Telegram-управление и B2B-сопровождение в одной спокойной системе.
                </p>
                <div class="hero-actions">
                    <a href="#pricing" class="btn btn-primary">Выбрать тариф</a>
                    <a href="{{ route('b2b') }}" class="btn btn-secondary">Решения для бизнеса</a>
                </div>
                <ul class="hero-metrics">
                    <li><strong>Access</strong><span>подключение за минуты</span></li>
                    <li><strong>Core</strong><span>статусы и версии</span></li>
                    <li><strong>B2B</strong><span>аудит и поддержка</span></li>
                </ul>
            </div>

            <div class="hero-panel product-stage">
                <div class="hero-device-glow" aria-hidden="true"></div>
                <div class="hero-status-strip" aria-label="Статус Auralith">
                    <span>Access online</span>
                    <strong>core.auralith.ru</strong>
                    <em>27 ms</em>
                </div>
                <div class="product-orbit-scene" aria-label="Экосистема Auralith">
                    <ul class="space-node-field" aria-hidden="true">
                        @for ($i = 0; $i < 12; $i++)<li></li>@endfor
                    </ul>
                    <div class="traffic-stars" aria-hidden="true">
                        <i class="traffic-star"></i>
                        <i class="traffic-star"></i>
                        <i class="traffic-star"></i>
                        <i class="traffic-star"></i>
                        <i class="traffic-star"></i>
                        <i class="traffic-star"></i>
                    </div>
                    <div class="planet-atmosphere" aria-hidden="true"></div>
                    <div class="planet-shadow" aria-hidden="true"></div>
                    <div class="product-orbit-ring product-orbit-ring--outer"></div>
                    <div class="product-orbit-ring product-orbit-ring--middle"></div>
                    <div class="product-orbit-ring product-orbit-ring--inner"></div>
                    <div class="orbit-track orbit-track--access">
                        <span class="product-node product-node--access"><strong>Access</strong></span>
                    </div>
                    <div class="orbit-track orbit-track--core">
                        <span class="product-node product-node--core"><strong>Core</strong></span>
                    </div>
                    <div class="orbit-track orbit-track--b2b">
                        <span class="product-node product-node--b2b"><strong>B2B</strong></span>
                    </div>
                    <div class="orbit-track orbit-track--traffic" aria-hidden="true">
                        <span class="traffic-packet"></span>
                    </div>
                    <div class="product-core-card">
                        <span class="product-core-card__halo" aria-hidden="true"></span>
                        <img src="{{ asset('images/logo-mark.png') }}?v=brand4" alt="Auralith" />
                    </div>
                </div>
                <div class="terminal">
                    <div class="terminal-head" aria-hidden="true">
                        <i class="terminal-dot"></i>
                        <i class="terminal-dot"></i>
                        <i class="terminal-dot"></i>
                    </div>
                    <pre><code data-type-speed="16">[auralith/infra]$ check-ha
status: warning
reason: single-point-of-failure at app-node-01
advice: introduce failover + backup replication

[auralith/ops]$ run-hardening --profile=prod
firewall: tuned
backup: verified
monitoring: enabled</code></pre>
                </div>
                <ul class="hero-signal-map" aria-hidden="true">
                    <li></li><li></li><li></li><li></li><li></li><li></li>
                </ul>
            </div>
        </div>
    </section>

    {{-- Auralith Access section --}}
    <section class="section access-section" id="access">
        <div class="container">
            <div class="section-head">
                <p class="eyebrow">Auralith Access</p>
                <h2>Защищённый сетевой доступ для стабильной работы</h2>
            </div>
            <div class="access-grid">
                <div class="access-content">
                    <p>Auralith Access — сервис защищённого сетевого доступа с быстрым подключением, стабильными серверами и личным кабинетом.</p>
                    <ul class="access-features">
                        <li>Безлимитный трафик на всех тарифах</li>
                        <li>Персональная subscription URL и QR-код</li>
                        <li>Серверы в Европе и Азии</li>
                        <li>Telegram-бот и уведомления по аккаунту</li>
                        <li>Поддержка Windows, macOS, Linux, iOS и Android</li>
                    </ul>
                </div>
                <div class="access-visual">
                    <div class="access-badge">
                        <svg viewBox="0 0 24 24" fill="none" width="28" height="28">
                            <path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z" stroke="currentColor" stroke-width="1.7" stroke-linejoin="round"/>
                            <path d="M9 12l2 2 4-4" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"/>
                        </svg>
                        <span>Защищено</span>
                    </div>
                    <div class="access-stats">
                        <div class="access-stat">
                            <strong>99.9%</strong>
                            <span>Доступность</span>
                        </div>
                        <div class="access-stat">
                            <strong>&lt;30 мс</strong>
                            <span>Задержка</span>
                        </div>
                        <div class="access-stat">
                            <strong>Безлимит</strong>
                            <span>Трафик</span>
                        </div>
                    </div>
                </div>
            </div>
        </div>
    </section>

    {{-- Pricing section --}}
    <section class="section pricing-section" id="pricing">
        <div class="container">
            <div class="section-head pricing-section-head">
                <p class="eyebrow">Тарифы</p>
                <h2>Выберите тариф Auralith Access</h2>
            </div>
            <div class="pricing-grid">
                @foreach($plans as $plan)
                <div class="pricing-card {{ $plan->is_highlighted ? 'pricing-card--highlight' : '' }}">
                    @if($plan->is_highlighted)
                    <span class="pricing-badge">Популярный</span>
                    @endif
                    <h3>{{ $plan->name }}</h3>
                    <div class="pricing-price">
                        <span class="pricing-amount">₽{{ number_format($plan->price_rub, 0, '.', ' ') }}</span>
                        <span class="pricing-period">/ {{ $plan->duration_months }} {{ $plan->duration_months === 1 ? 'месяц' : ($plan->duration_months < 5 ? 'месяца' : 'месяцев') }}</span>
                    </div>
                    <p class="pricing-headline">{{ $plan->headline }}</p>
                    @if($plan->features)
                    <ul class="pricing-features">
                        @foreach(is_array($plan->features) ? $plan->features : json_decode($plan->features, true) ?? [] as $feature)
                        <li>{{ $feature }}</li>
                        @endforeach
                    </ul>
                    @endif
                    <a href="{{ route('profile.index') }}" class="btn {{ $plan->is_highlighted ? 'btn-primary' : 'btn-secondary' }}">Выбрать план</a>
                </div>
                @endforeach
            </div>
        </div>
    </section>

    <section class="home-story apple-scene" aria-label="Как работает Auralith">
        <div class="container home-story__grid">
            <div class="home-story__sticky">
                <p class="eyebrow">Сценарий подключения</p>
                <h2>Один поток вместо набора ручных действий.</h2>
                <p>
                    Пользователь видит понятный статус, подключает устройство через мастер,
                    получает уведомления и не думает о ручной настройке.
                </p>
                <div class="client-preview" aria-hidden="true">
                    <div class="client-preview__top">
                        <div class="client-preview__brand">
                            <img src="{{ asset('images/logo-mark.png') }}?v=brand4" alt="" />
                            <strong>Auralith Client</strong>
                        </div>
                        <span>RU Access · 5 мс</span>
                    </div>
                    <div class="client-preview__body">
                        <nav class="client-preview__nav">
                            <span class="is-active">Главная</span>
                            <span>Обновления</span>
                            <span>Настройки</span>
                        </nav>
                        <div class="client-preview__status">
                            <div class="client-preview__pulse">
                                <img src="{{ asset('images/logo-mark.png') }}?v=brand4" alt="" />
                            </div>
                            <small>статус</small>
                            <strong>Подключено</strong>
                            <span>Соединение защищено</span>
                            <div class="client-preview__stats">
                                <em>00:48:36</em>
                                <em>TUN</em>
                                <em>Безлимит</em>
                            </div>
                        </div>
                        <aside class="client-preview__side">
                            <div>
                                <small>Режим</small>
                                <strong>TUN</strong>
                            </div>
                            <div>
                                <small>Нода</small>
                                <strong>RU Access</strong>
                            </div>
                            <div>
                                <small>Latency</small>
                                <strong>5 мс</strong>
                            </div>
                        </aside>
                    </div>
                </div>
            </div>
            <div class="home-story__steps">
                <article class="home-story-card">
                    <span>01</span>
                    <h3>Подписка активируется автоматически</h3>
                    <p>Личный кабинет сразу показывает тариф, срок, статус и готовую ссылку подключения.</p>
                </article>
                <article class="home-story-card">
                    <span>02</span>
                    <h3>Устройство подключается без лишних экранов</h3>
                    <p>QR-код, subscription URL и мастер подключения ведут пользователя по короткому пути.</p>
                </article>
                <article class="home-story-card">
                    <span>03</span>
                    <h3>Инфраструктура остаётся под наблюдением</h3>
                    <p>Для компаний доступны аудит, диагностика, мониторинг и план отказоустойчивости.</p>
                </article>
            </div>
        </div>
    </section>

    <section class="section b2b-bridge">
        <div class="container b2b-bridge-inner">
            <div>
                <p class="eyebrow">Для компаний</p>
                <h2>Auralith B2B: аудит, отказоустойчивость и поддержка</h2>
                <p>Проверим инфраструктуру, найдём точки отказа и соберём план, который снижает риск простоя и лишние расходы.</p>
            </div>
            <a href="{{ route('b2b') }}" class="btn btn-secondary">Открыть B2B-решения</a>
        </div>
    </section>

    <section id="services" class="section">
        <div class="container">
            <div class="section-head">
                <p class="eyebrow">Услуги Auralith</p>
                <h2>Минималистичные решения для сложной инфраструктуры</h2>
            </div>
            <div class="cards cards-3">
                <article class="card">
                    <h3>HA-архитектура</h3>
                    <ul>
                        <li>Кластеризация критичных сервисов</li>
                        <li>Failover и балансировка нагрузки</li>
                        <li>Резервирование на уровне сети и БД</li>
                    </ul>
                    <p>HA снижает риск простоя и защищает выручку.</p>
                </article>
                <article class="card">
                    <h3>IT-поддержка 24/7</h3>
                    <ul>
                        <li>Проактивный мониторинг и алерты</li>
                        <li>Реакция по SLA</li>
                        <li>Разбор инцидентов и профилактика</li>
                    </ul>
                    <p>Инциденты решаются быстро, бизнес не останавливается.</p>
                </article>
                <article class="card">
                    <h3>Оптимизация облака</h3>
                    <ul>
                        <li>Аудит ресурсов и тарифов</li>
                        <li>Снижение лишних затрат</li>
                        <li>Рост производительности системы</li>
                    </ul>
                    <p>Платите только за нужные мощности и сохраняете стабильность.</p>
                </article>
            </div>
        </div>
    </section>

    {{-- FAQ section (3 questions) --}}
    <section class="faq-section" id="faq">
        <div class="container">
            <p class="section-eyebrow">Вопросы и ответы</p>
            <h2 class="section-title">Часто задаваемые вопросы</h2>
            <div class="faq-list">
                <div class="faq-item">
                    <button class="faq-q" onclick="toggleFaq(this)">
                        Как быстро активируется подписка после оплаты?
                        <span class="faq-icon">+</span>
                    </button>
                    <div class="faq-a">
                        <p>Подписка активируется автоматически в течение нескольких секунд после подтверждения платежа. Вы получите уведомление в Telegram с данными для подключения к сети.</p>
                    </div>
                </div>
                <div class="faq-item">
                    <button class="faq-q" onclick="toggleFaq(this)">
                        На каких устройствах работает сервис?
                        <span class="faq-icon">+</span>
                    </button>
                    <div class="faq-a">
                        <p>Сервис работает на всех популярных платформах: Windows, macOS, Linux, iOS и Android. Достаточно установить совместимое приложение и добавить вашу персональную конфигурацию.</p>
                    </div>
                </div>
                <div class="faq-item">
                    <button class="faq-q" onclick="toggleFaq(this)">
                        Есть ли ограничения по объёму данных?
                        <span class="faq-icon">+</span>
                    </button>
                    <div class="faq-a">
                        <p>Нет, объём передаваемых данных не ограничен ни на одном из тарифов. Мы следим за стабильностью и равномерной нагрузкой серверов для комфортной работы всех пользователей.</p>
                    </div>
                </div>
            </div>
            <div style="text-align:center;margin-top:32px">
            <a href="{{ route('faq') }}" class="btn btn-secondary btn-with-arrow">Все вопросы<span aria-hidden="true"></span></a>
            </div>
        </div>
    </section>

    <section class="section seo-section" aria-labelledby="seo-auralith-title">
        <div class="container seo-copy seo-copy--compact">
            <p class="eyebrow">Auralith / Ауралит</p>
            <h2 id="seo-auralith-title">Auralith объединяет доступ, кабинет и поддержку в одном месте</h2>
            <div class="seo-copy-grid">
                <p>
                    Пользователь получает личный кабинет, Telegram-бота, QR-код, subscription URL
                    и понятный статус подписки без ручной возни с настройками.
                </p>
                <p>
                    Для компаний есть отдельное направление Auralith B2B: аудит, отказоустойчивость,
                    мониторинг и сопровождение инфраструктуры.
                </p>
            </div>
        </div>
    </section>

</main>

<footer id="contact" class="site-footer">
    <div class="container footer-grid">
        <div>
            <h2>Готовы укрепить инфраструктуру?</h2>
            <p>
                Оставьте запрос - подготовим план по отказоустойчивости, резервированию и поддержке
                вашей платформы.
            </p>
        </div>
        <form class="contact-form" id="contact-form">
            @csrf
            <label>
                Ваше имя
                <input type="text" name="name" placeholder="Имя" required />
            </label>
            <label>
                Email
                <input type="email" name="email" placeholder="name@company.com" required />
            </label>
            <label>
                Задача
                <textarea name="message" rows="4" placeholder="Коротко опишите текущую инфраструктуру"></textarea>
            </label>
            <button type="submit" class="btn btn-primary" id="contact-submit">Отправить запрос</button>
            <div id="contact-success" style="display:none;color:#86efac;font-size:.9rem;text-align:center">
                ✓ Заявка отправлена! Мы свяжемся с вами в ближайшее время.
            </div>
            <div id="contact-error" style="display:none;color:#f87171;font-size:.9rem;text-align:center"></div>
        </form>
    </div>

</footer>

@include('partials.footer')

{{-- Cookie Banner --}}
<div id="cookie-banner" style="display:none;position:fixed;bottom:0;left:0;right:0;z-index:9999;background:rgba(10,15,24,.97);border-top:1px solid rgba(138,148,166,.2);padding:16px 20px;align-items:center;justify-content:space-between;gap:16px;flex-wrap:wrap">
    <p style="margin:0;color:#8a94a6;font-size:.85rem;max-width:600px">
        Мы используем cookies для улучшения работы сайта. Продолжая использование, вы соглашаетесь с нашей
        <a href="#" style="color:#6b93c0">политикой конфиденциальности</a>.
    </p>
    <div style="display:flex;gap:10px;flex-shrink:0">
        <button onclick="acceptCookies()" style="border:0;border-radius:999px;background:linear-gradient(135deg,#4f7eb5,#6b93c0);color:#fff;font-weight:600;padding:.55rem 1.2rem;cursor:pointer;font-size:.85rem">Принять</button>
        <button onclick="declineCookies()" style="border:1px solid rgba(138,148,166,.3);border-radius:999px;background:transparent;color:#8a94a6;padding:.55rem 1rem;cursor:pointer;font-size:.85rem">Отклонить</button>
    </div>
</div>

<script src="{{ asset('js/landing.js') }}?v=8"></script>
<script>
// ── Cookie Banner ──
(function() {
    var consent = localStorage.getItem('cookie_consent');
    if (!consent) {
        var banner = document.getElementById('cookie-banner');
        if (banner) banner.style.display = 'flex';
    }
})();

function acceptCookies() {
    localStorage.setItem('cookie_consent', 'accepted');
    document.getElementById('cookie-banner').style.display = 'none';
}

function declineCookies() {
    localStorage.setItem('cookie_consent', 'declined');
    document.getElementById('cookie-banner').style.display = 'none';
}

// ── Contact Form ──
var contactForm = document.getElementById('contact-form');
if (contactForm) {
    contactForm.addEventListener('submit', function(e) {
        e.preventDefault();
        var btn = document.getElementById('contact-submit');
        var success = document.getElementById('contact-success');
        var error = document.getElementById('contact-error');
        btn.disabled = true;
        btn.textContent = 'Отправка...';
        error.style.display = 'none';

        var formData = new FormData(contactForm);

        fetch('{{ route("contact.store") }}', {
            method: 'POST',
            headers: { 'Accept': 'application/json', 'X-CSRF-TOKEN': formData.get('_token') },
            body: formData,
        })
        .then(r => r.json())
        .then(data => {
            if (data.ok) {
                contactForm.reset();
                success.style.display = 'block';
                btn.style.display = 'none';
            } else {
                throw new Error('Server error');
            }
        })
        .catch(function() {
            error.textContent = 'Ошибка отправки. Попробуйте позже.';
            error.style.display = 'block';
            btn.disabled = false;
            btn.textContent = 'Отправить запрос';
        });
    });
}
// ── FAQ accordion ──
function toggleFaq(btn) {
    var item = btn.closest('.faq-item');
    var isOpen = item.classList.contains('open');
    document.querySelectorAll('.faq-item.open').forEach(function(el) {
        el.classList.remove('open');
        el.querySelector('.faq-icon').textContent = '+';
    });
    if (!isOpen) {
        item.classList.add('open');
        btn.querySelector('.faq-icon').textContent = '×';
    }
}
</script>
</body>
</html>
