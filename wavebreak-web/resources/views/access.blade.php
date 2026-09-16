@extends('layout')

@section('title', 'Инфраструктура WAVEBREAK - управляемый доступ для бизнеса')
@section('description', 'Как устроен WAVEBREAK: личный кабинет, тарифы, серверы доступа, персональные подключения и панель оператора для защищенной бизнес-инфраструктуры.')
@section('body_class', 'wb-shell wb-public')

@push('schema')
<script type="application/ld+json">
{
  "@@context": "https://schema.org",
  "@@type": "FAQPage",
  "mainEntity": [
    {
      "@@type": "Question",
      "name": "Что делает WAVEBREAK?",
      "acceptedAnswer": {
        "@@type": "Answer",
        "text": "WAVEBREAK помогает бизнесу выдавать и сопровождать защищенный доступ через личный кабинет, тарифы, серверы доступа и панель оператора."
      }
    },
    {
      "@@type": "Question",
      "name": "Можно ли использовать свои ссылки?",
      "acceptedAnswer": {
        "@@type": "Answer",
        "text": "Да. Пользователь может добавить внешнюю ссылку подключения и использовать ее в приложении WAVEBREAK."
      }
    }
  ]
}
</script>
@endpush

@section('content')
@include('partials.public-header', ['active' => 'access'])

<main>
    <section class="wb-page-hero">
        <div class="wb-container wb-page-hero-grid">
            <div>
                <p class="wb-kicker">Инфраструктура</p>
                <h1>Путь от оплаты до рабочего подключения должен быть понятным</h1>
                <p class="wb-lead">
                    WAVEBREAK убирает ручную выдачу настроек. Клиент проходит аккуратный сценарий в кабинете,
                    а команда видит, какие подключения активны и какие серверы готовы к работе. Если у пользователя
                    уже есть внешняя ссылка подключения, приложение тоже умеет принять ее и хранить рядом с остальными профилями.
                </p>
            </div>
            <div class="wb-architecture-card">
                <div class="wb-arch-row"><span>Кабинет</span><b>клиент выбирает тариф</b></div>
                <div class="wb-arch-row"><span>Локация</span><b>сервер доступа готов</b></div>
                <div class="wb-arch-row"><span>Подключение</span><b>выдается персонально</b></div>
                <div class="wb-arch-row"><span>Импорт</span><b>можно добавить свою ссылку</b></div>
                <div class="wb-arch-row"><span>Панель</span><b>команда видит состояние</b></div>
            </div>
        </div>
    </section>

    <section class="wb-section">
        <div class="wb-container">
            <div class="wb-section-head">
                <p class="wb-kicker">Маршрут</p>
                <h2>Как клиент получает доступ</h2>
                <p>Без ручных файлов, хаотичных сообщений и непонятных статусов.</p>
            </div>
            <div class="wb-timeline">
                <article>
                    <span>01</span>
                    <h3>Аккаунт</h3>
                    <p>Клиент регистрируется или входит в кабинет. Все дальнейшие действия происходят в одном месте.</p>
                </article>
                <article>
                    <span>02</span>
                    <h3>Тариф</h3>
                    <p>Активный тариф открывает нужный уровень сервиса и доступные локации.</p>
                </article>
                <article>
                    <span>03</span>
                    <h3>Подключение</h3>
                    <p>Клиент выбирает локацию и получает персональные параметры подключения для своего устройства.</p>
                </article>
                <article>
                    <span>04</span>
                    <h3>Своя ссылка</h3>
                    <p>Если подключение уже куплено у другого продавца, пользователь может добавить его в приложение вручную.</p>
                </article>
                <article>
                    <span>05</span>
                    <h3>Контроль</h3>
                    <p>Команда видит состояние серверов, активные подключения и может быстро отозвать доступ.</p>
                </article>
            </div>
        </div>
    </section>

    <section class="wb-section wb-dark-band">
        <div class="wb-container wb-feature-grid">
            <article class="wb-card">
                <h3>Меньше ручной поддержки</h3>
                <p>Клиенту не нужно ждать инструкцию. Кабинет ведет его по нужным шагам.</p>
            </article>
            <article class="wb-card">
                <h3>Понятное сопровождение</h3>
                <p>Оператор видит тарифы, локации, устройства и активные подключения в одном контуре.</p>
            </article>
            <article class="wb-card">
                <h3>Готово к росту</h3>
                <p>Можно начать с одного сервера доступа и постепенно добавлять новые локации.</p>
            </article>
        </div>
    </section>

    <section class="wb-section">
        <div class="wb-container wb-faq">
            <div>
                <p class="wb-kicker">FAQ</p>
                <h2>Коротко о платформе</h2>
            </div>
            <div class="wb-faq-list">
                <article>
                    <h3>Можно ли подключать мобильное и десктопное приложение?</h3>
                    <p>Да. Приложения получают авторизацию, тарифы, локации и параметры подключения через единый backend продукта.</p>
                </article>
                <article>
                    <h3>Можно ли использовать свои ссылки?</h3>
                    <p>Да. WAVEBREAK не ограничен только нашими тарифами: пользователь может добавить внешнюю ссылку подключения и использовать ее в приложении.</p>
                </article>
                <article>
                    <h3>Что видит пользователь?</h3>
                    <p>Личный кабинет, активный тариф, доступные локации, устройства и готовое подключение.</p>
                </article>
                <article>
                    <h3>Что видит команда?</h3>
                    <p>Состояние серверов доступа, активных клиентов, тарифы и действия, которые требуют внимания.</p>
                </article>
            </div>
        </div>
    </section>
</main>
@endsection
