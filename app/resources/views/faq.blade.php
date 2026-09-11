<!DOCTYPE html>
<html lang="ru">
<head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>FAQ — Часто задаваемые вопросы | Auralith</title>
    <meta name="description" content="FAQ Auralith / Ауралит: как подключить подписку, где получить ссылку, какие устройства поддерживаются, как работает Telegram-бот и защищённый доступ." />
    <meta name="robots" content="index, follow, max-snippet:-1, max-image-preview:large" />
    <link rel="canonical" href="{{ route('faq') }}" />
    <meta property="og:type" content="article" />
    <meta property="og:url" content="{{ route('faq') }}" />
    <meta property="og:title" content="FAQ Auralith / Ауралит" />
    <meta property="og:description" content="Ответы на вопросы о подписке Auralith, подключении, Telegram-боте и защищённом доступе." />
    <meta property="og:image" content="https://auralith.ru/images/logo-mark.png?v=brand4" />
    <link rel="icon" type="image/png" sizes="32x32" href="{{ asset('images/favicon-32.png') }}?v=brand4">
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&family=Montserrat:wght@600;700&display=swap" rel="stylesheet">
    <link rel="stylesheet" href="{{ asset('css/landing.css') }}?v=13">
    <link rel="stylesheet" href="{{ asset('css/faq.css') }}">
    <script type="application/ld+json">
    {
        "@@context": "https://schema.org",
        "@@type": "FAQPage",
        "mainEntity": [
            {
                "@@type": "Question",
                "name": "Как быстро активируется подписка после оплаты?",
                "acceptedAnswer": {
                    "@@type": "Answer",
                    "text": "Подписка Auralith активируется автоматически после подтверждения платежа. Пользователь получает данные для подключения в Telegram и видит статус в личном кабинете."
                }
            },
            {
                "@@type": "Question",
                "name": "На каких устройствах работает Auralith?",
                "acceptedAnswer": {
                    "@@type": "Answer",
                    "text": "Auralith работает на Windows, macOS, Linux, iOS и Android через совместимые приложения и персональную конфигурацию."
                }
            },
            {
                "@@type": "Question",
                "name": "Как найти сервис, если вводить название по-русски?",
                "acceptedAnswer": {
                    "@@type": "Answer",
                    "text": "Сервис называется Auralith, а русское написание бренда — Ауралит. Оба варианта относятся к одному сервису защищённого доступа."
                }
            }
        ]
    }
    </script>
</head>
<body>

<div class="page-glow page-glow-top"></div>

<header class="site-header">
    <div class="container nav">
        <a href="{{ route('home') }}" class="brand">
            <img src="{{ asset('images/logo-mark.png') }}?v=brand4" alt="Auralith" class="brand-logo" width="44" height="44" />
            <span>Auralith</span>
        </a>
        <nav class="nav-links">
            <a href="{{ route('home') }}#pricing">Тарифы</a>
            <a href="{{ route('home') }}#services">Услуги</a>
            <a href="{{ route('b2b') }}">B2B</a>
            <a href="{{ route('faq') }}" class="active">FAQ</a>
            <a href="{{ route('home') }}#contact">Контакты</a>
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
    <section class="faq-page-section">
        <div class="container">
            <p class="section-eyebrow">Поддержка</p>
            <h1 class="section-title">Часто задаваемые вопросы</h1>
            <p style="color:var(--muted);text-align:center;margin-bottom:48px;font-size:.95rem">Не нашли ответ? Напишите нам в <a href="https://t.me/auralithaccessbot" style="color:var(--accent)">Telegram</a></p>

            <div class="faq-list">

                <div class="faq-item">
                    <button class="faq-q" onclick="toggleFaq(this)">
                        Как быстро активируется подписка после оплаты?
                        <span class="faq-icon">+</span>
                    </button>
                    <div class="faq-a">
                        <p>Подписка активируется автоматически в течение нескольких секунд после подтверждения платежа. Вы получите уведомление в Telegram с персональными данными для подключения.</p>
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

                <div class="faq-item">
                    <button class="faq-q" onclick="toggleFaq(this)">
                        Как подключиться к сервису?
                        <span class="faq-icon">+</span>
                    </button>
                    <div class="faq-a">
                        <p>Зарегистрируйтесь через Telegram-бота, выберите подходящий тариф и оплатите. После активации вы получите персональную ссылку-конфигурацию. Весь процесс занимает не более 2 минут.</p>
                    </div>
                </div>

                <div class="faq-item">
                    <button class="faq-q" onclick="toggleFaq(this)">
                        Можно ли использовать сервис на нескольких устройствах?
                        <span class="faq-icon">+</span>
                    </button>
                    <div class="faq-a">
                        <p>Да, одна подписка позволяет подключать несколько устройств одновременно без дополнительной платы.</p>
                    </div>
                </div>

                <div class="faq-item">
                    <button class="faq-q" onclick="toggleFaq(this)">
                        Какие способы оплаты доступны?
                        <span class="faq-icon">+</span>
                    </button>
                    <div class="faq-a">
                        <p>Принимаем оплату банковской картой РФ, через СБП (QR-код) и СберПэй. Все платежи обрабатываются через защищённый платёжный шлюз.</p>
                    </div>
                </div>

                <div class="faq-item">
                    <button class="faq-q" onclick="toggleFaq(this)">
                        Что такое пробный период и как его получить?
                        <span class="faq-icon">+</span>
                    </button>
                    <div class="faq-a">
                        <p>Пробный период — это бесплатный доступ к сервису на 3 дня. Активировать его можно один раз через Telegram-бота или в личном кабинете. Данные карты не требуются.</p>
                    </div>
                </div>

                <div class="faq-item">
                    <button class="faq-q" onclick="toggleFaq(this)">
                        Что происходит после окончания подписки?
                        <span class="faq-icon">+</span>
                    </button>
                    <div class="faq-a">
                        <p>После истечения срока доступ к сервису автоматически приостанавливается. Продлить подписку можно в любой момент через Telegram-бота или личный кабинет на сайте.</p>
                    </div>
                </div>

                <div class="faq-item">
                    <button class="faq-q" onclick="toggleFaq(this)">
                        Где расположены серверы?
                        <span class="faq-icon">+</span>
                    </button>
                    <div class="faq-a">
                        <p>Серверы расположены в Европе. Мы постоянно расширяем инфраструктуру для обеспечения минимальных задержек и высокой стабильности соединения.</p>
                    </div>
                </div>

                <div class="faq-item">
                    <button class="faq-q" onclick="toggleFaq(this)">
                        Как получить помощь если что-то не работает?
                        <span class="faq-icon">+</span>
                    </button>
                    <div class="faq-a">
                        <p>Напишите в наш Telegram-бот или оставьте заявку на сайте. Мы отвечаем в рабочее время и стараемся решить любой вопрос в течение нескольких часов.</p>
                    </div>
                </div>

            </div>
        </div>
    </section>
</main>

@include('partials.footer')

<script>
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

