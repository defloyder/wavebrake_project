@extends('layout')

@section('title', 'WAVEBREAK - защищенная инфраструктура для бизнеса')
@section('description', 'WAVEBREAK помогает бизнесу продавать и сопровождать защищенный доступ: личный кабинет, тарифы, серверы доступа, панель оператора и понятное состояние подключений.')
@section('body_class', 'wb-shell wb-public')

@push('schema')
<script type="application/ld+json">
{
  "@@context": "https://schema.org",
  "@@type": "Organization",
  "name": "WAVEBREAK",
  "url": "{{ rtrim(config('app.url'), '/') }}",
  "logo": "{{ asset('images/wavebreak-logo.png') }}",
  "description": "Защищенная инфраструктура для бизнеса: личный кабинет, тарифы, серверы доступа и панель оператора."
}
</script>
<script type="application/ld+json">
{
  "@@context": "https://schema.org",
  "@@type": "SoftwareApplication",
  "name": "WAVEBREAK",
  "applicationCategory": "BusinessApplication",
  "operatingSystem": "Web, iOS, Android, Windows, macOS",
  "description": "Платформа для запуска и сопровождения защищенного доступа для клиентов и команд."
}
</script>
@endpush

@section('content')
@include('partials.public-header', ['active' => 'home'])

<main>
    <section class="wb-hero wb-hero--command">
        <div class="wb-container wb-hero-grid">
            <div class="wb-hero-copy">
                <p class="wb-kicker">Защищенная инфраструктура для бизнеса</p>
                <h1>Доступ для клиентов без ручной настройки и хаоса в операциях</h1>
                <p class="wb-lead">
                    WAVEBREAK собирает в одном продукте личный кабинет, тарифы, серверы доступа и панель оператора.
                    При этом приложение можно использовать и шире: добавить свою ссылку подключения от другого продавца
                    и держать все рабочие профили в одном понятном месте.
                </p>
                <div class="wb-hero-actions">
                    <a href="/register" class="wb-btn wb-btn--primary">Создать аккаунт</a>
                    <a href="/pricing" class="wb-btn">Посмотреть тарифы</a>
                    <a href="/access" class="wb-btn wb-btn--ghost">Как это устроено</a>
                </div>
                <div class="wb-trust-strip" aria-label="Состояние платформы">
                    <span><b>{{ $health['status'] ?? 'ok' }}</b> платформа</span>
                    <span><b>{{ count($plans) ?: 3 }}</b> тарифа</span>
                    <span><b>online</b> серверы доступа</span>
                </div>
            </div>

            <div class="wb-command-console" aria-label="Операционный контур WAVEBREAK">
                <div class="wb-console-top">
                    <span class="wb-status-dot">live</span>
                    <strong>WAVEBREAK Control</strong>
                    <span>ready</span>
                </div>
                <div class="wb-console-map">
                    <div class="wb-orbit wb-orbit--one"></div>
                    <div class="wb-orbit wb-orbit--two"></div>
                    <img src="{{ asset('images/wavebreak-logo.png') }}" alt="WAVEBREAK">
                    <span class="wb-point-chip wb-point-chip--core">Кабинет</span>
                    <span class="wb-point-chip wb-point-chip--client">Клиент</span>
                    <span class="wb-point-chip wb-point-chip--edge">Сервер</span>
                </div>
                <div class="wb-event-feed">
                    <div><span>01</span> Клиент выбирает тариф</div>
                    <div><span>02</span> Система готовит персональное подключение</div>
                    <div><span>03</span> Сервер принимает новые настройки</div>
                    <div><span>04</span> Команда видит подтверждение</div>
                </div>
            </div>
        </div>
    </section>

    <section class="wb-section wb-proof-section">
        <div class="wb-container wb-proof-grid">
            <article>
                <span>01</span>
                <h3>Клиенту понятно</h3>
                <p>Регистрация, тариф, устройство и подключение собраны в один спокойный сценарий.</p>
            </article>
            <article>
                <span>02</span>
                <h3>Команде видно</h3>
                <p>Панель показывает серверы, активные подключения, тарифы и состояние инфраструктуры.</p>
            </article>
            <article>
                <span>03</span>
                <h3>Гибко для рынка</h3>
                <p>Можно работать с тарифами WAVEBREAK или добавить стороннюю ссылку подключения, если она уже есть.</p>
            </article>
        </div>
    </section>

    <section class="wb-section wb-split-section">
        <div class="wb-container wb-split">
            <div>
                <p class="wb-kicker">Без лишней магии</p>
                <h2>WAVEBREAK превращает технический доступ в управляемый сервис</h2>
                <p>
                    Внутри есть все, что нужно для пилота и роста: учет клиентов, тарифы, серверы доступа,
                    панель оператора и подтверждение того, что подключение действительно готово. А для обычного пользователя
                    приложение остается удобным клиентом, куда можно добавить свои рабочие ссылки.
                </p>
            </div>
            <div class="wb-stack-list">
                <div><b>Кабинет</b><span>регистрация, вход, тарифы и устройства</span></div>
                <div><b>Подключение</b><span>персональные настройки для каждого клиента</span></div>
                <div><b>Свои ссылки</b><span>импорт подключений от внешних продавцов</span></div>
                <div><b>Серверы</b><span>локации, статусы и готовность к работе</span></div>
                <div><b>Операции</b><span>контроль, отзыв доступа и история действий</span></div>
            </div>
        </div>
    </section>

    <section class="wb-section">
        <div class="wb-container">
            <div class="wb-section-head">
                <p class="wb-kicker">Сценарии</p>
                <h2>Когда WAVEBREAK особенно полезен</h2>
                <p>Для компаний, которые хотят дать клиентам защищенный доступ как аккуратный продукт, а не как набор инструкций в чате.</p>
            </div>
            <div class="wb-usecase-grid">
                <article class="wb-card">
                    <h3>Коммерческий запуск</h3>
                    <p>Быстро показать клиенту личный кабинет, тариф и готовое подключение.</p>
                </article>
                <article class="wb-card">
                    <h3>Рабочие локации</h3>
                    <p>Добавлять серверы доступа по странам и видеть, какие из них доступны прямо сейчас.</p>
                </article>
                <article class="wb-card">
                    <h3>Поддержка клиентов</h3>
                    <p>Понимать, у кого активен тариф, где выдан доступ и что можно отозвать или пересоздать.</p>
                </article>
                <article class="wb-card">
                    <h3>Личное использование</h3>
                    <p>Добавить свою ссылку подключения и пользоваться приложением без покупки тарифа WAVEBREAK.</p>
                </article>
            </div>
        </div>
    </section>

    <section class="wb-section wb-final-cta">
        <div class="wb-container wb-final-panel">
            <div>
                <p class="wb-kicker">Запуск</p>
                <h2>Соберите доступ вокруг своего продукта</h2>
                <p>Начните с аккаунта, активируйте тариф и проверьте путь от кабинета до рабочего подключения.</p>
            </div>
            <a href="/register" class="wb-btn wb-btn--primary">Начать работу</a>
        </div>
    </section>
</main>
@endsection

