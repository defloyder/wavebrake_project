<!DOCTYPE html>
<html lang="ru" prefix="og: https://ogp.me/ns#">
<head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>Auralith B2B — IT-инфраструктура, аудит, HA и поддержка для бизнеса</title>
    <meta name="description" content="Auralith B2B помогает бизнесу укрепить IT-инфраструктуру: аудит, HA-архитектура, мониторинг 24/7, резервное копирование, оптимизация облака и сопровождение." />
    <meta name="keywords" content="Auralith B2B, IT инфраструктура для бизнеса, аудит инфраструктуры, HA архитектура, отказоустойчивость, мониторинг серверов, DevOps поддержка, оптимизация облака" />
    <meta name="robots" content="index, follow, max-snippet:-1, max-image-preview:large" />
    <link rel="canonical" href="{{ route('b2b') }}" />

    <meta property="og:type" content="website" />
    <meta property="og:url" content="{{ route('b2b') }}" />
    <meta property="og:title" content="Auralith B2B — стабильная IT-инфраструктура для бизнеса" />
    <meta property="og:description" content="Аудит, отказоустойчивость, мониторинг и сопровождение инфраструктуры без лишней сложности." />
    <meta property="og:image" content="https://auralith.ru/images/logo-mark.png?v=brand4" />
    <meta property="og:locale" content="ru_RU" />
    <meta property="og:site_name" content="Auralith" />

    <meta name="twitter:card" content="summary_large_image" />
    <meta name="twitter:title" content="Auralith B2B — IT-инфраструктура для бизнеса" />
    <meta name="twitter:description" content="От аудита до сопровождения: HA, мониторинг, резервирование и оптимизация облака." />
    <meta name="twitter:image" content="https://auralith.ru/images/logo-mark.png?v=brand4" />

    <link rel="icon" type="image/png" sizes="32x32" href="{{ asset('images/favicon-32.png') }}?v=brand4">
    <link rel="apple-touch-icon" sizes="180x180" href="{{ asset('images/apple-touch-icon.png') }}?v=brand4">
    <link rel="preconnect" href="https://fonts.googleapis.com" />
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&family=Montserrat:wght@600;700&display=swap" rel="stylesheet" />
    <link rel="stylesheet" href="{{ asset('css/landing.css') }}?v=21" />
    <link rel="stylesheet" href="{{ asset('css/public-redesign.css') }}?v=28" />

    <script type="application/ld+json">
    {
        "@@context": "https://schema.org",
        "@@type": "ProfessionalService",
        "name": "Auralith B2B",
        "url": "{{ route('b2b') }}",
        "logo": "https://auralith.ru/images/logo-mark.png?v=brand4",
        "description": "Аудит, проектирование и сопровождение IT-инфраструктуры для бизнеса.",
        "areaServed": "RU",
        "serviceType": ["IT-аудит", "HA-архитектура", "Мониторинг 24/7", "Оптимизация облака", "Резервное копирование"],
        "provider": {
            "@@type": "Organization",
            "name": "Auralith",
            "url": "https://auralith.ru"
        }
    }
    </script>
</head>
<body class="b2b-page">
<div class="page-glow page-glow-top"></div>
<div class="page-glow page-glow-bottom"></div>

