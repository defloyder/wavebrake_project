@extends('layout')
@section('title', 'WAVEBREAK | Защищённая инфраструктура для бизнеса')
@section('description', 'WAVEBREAK: защищённая инфраструктура для бизнеса и приложение для ваших подключений. Тарифы сервиса и профили других провайдеров на компьютере и смартфоне.')
@section('body_class', 'wb-public page-home')
@section('content')
<main id="main">
    <section class="download-hero site-hero" aria-labelledby="home-title">
        @include('partials.tide')
        <div class="wb-container site-hero-inner">
            <div class="hero-copy" data-reveal>
                <p class="download-kicker"><span></span> Защищённая инфраструктура для бизнеса</p>
                <h1 id="home-title" class="brand-heading">WAVEBREAK</h1>
                <p class="hero-statement">На вашей <em>волне.</em></p>
                <p class="hero-description">Один сервис для работы. Одно приложение для ваших подключений. На компьютере и в телефоне.</p>
                <a class="download-discover" href="/download"><span>К приложениям</span><span aria-hidden="true">↗</span></a>
            </div>
            <div class="hero-bottom"><span>Windows / Android / iOS</span><a href="#choice">Дальше о главном <span aria-hidden="true">↓</span></a></div>
        </div>
    </section>
    <section class="site-section" id="choice" aria-labelledby="choice-title">
        <div class="wb-container">
            <div class="section-heading" data-reveal><p class="download-kicker"><span></span> Ваш выбор</p><h2 id="choice-title">Наш сервис.<br><em>Или ваша ссылка.</em></h2></div>
            <div class="choice-grid">
                <article data-reveal><span class="section-number">01 / WAVEBREAK</span><h3>Подключение от нас</h3><p>Выберите тариф WAVEBREAK. Подписка, доступные локации и расход трафика будут в приложении.</p><a class="text-link" href="/pricing">Выбрать тариф <span aria-hidden="true">↗</span></a></article>
                <article data-reveal><span class="section-number">02 / СВОЙ ПРОФИЛЬ</span><h3>Уже есть подписка?</h3><p>Добавьте совместимую ссылку другого провайдера. Покупать тариф WAVEBREAK для этого не нужно.</p><a class="text-link" href="/access#profiles">О совместимости <span aria-hidden="true">↗</span></a></article>
            </div>
        </div>
    </section>
    <section class="site-section product-band" aria-labelledby="app-title">
        <div class="wb-container product-layout">
            <div data-reveal><p class="download-kicker"><span></span> Всегда под рукой</p><h2 id="app-title">Меньше переходов.<br><em>Больше дела.</em></h2><p class="section-copy">Аккаунт и подключения находятся в приложении. Здесь, на сайте, можно посмотреть тарифы и выбрать версию для своего устройства.</p><a class="text-link" href="/download">Посмотреть приложения <span aria-hidden="true">↗</span></a></div>
            <div class="product-globe" aria-hidden="true">
                <span class="download-core-ring"><i class="download-globe-meridian"></i><i class="download-globe-latitude"></i><img src="{{ asset('images/wavebreak-mark.png') }}" alt=""></span>
                <span class="section-number">WAVEBREAK / ВАШИ ПОДКЛЮЧЕНИЯ</span>
            </div>
        </div>
    </section>
    <section class="site-section">
        <div class="wb-container faq-layout">
            <h2 data-reveal">Коротко.<br><em>По существу.</em></h2>
            <div class="faq-list">
                <details><summary>Нужна ли подписка WAVEBREAK?</summary><p>Только для использования нашего сервиса. Совместимые профили других провайдеров можно добавить отдельно.</p></details>
                <details><summary>Где войти в личный кабинет?</summary><p>В мобильном или десктопном приложении. Веб-кабинета для клиентов нет.</p></details>
                <details><summary>Где скачать приложение?</summary><p>На <a href="/download">странице приложений</a>. Ссылки станут доступны после публикации сборок.</p></details>
            </div>
        </div>
    </section>
</main>
@endsection
