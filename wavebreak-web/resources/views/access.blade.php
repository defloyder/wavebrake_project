@extends('layout')
@section('title', 'Как работает WAVEBREAK — технология защищённого подключения')
@section('description', 'Как устроен WAVEBREAK: зашифрованное подключение к серверам, выбор локации и импорт совместимых профилей других провайдеров в одном приложении для компьютера и смартфона.')
@section('breadcrumb', 'Технология')
@section('body_class', 'wb-public page-access')
@section('content')
<main id="main">
    <section class="download-hero site-hero site-hero--compact" aria-labelledby="access-title">
        @include('partials.tide')
        <div class="wb-container site-hero-inner">
            <div class="hero-copy" data-reveal>
                <p class="download-kicker"><span></span> Что за этим стоит</p>
                <h1 id="access-title">Технология<br><em>WAVEBREAK.</em></h1>
                <p class="hero-description">Приложение хранит ваши профили и подключается к выбранному серверу. Вы решаете, чьим сервисом пользоваться.</p>
                <a class="download-discover" href="#profiles"><span>Как это устроено</span><span aria-hidden="true">↓</span></a>
            </div>
            <div class="hero-bottom"><span>Ваш профиль / Ваша локация</span><span>Компьютер + Смартфон</span></div>
        </div>
    </section>
    <section class="site-section" id="profiles">
        <div class="wb-container">
            <div class="section-heading" data-reveal><p class="download-kicker"><span></span> Основа подключения</p><h2>Всё начинается<br><em>с профиля.</em></h2></div>
            <div class="choice-grid">
                <article data-reveal><span class="section-number">01 / СЕРВИС WAVEBREAK</span><h3>Профиль из подписки</h3><p>После оформления подписки в приложении появляются доступные подключения WAVEBREAK. Там же можно проверить срок действия и расход трафика.</p></article>
                <article data-reveal><span class="section-number">02 / ДРУГОЙ ПРОВАЙДЕР</span><h3>Профиль по ссылке</h3><p>Добавьте совместимую ссылку подключения или подписки. Локации, срок действия и ограничения в этом случае определяет ваш провайдер.</p></article>
            </div>
        </div>
    </section>
    <section class="site-section product-band">
        <div class="wb-container steps-layout"><div data-reveal><p class="download-kicker"><span></span> В приложении</p><h2>От выбора<br><em>к подключению.</em></h2></div>
            <ol class="steps">
                <li><span>01</span><div><h3>Добавьте профиль</h3><p>Войдите в аккаунт WAVEBREAK или импортируйте свою ссылку.</p></div></li>
                <li><span>02</span><div><h3>Выберите локацию</h3><p>Используйте одну из локаций, доступных в вашем профиле.</p></div></li>
                <li><span>03</span><div><h3>Подключитесь</h3><p>Нажмите на планету. Текущий статус соединения появится на главном экране приложения.</p></div></li>
            </ol>
        </div>
    </section>
    <section class="site-section">
        <div class="wb-container faq-layout"><h2>Чуть<br><em>подробнее.</em></h2>@include('partials.faq', ['faq' => [
                ['Какие подключения есть у WAVEBREAK?', 'В тестовой инфраструктуре доступны Direct-TLS и Hysteria2. Список подключений и локаций отображается в приложении и зависит от вашей подписки.'],
                ['Подойдёт любая сторонняя ссылка?', 'Не любая. Формат ссылки и протокол должны поддерживаться вашей версией приложения. Условия сторонней подписки остаются у её провайдера.'],
                ['Что влияет на скорость?', 'Качество вашей сети, маршрут до сервера и его загрузка. Если соединение нестабильно, попробуйте другую доступную локацию или тип подключения.'],
                ['Где управлять подпиской?', 'В аккаунте внутри приложения. На сайте не нужно регистрироваться или вводить платёжные данные.'],
            ]])</div>
    </section>
    <section class="site-cta"><div class="wb-container"><h2>Следующий шаг.<br><em>Ваше устройство.</em></h2><a href="/download" class="download-discover"><span>Выбрать приложение</span><span aria-hidden="true">↗</span></a></div></section>
</main>
@endsection
