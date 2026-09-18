@extends('layout')

@section('title', 'Скачать WAVEBREAK')
@section('description', 'WAVEBREAK для компьютера и смартфона. Один аккаунт, ваши профили и управление защищённым подключением внутри приложения.')
@section('body_class', 'wb-shell wb-public wb-download-page')

@section('content')
@include('partials.public-header', ['active' => 'download'])

<main class="download-site">
    <section class="download-hero" aria-labelledby="download-title">
        <canvas id="download-tide" aria-hidden="true"></canvas>
        <div class="download-grid" aria-hidden="true"></div>
        <div class="download-wordmark download-wordmark--wave" aria-hidden="true">WAVE</div>
        <div class="download-wordmark download-wordmark--break" aria-hidden="true">BREAK</div>

        <div class="wb-container download-hero-inner">
            <div class="download-intro" data-reveal>
                <p class="download-kicker"><span></span> Приложение WAVEBREAK</p>
                <h1 id="download-title">Волна меняется.<br><em>Доступ остаётся.</em></h1>
                <p>Аккаунт, тарифы и ваши ссылки живут там, где вы ими пользуетесь: на компьютере и в смартфоне.</p>
                <a class="download-discover" href="#platforms">
                    <span>Выбрать платформу</span>
                    <span aria-hidden="true">↓</span>
                </a>
            </div>

            <div class="download-signal" data-reveal data-reveal-delay="180" aria-label="Статус подготовки приложений">
                <span class="download-signal-dot"></span>
                <span>Сборки готовятся</span>
                <b>01</b>
            </div>

            <div class="download-platform-switch" id="platforms" data-platform-switch data-reveal data-reveal-delay="260">
                <div class="download-platform-glass" aria-hidden="true"></div>
                <button type="button" data-platform="0" aria-describedby="release-note" disabled>
                    <span class="download-platform-index">01</span>
                    <span><b>Windows</b><small>Десктоп</small></span>
                    <em>Скоро</em>
                </button>
                <button type="button" data-platform="1" aria-describedby="release-note" disabled>
                    <span class="download-platform-index">02</span>
                    <span><b>Android</b><small>Смартфон</small></span>
                    <em>Скоро</em>
                </button>
                <button type="button" data-platform="2" aria-describedby="release-note" disabled>
                    <span class="download-platform-index">03</span>
                    <span><b>iOS</b><small>Смартфон</small></span>
                    <em>Скоро</em>
                </button>
            </div>
        </div>
    </section>

    <section class="download-continuity" aria-labelledby="continuity-title">
        <div class="wb-container download-continuity-head" data-reveal>
            <p class="download-kicker"><span></span> Один ритм</p>
            <h2 id="continuity-title">Начали на компьютере.<br>Продолжили в телефоне.</h2>
            <p>Профили и состояние аккаунта остаются понятными на каждом устройстве. Без веб-кабинета и лишних переходов.</p>
        </div>

        <div class="wb-container download-device-scene" data-reveal data-reveal-delay="120">
            <div class="download-device download-device--desktop">
                <div class="download-device-bar"><i></i><span>WAVEBREAK / DESKTOP</span><b>готово</b></div>
                <div class="download-device-core">
                    <span class="download-core-ring"></span>
                    <strong>Ваша волна</strong>
                    <small>одним касанием</small>
                </div>
            </div>

            <div class="download-flow" aria-hidden="true">
                <span></span><span></span><span></span>
            </div>

            <div class="download-device download-device--phone">
                <div class="download-phone-island"></div>
                <div class="download-device-core">
                    <span class="download-core-ring"></span>
                    <strong>WAVEBREAK</strong>
                    <small>профиль синхронизирован</small>
                </div>
            </div>
        </div>
    </section>

    <section class="download-manifest" aria-label="Возможности приложений">
        <div class="wb-container download-manifest-grid">
            <div data-reveal>
                <span>01</span>
                <h3>Свои ссылки</h3>
                <p>Добавляйте профили других сервисов рядом с WAVEBREAK.</p>
            </div>
            <div data-reveal data-reveal-delay="80">
                <span>02</span>
                <h3>Всё на месте</h3>
                <p>Тариф, расход и устройства собраны внутри приложения.</p>
            </div>
            <div data-reveal data-reveal-delay="160">
                <span>03</span>
                <h3>Сеть меняется</h3>
                <p>Приложение восстанавливает соединение при переходе между сетями.</p>
            </div>
        </div>
    </section>

    <section class="download-release" id="release-note">
        <div class="wb-container" data-reveal>
            <p class="download-kicker"><span></span> Скоро здесь</p>
            <h2>Ссылки появятся<br>после публикации сборок.</h2>
            <p>Эта страница станет единственной официальной точкой загрузки приложений WAVEBREAK.</p>
        </div>
    </section>
</main>

<footer class="art-footer download-footer">
    <div class="wb-container art-footer-grid">
        <a href="/" class="art-footer-brand" aria-label="WAVEBREAK">
            <img src="{{ asset('images/wavebreak-logo.png') }}" alt="">
            <span class="wb-brand-name"><span class="wb-brand-wave">WAVE</span><span class="wb-brand-break">BREAK</span></span>
        </a>
        <nav aria-label="Нижняя навигация">
            <a href="/">Главная</a>
            <a href="/pricing">Тарифы</a>
            <a href="/access">Технология</a>
        </nav>
        <span>© {{ date('Y') }}</span>
    </div>
</footer>
@endsection