<header class="site-header">
    <div class="container nav">
        <a href="{{ route('home') }}" class="brand" aria-label="Auralith — главная страница">
            <img src="{{ asset('images/logo-mark.png') }}?v=brand4" alt="Auralith логотип" class="brand-logo" width="56" height="56" />
            <span>Auralith</span>
        </a>
        <nav class="nav-links" aria-label="Основная навигация">
            <a href="#b2b-pricing">B2B-тарифы</a>
            <a href="{{ route('home') }}#pricing">Access</a>
            <a href="{{ route('home') }}#services">Услуги</a>
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
    <section class="hero b2b-hero">
        <div class="container hero-grid">
            <div class="hero-content">
                <p class="eyebrow">Auralith B2B</p>
                <h1>Инфраструктура без лишнего шума</h1>
                <p class="hero-text">
                    Аудит, Core-диагностика, отказоустойчивость и сопровождение для систем,
                    где простой быстро становится дорогим.
                </p>
                <div class="hero-actions">
                    <a href="#contact" class="btn btn-primary">Обсудить задачу</a>
                    <a href="#b2b-pricing" class="btn btn-secondary">Тарифы B2B</a>
                </div>
                <ul class="hero-metrics">
                    <li><strong>HA</strong><span>без единой точки отказа</span></li>
                    <li><strong>24/7</strong><span>алерты и мониторинг</span></li>
                    <li><strong>SLA</strong><span>понятная реакция</span></li>
                </ul>
            </div>

            <div class="hero-panel b2b-command-panel">
                <div class="b2b-radar" aria-hidden="true">
                    <span></span><span></span><span></span>
                    <strong>Core</strong>
                    <em>nodes / logs / diagnostics</em>
                </div>
                <div class="terminal">
                    <div class="terminal-head" aria-hidden="true">
                        <i class="terminal-dot"></i>
                        <i class="terminal-dot"></i>
                        <i class="terminal-dot"></i>
                    </div>
                    <pre><code data-type-speed="17">[auralith/b2b]$ audit stack
 network: review routes and firewall
 data: backup policy and restore test
 app: failover plan and observability
 cloud: cost and capacity report

 result: roadmap for stable growth</code></pre>
                </div>
                <div class="b2b-health-grid" aria-hidden="true">
                    <div><span>HA</span><strong>planned</strong></div>
                    <div><span>Backups</span><strong>verified</strong></div>
                    <div><span>Alerts</span><strong>active</strong></div>
                </div>
            </div>
        </div>
    </section>

    <section class="section b2b-capabilities">
        <div class="container">
            <div class="section-head">
                <p class="eyebrow">Что закрываем</p>
                <h2>От диагностики до постоянного сопровождения</h2>
            </div>
            <div class="cards cards-3">
                <article class="card">
                    <h3>Аудит инфраструктуры</h3>
                    <p>Проверяем серверы, сеть, облачные ресурсы, безопасность, резервные копии и точки отказа.</p>
                </article>
                <article class="card">
                    <h3>Отказоустойчивость</h3>
                    <p>Проектируем HA-схемы, балансировку, репликацию и план восстановления после инцидентов.</p>
                </article>
                <article class="card">
                    <h3>Поддержка и мониторинг</h3>
                    <p>Настраиваем наблюдаемость, алерты, регламенты реакции и регулярную профилактику.</p>
                </article>
            </div>
        </div>
    </section>

    <section class="section b2b-pricing-section" id="b2b-pricing">
        <div class="container">
            <div class="section-head b2b-pricing-head">
                <p class="eyebrow">Тарифы B2B</p>
                <h2>Сопровождение под вашу нагрузку</h2>
                <p>Три формата: разовая консультация, сопровождение текущей инфраструктуры или глубокая работа с архитектурой.</p>
            </div>
            <div class="b2b-pricing-grid">
                <article class="b2b-pricing-card">
                    <div class="b2b-pricing-card__top">
                        <span>Старт</span>
                        <strong>5 000 — 8 000 ₽</strong>
                    </div>
                    <h3>Разовая консультация</h3>
                    <ul>
                        <li>1 встреча до 1,5 часов</li>
                        <li>Разбор текущей ситуации или конкретного вопроса</li>
                        <li>Рекомендации по стеку или архитектуре</li>
                        <li>Краткое резюме после встречи</li>
                    </ul>
                    <a href="#contact" class="btn btn-secondary">Обсудить старт</a>
                </article>
                <article class="b2b-pricing-card">
                    <div class="b2b-pricing-card__top">
                        <span>Базовый</span>
                        <strong>20 000 — 30 000 ₽/мес</strong>
                    </div>
                    <h3>Сопровождение месяц</h3>
                    <ul>
                        <li>До 4 встреч в месяц</li>
                        <li>Анализ запроса и задач бизнеса</li>
                        <li>Помощь с выбором стека и инструментов</li>
                        <li>Ответы на вопросы между встречами в текстовом формате</li>
                    </ul>
                    <a href="#contact" class="btn btn-secondary">Обсудить базовый</a>
                </article>
                <article class="b2b-pricing-card b2b-pricing-card--featured">
                    <div class="b2b-pricing-card__top">
                        <span>Продвинутый</span>
                        <strong>50 000 — 70 000 ₽/мес</strong>
                    </div>
                    <h3>Глубокое сопровождение</h3>
                    <ul>
                        <li>До 8 встреч в месяц</li>
                        <li>Полный анализ IT-инфраструктуры или проекта с нуля</li>
                        <li>Проектирование архитектуры под задачи бизнеса</li>
                        <li>Помощь с выбором команды или подрядчиков</li>
                        <li>Приоритетная связь, ответы в течение дня</li>
                    </ul>
                    <a href="#contact" class="btn btn-primary">Обсудить продвинутый</a>
                </article>
            </div>
        </div>
    </section>

    <section class="section section-dim b2b-process-section">
        <div class="container b2b-process">
            <div class="section-head">
                <p class="eyebrow">Как работаем</p>
                <h2>Короткий путь от хаоса к управляемой системе</h2>
            </div>
            <div class="timeline">
                <div class="timeline-item">
                    <span>01</span>
                    <div>
                        <h3>Быстро собираем контекст</h3>
                        <p>Фиксируем сервисы, зависимости, текущие боли, риски и бизнес-критичные процессы.</p>
                    </div>
                </div>
                <div class="timeline-item">
                    <span>02</span>
                    <div>
                        <h3>Даём понятный план</h3>
                        <p>Расставляем приоритеты: что чинить сразу, что можно отложить, где есть лишние расходы.</p>
                    </div>
                </div>
                <div class="timeline-item">
                    <span>03</span>
                    <div>
                        <h3>Внедряем и сопровождаем</h3>
                        <p>Настраиваем инфраструктуру, мониторинг, резервирование и оставляем систему под наблюдением.</p>
                    </div>
                </div>
            </div>
        </div>
    </section>

    <section class="section b2b-seo">
        <div class="container seo-copy">
            <p class="eyebrow">Для кого</p>
            <h2>Командам, которым важны доступность, безопасность и предсказуемые расходы</h2>
            <div class="seo-copy-grid">
                <p>
                    Auralith B2B подходит онлайн-сервисам, внутренним системам, e-commerce, Telegram-проектам
                    и компаниям, где простой инфраструктуры быстро превращается в потерю денег и доверия.
                </p>
                <p>
                    Мы работаем с существующей архитектурой без резких перестроек: сначала убираем критичные
                    риски, затем усиливаем систему, документацию, мониторинг и процессы поддержки.
                </p>
            </div>
        </div>
    </section>
