@extends('layout')

@section('title', 'WAVEBREAK - защищенная инфраструктура для бизнеса')
@section('description', 'WAVEBREAK помогает запускать и сопровождать защищенный доступ: тарифы, личный кабинет, серверы доступа, внешние ссылки подключения и панель оператора.')
@section('body_class', 'wb-shell wb-public wb-clearwave-page')

@push('schema')
<script type="application/ld+json">
{
  "@@context": "https://schema.org",
  "@@type": "Organization",
  "name": "WAVEBREAK",
  "url": "{{ rtrim(config('app.url'), '/') }}",
  "logo": "{{ asset('images/wavebreak-logo.png') }}",
  "description": "Защищенная инфраструктура для бизнеса: личный кабинет, тарифы, серверы доступа и внешние ссылки подключения."
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
                <p class="wb-kicker">WAVEBREAK для бизнеса и личного использования</p>
                <h1>Один кабинет для тарифов, серверов и своих ссылок подключения</h1>
                <p class="wb-lead">
                    Запускайте собственный сервис доступа с тарифами и панелью оператора. А если у пользователя
                    уже есть ссылка от другого продавца, он может добавить ее в приложение и держать все профили рядом.
                </p>
                <div class="wb-hero-actions">
                    <a href="/register" class="wb-btn wb-btn--primary">Создать аккаунт</a>
                    <a href="/access" class="wb-btn">Как устроено</a>
                </div>
                <div class="cw-metrics" aria-label="Ключевые возможности">
                    <div><strong>2</strong><span>режима: свои тарифы и внешние ссылки</span></div>
                    <div><strong>3</strong><span>готовых уровня сервиса</span></div>
                    <div><strong>24/7</strong><span>контроль состояния инфраструктуры</span></div>
                </div>
            </div>

            <div class="cw-product-stage" aria-label="Интерфейс WAVEBREAK">
                <div class="cw-glass-card cw-card-main">
                    <div class="cw-card-top">
                        <span class="cw-live-dot">online</span>
                        <strong>WAVEBREAK</strong>
                        <em>ready</em>
                    </div>
                    <div class="cw-logo-orbit">
                        <div class="cw-ring cw-ring-one"></div>
                        <div class="cw-ring cw-ring-two"></div>
                        <img src="{{ asset('images/wavebreak-logo-mark.png') }}" alt="WAVEBREAK">
                        <span class="cw-node cw-node-a">Кабинет</span>
                        <span class="cw-node cw-node-b">Тариф</span>
                        <span class="cw-node cw-node-c">Сервер</span>
                    </div>
                    <div class="cw-card-feed">
                        <div><span>01</span><b>Клиент входит в кабинет</b></div>
                        <div><span>02</span><b>Выбирает тариф или добавляет ссылку</b></div>
                        <div><span>03</span><b>Получает готовый профиль</b></div>
                    </div>
                </div>

                <div class="cw-floating-panel cw-floating-panel--left">
                    <span>External link</span>
                    <strong>imported</strong>
                    <small>профиль добавлен вручную</small>
                </div>

                <div class="cw-floating-panel cw-floating-panel--right">
                    <span>Operator</span>
                    <strong>visible</strong>
                    <small>тарифы, локации, статусы</small>
                </div>
            </div>
        </div>
    </section>

    <section class="wb-section cw-route-section">
        <div class="wb-container">
            <div class="wb-section-head">
                <p class="wb-kicker">Два понятных сценария</p>
                <h2>Не только наши тарифы. Приложение работает и со своими ссылками.</h2>
            </div>
            <div class="cw-route-grid">
                <article class="cw-route-card cw-route-card--accent">
                    <span>01</span>
                    <h3>Сервис WAVEBREAK</h3>
                    <p>Клиент регистрируется, выбирает тариф, локацию и получает персональное подключение в кабинете.</p>
                </article>
                <article class="cw-route-card">
                    <span>02</span>
                    <h3>Своя ссылка</h3>
                    <p>Пользователь вставляет внешнюю ссылку подключения от другого продавца и использует ее в приложении.</p>
                </article>
                <article class="cw-route-card">
                    <span>03</span>
                    <h3>Операционный контроль</h3>
                    <p>Команда видит тарифы, серверы доступа, активные подключения и может быстро помогать клиентам.</p>
                </article>
            </div>
        </div>
    </section>

    <section class="wb-section cw-showcase">
        <div class="wb-container cw-showcase-grid">
            <div class="cw-showcase-copy">
                <p class="wb-kicker">Контур продукта</p>
                <h2>Витрина, кабинет и приложения работают как единая система</h2>
                <p>
                    WAVEBREAK закрывает коммерческий запуск и обычное использование: тарифы для вашего сервиса,
                    ручной импорт внешних ссылок, устройства клиента и понятная панель для команды.
                </p>
            </div>
            <div class="cw-stack">
                <div><b>Личный кабинет</b><span>аккаунт, тариф, устройства, подключения</span></div>
                <div><b>Приложения</b><span>мобильный и десктопный клиент для рабочих профилей</span></div>
                <div><b>Серверы доступа</b><span>локации, статусы и готовность к работе</span></div>
                <div><b>Внешние ссылки</b><span>импорт подключений от разных продавцов</span></div>
            </div>
        </div>
    </section>

    <section class="wb-section cw-usecases">
        <div class="wb-container">
            <div class="wb-section-head">
                <p class="wb-kicker">Где полезно</p>
                <h2>Для запуска продукта и для повседневного использования</h2>
            </div>
            <div class="wb-usecase-grid">
                <article class="wb-card">
                    <h3>Коммерческий запуск</h3>
                    <p>Быстро показать клиенту тариф, кабинет и готовый путь к подключению.</p>
                </article>
                <article class="wb-card">
                    <h3>Личные профили</h3>
                    <p>Добавить внешние ссылки подключения и не держать их в заметках или чатах.</p>
                </article>
                <article class="wb-card">
                    <h3>Поддержка клиентов</h3>
                    <p>Видеть активные тарифы, устройства, локации и состояние серверов доступа.</p>
                </article>
            </div>
        </div>
    </section>

    <section class="wb-section wb-final-cta">
        <div class="wb-container wb-final-panel">
            <div>
                <p class="wb-kicker">Запуск</p>
                <h2>Соберите защищенный доступ в понятный продукт</h2>
                <p>Начните с аккаунта: проверьте тарифы, кабинет и сценарий добавления рабочих профилей.</p>
            </div>
            <a href="/register" class="wb-btn wb-btn--primary">Начать работу</a>
        </div>
    </section>
</main>
@endsection
