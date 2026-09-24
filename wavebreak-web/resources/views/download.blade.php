@extends('layout')

@section('title', 'Скачать WAVEBREAK')
@section('description', 'WAVEBREAK для компьютера и смартфона. Один аккаунт, ваши профили и управление защищённым подключением внутри приложения.')
@section('body_class', 'wb-shell wb-public wb-download-page')

@section('content')


<main id="main" class="download-site">
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
                <span>Windows и Android доступны, остальные сборки готовятся</span>
                <b>02</b>
            </div>

            <div class="download-platform-switch" id="platforms" data-platform-switch data-reveal data-reveal-delay="260">
                <div class="download-platform-glass" aria-hidden="true"></div>
                <a class="download-platform-btn" href="{{ asset('downloads/wavebreak-windows.exe') }}" data-platform="0" download>
                    <span class="download-platform-index">01</span>
                    <span><b>Windows</b><small>Десктоп</small></span>
                    <em>Скачать</em>
                </a>
                <a class="download-platform-btn" href="{{ asset('downloads/wavebreak-android.apk') }}" data-platform="1" download>
                    <span class="download-platform-index">02</span>
                    <span><b>Android</b><small>Смартфон</small></span>
                    <em>Скачать</em>
                </a>
                <button type="button" class="download-platform-btn" data-platform="2" aria-describedby="release-note" disabled>
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
                    <span class="download-device-mode">АВТО</span>
                    <b class="download-device-location">Самая быстрая</b>
                    <span class="download-core-ring">
                        <i class="download-globe-meridian"></i>
                        <i class="download-globe-latitude"></i>
                        <img src="{{ asset('images/wavebreak-mark.png') }}" alt="">
                    </span>
                    <strong>Не подключено</strong>
                    <small>Нажмите для подключения</small>
                </div>
            </div>

            <div class="download-flow" aria-hidden="true">
                <span></span><span></span><span></span>
            </div>

            <div class="download-device download-device--phone">
                <div class="download-phone-island"></div>
                <div class="download-device-core">
                    <span class="download-device-mode">АВТО</span>
                    <b class="download-device-location">Самая быстрая</b>
                    <span class="download-core-ring">
                        <i class="download-globe-meridian"></i>
                        <i class="download-globe-latitude"></i>
                        <img src="{{ asset('images/wavebreak-mark.png') }}" alt="">
                    </span>
                    <strong>Не подключено</strong>
                    <small>Нажмите для подключения</small>
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
                <h3>Выбор локации</h3>
                <p>Выбирайте доступную локацию и проверяйте состояние подключения в приложении.</p>
            </div>
        </div>
    </section>

    <section class="download-release" id="release-note">
        <div class="wb-container" data-reveal>
            <p class="download-kicker"><span></span> Скоро здесь</p>
            <h2>Windows и Android уже доступны.<br>iOS — после публикации сборки.</h2>
            <p>Официальные сборки для Windows и Android доступны для скачивания выше. iOS появится здесь по мере готовности.</p>
        </div>
    </section>
</main>


@endsection
