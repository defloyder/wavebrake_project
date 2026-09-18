@extends('layout')

@section('title', 'WAVEBREAK - защищенная инфраструктура для бизнеса')
@section('description', 'WAVEBREAK собирает тарифы, серверы доступа и внешние ссылки подключения в одном спокойном приложении для бизнеса и личных рабочих профилей.')
@section('body_class', 'wb-shell wb-public wb-art-page')

@push('schema')
<script type="application/ld+json">
{
  "@@context": "https://schema.org",
  "@@type": "Organization",
  "name": "WAVEBREAK",
  "url": "{{ rtrim(config('app.url'), '/') }}",
  "logo": "{{ asset('images/wavebreak-logo.png') }}",
  "description": "Защищенная инфраструктура для бизнеса: тарифы, серверы доступа и управление в приложении."
}
</script>
@endpush

@section('content')
@include('partials.public-header', ['active' => 'home'])

<main class="art-site">
    <section class="art-hero" id="top">
        <div class="art-noise" aria-hidden="true"></div>

        <div class="wb-container art-hero-grid">
            <div class="art-copy" data-reveal>
                <p class="art-kicker">WAVEBREAK</p>
                <h1>Разбивает волны помех —<br>оставляет тишину.</h1>
                <p>
                    WAVEBREAK держит защищённое соединение там, где обычные сервисы доступа обрываются:
                    агрессивные блокировки, шаткий Wi-Fi, мобильная сеть в метро.
                    Один линк — и всё просто работает.
                </p>
                <div class="art-actions">
                    <a href="/download" class="wb-btn wb-btn--primary">Скачать приложение</a>
                    <a href="#reveal" class="wb-btn">Как это работает</a>
                </div>
                <p class="art-tagline">VLESS · Hysteria2 — канал выбирается сам, вручную ничего не нужно</p>
            </div>

            <div class="art-wave-scene" data-reveal data-reveal-delay="120">
                <div class="art-wave-panel">
                    <canvas id="wb-wave" role="img" aria-label="Волна связи, которая держит форму"></canvas>
                    <span class="art-wave-badge">соединение стабильно</span>
                </div>
                <p class="art-wave-meta">
                    <span>NL · AMS-01 → устройство</span>
                    <span>REALITY / TLS 1.3</span>
                </p>
            </div>
        </div>
    </section>

    <section class="art-reveal" id="reveal">
        <div class="wb-container art-reveal-grid art-glass" data-reveal>
            <div class="art-index">01</div>
            <div>
                <p class="art-kicker">как это работает</p>
                <h2>Транспорт меняется на лету. Вы этого не замечаете.</h2>
            </div>
            <p>
                Один линк подключает подходящий транспорт — VLESS или Hysteria2 —
                и держит его, даже когда сеть мешает. Вы просто открываете
                приложение и работаете.
            </p>
        </div>
    </section>

    <section class="art-three">
        <div class="wb-container art-three-grid" data-reveal="stagger">
            <article>
                <span>01</span>
                <h3>Держит канал</h3>
                <p>Блокировки, слабый Wi-Fi, мобильный интернет — профиль сам переключает транспорт, чтобы соединение не падало.</p>
            </article>
            <article>
                <span>02</span>
                <h3>Один линк на всё</h3>
                <p>Ссылка обновляется сама. Меняется сервер — пересылать новый конфиг не нужно.</p>
            </article>
            <article>
                <span>03</span>
                <h3>Видно, что происходит</h3>
                <p>Статус, трафик и устройства всегда под рукой в приложении.</p>
            </article>
        </div>
    </section>

    <section class="art-details">
        <div class="wb-container art-details-grid" data-reveal>
            <div>
                <p class="art-kicker">глубже</p>
                <h2>Коротко — выше. Подробности — здесь.</h2>
            </div>
            <div class="art-accordion">
                <details open>
                    <summary>Для бизнеса</summary>
                    <p>Подключаете тариф, выдаёте доступ клиенту и не собираете конфиги вручную под каждое устройство.</p>
                </details>
                <details>
                    <summary>Для личного использования</summary>
                    <p>Держите тарифы разных провайдеров в одном приложении вместо десятка отдельных ссылок.</p>
                </details>
                <details>
                    <summary>Для команды</summary>
                    <p>Видите, у кого какой доступ и какой тариф, без таблиц и переписки в чатах.</p>
                </details>
            </div>
        </div>
    </section>

    <section class="art-final">
        <div class="wb-container art-glass" data-reveal>
            <h2>Один аккаунт. Одна ссылка. Готово.</h2>
            <a href="/download" class="wb-btn wb-btn--primary">Скачать приложение</a>
        </div>
    </section>
</main>

<footer class="art-footer">
    <div class="wb-container art-footer-grid">
        <a href="/" class="art-footer-brand" aria-label="WAVEBREAK">
            <img src="{{ asset('images/wavebreak-logo.png') }}" alt="">
            <span class="wb-brand-name"><span class="wb-brand-wave">WAVE</span><span class="wb-brand-break">BREAK</span></span>
        </a>
        <nav aria-label="Нижняя навигация">
            <a href="/">Главная</a>
            <a href="/pricing">Тарифы</a>
            <a href="/access">Технология</a>
            <a href="/download">Скачать</a>
        </nav>
        <span>© {{ date('Y') }}</span>
    </div>
</footer>
@endsection
