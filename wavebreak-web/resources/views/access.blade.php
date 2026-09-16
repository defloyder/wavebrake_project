@extends('layout')

@section('title', 'Технология WAVEBREAK')
@section('description', 'Как WAVEBREAK держит соединение: несколько транспортов на выбор, автоматическое переключение и один линк, который обновляется сам.')
@section('body_class', 'wb-shell wb-public')

@push('schema')
<script type="application/ld+json">
{
  "@@context": "https://schema.org",
  "@@type": "FAQPage",
  "mainEntity": [
    {
      "@@type": "Question",
      "name": "Нужно вручную выбирать протокол подключения?",
      "acceptedAnswer": {
        "@@type": "Answer",
        "text": "Нет. Профиль пробует несколько транспортов — VLESS и Hysteria2 — и держит тот, что проходит в вашей сети."
      }
    },
    {
      "@@type": "Question",
      "name": "Что если сеть блокирует VPN?",
      "acceptedAnswer": {
        "@@type": "Answer",
        "text": "WAVEBREAK не завязан на один способ подключения, поэтому канал продолжает работать даже при активных блокировках."
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
                <p class="wb-kicker">Технология</p>
                <h1>Один линк держит форму, даже когда сеть против</h1>
                <p class="wb-lead">
                    WAVEBREAK не привязан к одному протоколу. Профиль сам выбирает канал,
                    который проходит именно в вашей сети, и переключается, если условия меняются —
                    вы просто открываете приложение.
                </p>
            </div>
            <div class="wb-architecture-card">
                <div class="wb-arch-row"><span>Транспорт</span><b>VLESS · Hysteria2</b></div>
                <div class="wb-arch-row"><span>Шифрование</span><b>REALITY / TLS 1.3</b></div>
                <div class="wb-arch-row"><span>Переключение</span><b>автоматическое</b></div>
                <div class="wb-arch-row"><span>Подписка</span><b>одна ссылка, обновляется сама</b></div>
                <div class="wb-arch-row"><span>Устройства</span><b>iOS · Android · Windows · macOS</b></div>
            </div>
        </div>
    </section>

    <section class="wb-section">
        <div class="wb-container">
            <div class="wb-section-head">
                <p class="wb-kicker">Маршрут</p>
                <h2>От оплаты до рабочего подключения</h2>
                <p>Без ручных конфигов и инструкций в чатах.</p>
            </div>
            <div class="wb-timeline">
                <article>
                    <span>01</span>
                    <h3>Аккаунт</h3>
                    <p>Регистрируетесь и сразу попадаете в личный кабинет.</p>
                </article>
                <article>
                    <span>02</span>
                    <h3>Тариф</h3>
                    <p>Активный тариф открывает лимит трафика и число устройств.</p>
                </article>
                <article>
                    <span>03</span>
                    <h3>Подключение</h3>
                    <p>Один QR-код или ссылка — работает в Happ и похожих приложениях.</p>
                </article>
                <article>
                    <span>04</span>
                    <h3>Устройства</h3>
                    <p>Добавляете столько устройств, сколько разрешает тариф.</p>
                </article>
            </div>
        </div>
    </section>

    <section class="wb-section wb-dark-band">
        <div class="wb-container wb-feature-grid">
            <article class="wb-card">
                <h3>Не нужно гадать, что вставить</h3>
                <p>QR-код или ссылка — сканируете или копируете. Инструкция не нужна.</p>
            </article>
            <article class="wb-card">
                <h3>Работает там, где давят блокировки</h3>
                <p>Активные блокировки не останавливают канал: транспорт подбирается под вашу сеть.</p>
            </article>
            <article class="wb-card">
                <h3>Видно, что происходит</h3>
                <p>Статус, трафик и устройства — в кабинете, без обращения в поддержку.</p>
            </article>
        </div>
    </section>

    <section class="wb-section">
        <div class="wb-container wb-faq">
            <div>
                <p class="wb-kicker">FAQ</p>
                <h2>Коротко о том, как это работает</h2>
            </div>
            <div class="wb-faq-list">
                <article>
                    <h3>На скольких устройствах можно подключиться?</h3>
                    <p>Столько, сколько разрешает тариф. Устройства добавляются в личном кабинете.</p>
                </article>
                <article>
                    <h3>Что если сеть блокирует VPN?</h3>
                    <p>Профиль пробует несколько транспортов и держит тот, что проходит в вашей сети.</p>
                </article>
                <article>
                    <h3>Нужно вручную выбирать протокол?</h3>
                    <p>Нет — сработает лучший вариант для вашей сети автоматически.</p>
                </article>
                <article>
                    <h3>Что видно в личном кабинете?</h3>
                    <p>Тариф, использованный трафик, устройства и статус подключения.</p>
                </article>
            </div>
        </div>
    </section>
</main>
@endsection
