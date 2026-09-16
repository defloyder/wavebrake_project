@extends('layout')

@section('title', 'WAVEBREAK - защищенная инфраструктура для бизнеса')
@section('description', 'WAVEBREAK помогает запускать защищенный доступ для клиентов и использовать свои внешние ссылки подключения в одном приложении.')
@section('body_class', 'wb-shell wb-public wb-clearwave-page')

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
<script type="application/ld+json">
{
  "@@context": "https://schema.org",
  "@@type": "SoftwareApplication",
  "name": "WAVEBREAK",
  "applicationCategory": "BusinessApplication",
  "operatingSystem": "Web, iOS, Android, Windows, macOS",
  "description": "Платформа и приложения для управления защищенным доступом, тарифами и подключениями."
}
</script>
@endpush

@section('content')
@include('partials.public-header', ['active' => 'home'])

<main>
    <section class="cw-hero">
        <div class="cw-ambient" aria-hidden="true">
            <span></span><span></span><span></span>
        </div>

        <div class="wb-container cw-hero-grid">
            <div class="cw-hero-copy">
                <p class="wb-kicker">Secure access control</p>
                <h1>Доступ без ручной возни</h1>
                <p class="wb-lead">
                    WAVEBREAK объединяет тарифы, серверы доступа и внешние ссылки подключения в одном аккуратном приложении.
                </p>

                <div class="cw-mode-switch" aria-label="Режимы работы WAVEBREAK">
                    <span class="cw-switch-glass" aria-hidden="true"></span>
                    <button type="button">Свой сервис</button>
                    <button type="button">Внешние ссылки</button>
                    <button type="button">Контроль</button>
                </div>

                <div class="wb-hero-actions">
                    <a href="/register" class="wb-btn wb-btn--primary">Создать аккаунт</a>
                    <a href="/access" class="wb-btn">Посмотреть схему</a>
                </div>
            </div>

            <div class="cw-product-stage" aria-label="Интерфейс WAVEBREAK">
                <div class="cw-glass-card">
                    <div class="cw-card-top">
                        <span class="cw-live-dot">online</span>
                        <img src="{{ asset('images/wavebreak-logo.png') }}" alt="WAVEBREAK">
                        <em>ready</em>
                    </div>
                    <div class="cw-flow-board">
                        <div class="cw-flow-line cw-flow-line-one"></div>
                        <div class="cw-flow-line cw-flow-line-two"></div>
                        <div class="cw-brand-core">
                            <img src="{{ asset('images/wavebreak-logo.png') }}" alt="WAVEBREAK">
                        </div>
                        <span class="cw-node cw-node-a">Кабинет</span>
                        <span class="cw-node cw-node-b">Тариф</span>
                        <span class="cw-node cw-node-c">Сервер</span>
                        <span class="cw-node cw-node-d">Своя ссылка</span>
                    </div>
                    <div class="cw-card-feed">
                        <div><span>01</span><b>Пользователь выбирает сценарий</b></div>
                        <div><span>02</span><b>Приложение собирает профиль</b></div>
                        <div><span>03</span><b>Команда видит состояние</b></div>
                    </div>
                </div>

                <div class="cw-floating-panel cw-floating-panel--left">
                    <span>Link import</span>
                    <strong>ready</strong>
                    <small>свои ссылки внутри приложения</small>
                </div>

                <div class="cw-floating-panel cw-floating-panel--right">
                    <span>Business</span>
                    <strong>plans</strong>
                    <small>тарифы и локации под контролем</small>
                </div>
            </div>
        </div>
    </section>

    <section class="wb-section cw-route-section">
        <div class="wb-container">
            <div class="wb-section-head wb-section-head--compact">
                <p class="wb-kicker">Два сценария</p>
                <h2>Для продажи доступа и для своих рабочих профилей</h2>
            </div>
            <div class="cw-route-grid">
                <article class="cw-route-card cw-route-card--accent">
                    <span>01</span>
                    <h3>Ваш сервис</h3>
                    <p>Кабинет, тарифы, локации и выдача подключения для клиента.</p>
                </article>
                <article class="cw-route-card">
                    <span>02</span>
                    <h3>Свои ссылки</h3>
                    <p>Пользователь добавляет внешние ссылки подключения от разных продавцов.</p>
                </article>
                <article class="cw-route-card">
                    <span>03</span>
                    <h3>Панель команды</h3>
                    <p>Оператор видит статусы, серверы доступа и активные подключения.</p>
                </article>
            </div>
        </div>
    </section>

    <section class="wb-section cw-showcase">
        <div class="wb-container cw-showcase-grid">
            <div class="cw-showcase-copy">
                <p class="wb-kicker">Система</p>
                <h2>Не набор инструкций, а цельный продукт</h2>
                <p>
                    Витрина, кабинет, приложения и панель оператора работают в одном стиле:
                    клиенту понятно, команде видно, бизнесу проще сопровождать сервис.
                </p>
            </div>
            <div class="cw-stack">
                <div><b>Кабинет</b><span>аккаунт, тариф, устройства</span></div>
                <div><b>Приложения</b><span>мобильный и десктопный клиент</span></div>
                <div><b>Серверы доступа</b><span>локации и состояние</span></div>
                <div><b>Внешние ссылки</b><span>импорт профилей от продавцов</span></div>
            </div>
        </div>
    </section>

    <section class="wb-section cw-usecases">
        <div class="wb-container">
            <div class="wb-section-head wb-section-head--compact">
                <p class="wb-kicker">Где полезно</p>
                <h2>Когда нужен порядок</h2>
            </div>
            <div class="wb-usecase-grid">
                <article class="wb-card">
                    <h3>Коммерческий запуск</h3>
                    <p>Показать клиенту тариф, кабинет и готовый путь подключения.</p>
                </article>
                <article class="wb-card">
                    <h3>Личные профили</h3>
                    <p>Держать внешние ссылки подключения не в чатах, а в приложении.</p>
                </article>
                <article class="wb-card">
                    <h3>Поддержка</h3>
                    <p>Быстро понимать, что активно и где нужна помощь.</p>
                </article>
            </div>
        </div>
    </section>

    <section class="wb-section wb-final-cta">
        <div class="wb-container wb-final-panel">
            <div>
                <p class="wb-kicker">Старт</p>
                <h2>Запустите доступ как продукт</h2>
                <p>Создайте аккаунт и проверьте путь от тарифа до готового профиля.</p>
            </div>
            <a href="/register" class="wb-btn wb-btn--primary">Начать</a>
        </div>
    </section>
</main>

<footer class="wb-footer">
    <div class="wb-container wb-footer-grid">
        <div>
            <img src="{{ asset('images/wavebreak-logo.png') }}" alt="WAVEBREAK">
            <p>Защищенная инфраструктура для бизнеса и рабочих профилей.</p>
        </div>
        <nav aria-label="Нижняя навигация">
            <a href="/">Главная</a>
            <a href="/pricing">Тарифы</a>
            <a href="/access">Инфраструктура</a>
            <a href="/login">Вход</a>
        </nav>
        <span>© {{ date('Y') }} WAVEBREAK</span>
    </div>
</footer>
@endsection
