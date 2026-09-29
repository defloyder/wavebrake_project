@extends('layout')
@section('title', 'WAVEBREAK — защищённое сетевое подключение и управление доступом')
@section('description', 'WAVEBREAK шифрует подключение ваших устройств и помогает управлять доступом — для себя, команды и бизнеса. Приложения для Windows и Android, для аккаунта достаточно e-mail.')
@section('body_class', 'wb-public page-home')
@section('content')
<main id="main">
    <section class="download-hero site-hero" aria-labelledby="home-title">
        @include('partials.tide')
        <div class="wb-container site-hero-inner">
            <div class="hero-copy" data-reveal>
                <h1 id="home-title" class="brand-heading"><span class="download-kicker hero-kicker"><span></span> Платформа защищённого подключения и управления доступом</span> WAVEBREAK</h1>
                <p class="hero-statement">На вашей <em>волне.</em></p>
                <p class="hero-description">Зашифрованное подключение к нашей инфраструктуре и управление доступом в одном приложении. Для себя, команды и бизнеса — на компьютере и в телефоне.</p>
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
    <section class="site-section" aria-labelledby="audience-title">
        <div class="wb-container">
            <div class="section-heading" data-reveal><p class="download-kicker"><span></span> Для кого</p><h2 id="audience-title">Для себя, команды<br><em>и бизнеса.</em></h2></div>
            <div class="choice-grid choice-grid--three">
                <article data-reveal><span class="section-number">01 / ЧАСТНЫМ ПОЛЬЗОВАТЕЛЯМ</span><h3>Защищённое подключение</h3><p>Соединение с серверами WAVEBREAK шифруется — в том числе в публичных сетях Wi-Fi в кафе, отелях и аэропортах. Локацию выбираете сами.</p></article>
                <article data-reveal data-reveal-delay="80"><span class="section-number">02 / КОМАНДАМ</span><h3>Один аккаунт — несколько устройств</h3><p>Компьютер и смартфон на одной подписке. Устройства, срок действия и расход трафика видны в приложении.</p></article>
                <article data-reveal data-reveal-delay="160"><span class="section-number">03 / БИЗНЕСУ</span><h3>Управление доступом</h3><p>Тарифы с большим числом устройств и отдельный договор для компаний. Доступ сотрудникам выдаём и отзываем по вашему запросу.</p></article>
            </div>
        </div>
    </section>
    <section class="site-section">
        <div class="wb-container faq-layout">
            <h2 data-reveal>Коротко.<br><em>По существу.</em></h2>
            @include('partials.faq', ['faq' => [
                ['Что такое WAVEBREAK?', 'Платформа защищённого сетевого подключения и управления доступом. Приложение шифрует соединение ваших устройств с серверами WAVEBREAK, а в аккаунте собраны подписка, устройства и доступные локации.'],
                ['Нужна ли подписка WAVEBREAK?', 'Только для использования нашего сервиса. Совместимые профили других провайдеров можно добавить в приложение отдельно, без подписки.'],
                ['Какие данные собирает WAVEBREAK?', 'Для аккаунта достаточно e-mail. Мы не собираем содержимое трафика и историю посещённых ресурсов. Подробнее — в <a href="/privacy">политике обработки персональных данных</a>.'],
                ['Где войти в личный кабинет?', 'В приложении для компьютера или смартфона. Веб-кабинета для клиентов нет.'],
                ['Где скачать приложение?', 'На <a href="/download">странице приложений</a>: версии для Windows и Android доступны сейчас, iOS — скоро.'],
            ]])
        </div>
    </section>
</main>
@endsection