</main>

<footer id="contact" class="site-footer">
    <div class="container footer-grid">
        <div>
            <h2>Расскажите, что должно работать стабильнее</h2>
            <p>Опишите инфраструктуру и задачу. Вернёмся с первичной оценкой и следующим шагом.</p>
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
                <textarea name="message" rows="4" placeholder="Коротко опишите инфраструктуру и проблему"></textarea>
            </label>
            <button type="submit" class="btn btn-primary" id="contact-submit">Отправить запрос</button>
            <div id="contact-success" style="display:none;color:#86efac;font-size:.9rem;text-align:center">
                Заявка отправлена. Мы свяжемся с вами в ближайшее время.
            </div>
            <div id="contact-error" style="display:none;color:#f87171;font-size:.9rem;text-align:center"></div>
        </form>
    </div>
</footer>

@include('partials.footer')

<script>
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
            body: formData
        })
        .then(function(r) { return r.json(); })
        .then(function(data) {
            if (!data.ok) throw new Error('Server error');
            contactForm.reset();
            success.style.display = 'block';
            btn.style.display = 'none';
        })
        .catch(function() {
            error.textContent = 'Ошибка отправки. Попробуйте позже.';
            error.style.display = 'block';
            btn.disabled = false;
            btn.textContent = 'Отправить запрос';
        });
    });
}
</script>
<script src="{{ asset('js/landing.js') }}?v=8"></script>
</body>
</html>

