@extends('layout')
@php use App\Support\Locales; @endphp
@section('title', __('site.download.title'))
@section('description', __('site.download.description'))
@section('breadcrumb', __('site.nav.apps'))
@section('body_class', 'wb-shell wb-public wb-download-page')

@php
    // priceCurrency was hardcoded 'RUB' on every locale even though the
    // download itself is free and the currency has no real meaning here —
    // still, claiming RUB specifically on /en and /tr is misleading. Pick
    // it from the page's own locale instead of assuming Russia.
    $downloadCurrency = ['ru' => 'RUB', 'en' => 'USD', 'tr' => 'TRY'][Locales::current()] ?? 'USD';

    // The Windows build isn't a static file in public/downloads (only the
    // Android .apk is) — it ships from the real update mirror, versioned, in
    // version-windows.json (the same manifest the desktop app's own updater
    // reads). Read the current release URL from there instead of pointing
    // at a local file that was never actually deployed.
    $windowsManifestPath = public_path('downloads/version-windows.json');
    $windowsDownloadUrl = null;
    if (file_exists($windowsManifestPath)) {
        $windowsManifest = json_decode(file_get_contents($windowsManifestPath), true);
        $windowsDownloadUrl = $windowsManifest['url'] ?? null;
    }
    $windowsDownloadUrl ??= asset('downloads/wavebreak-windows.exe');
@endphp
@push('schema')
<script type="application/ld+json">{!! json_encode([
    '@context' => 'https://schema.org',
    '@type' => 'SoftwareApplication',
    'name' => 'WAVEBREAK',
    'description' => __('site.meta.app_description'),
    'applicationCategory' => 'SecurityApplication',
    'operatingSystem' => 'Windows, Android, iOS',
    'inLanguage' => ['ru', 'en', 'tr'],
    'url' => Locales::url('download'),
    'downloadUrl' => Locales::url('download'),
    'image' => 'https://wavebreak.com.tr/images/og-cover.png',
    'publisher' => ['@id' => 'https://wavebreak.com.tr/#organization'],
    'offers' => ['@type' => 'Offer', 'price' => '0', 'priceCurrency' => $downloadCurrency],
], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_HEX_TAG) !!}</script>
@endpush
@section('content')


<main id="main" class="download-site">
    <section class="download-hero" aria-labelledby="download-title">
        <canvas id="download-tide" aria-hidden="true"></canvas>
        <div class="download-grid" aria-hidden="true"></div>
        <div class="download-wordmark download-wordmark--wave" aria-hidden="true">WAVE</div>
        <div class="download-wordmark download-wordmark--break" aria-hidden="true">BREAK</div>

        <div class="wb-container download-hero-inner">
            <div class="download-intro" data-reveal>
                <p class="download-kicker"><span></span> {{ __('site.download.kicker') }}</p>
                <h1 id="download-title">{!! __('site.download.h1') !!}</h1>
                <p>{{ __('site.download.lede') }}</p>
                <a class="download-discover" href="#platforms">
                    <span>{{ __('site.download.choose') }}</span>
                    <span aria-hidden="true">↓</span>
                </a>
            </div>

            <div class="download-signal" data-reveal data-reveal-delay="180" aria-label="{{ __('site.download.signal_label') }}">
                <span class="download-signal-dot"></span>
                <span>{{ __('site.download.signal') }}</span>
                <b>02</b>
            </div>

            <div class="download-platform-switch" id="platforms" data-platform-switch data-reveal data-reveal-delay="260">
                <div class="download-platform-glass" aria-hidden="true"></div>
                <a class="download-platform-btn" href="{{ $windowsDownloadUrl }}" data-platform="0" download>
                    <span class="download-platform-index">01</span>
                    <span><b>Windows</b><small>{{ __('site.download.desktop') }}</small></span>
                    <em>{{ __('site.download.get') }}</em>
                </a>
                <a class="download-platform-btn" href="{{ asset('downloads/wavebreak-android.apk') }}" data-platform="1" download>
                    <span class="download-platform-index">02</span>
                    <span><b>Android</b><small>{{ __('site.download.phone') }}</small></span>
                    <em>{{ __('site.download.get') }}</em>
                </a>
                <button type="button" class="download-platform-btn" data-platform="2" aria-describedby="release-note" disabled>
                    <span class="download-platform-index">03</span>
                    <span><b>iOS</b><small>{{ __('site.download.phone') }}</small></span>
                    <em>{{ __('site.download.soon') }}</em>
                </button>
            </div>
        </div>
    </section>

    <section class="download-continuity" aria-labelledby="continuity-title">
        <div class="wb-container download-continuity-head" data-reveal>
            <p class="download-kicker"><span></span> {{ __('site.download.cont_kicker') }}</p>
            <h2 id="continuity-title">{!! __('site.download.cont_title') !!}</h2>
            <p>{{ __('site.download.cont_text') }}</p>
        </div>

        <div class="wb-container download-device-scene" data-reveal data-reveal-delay="120">
            <div class="download-device download-device--desktop">
                <div class="download-device-bar"><i></i><span>WAVEBREAK / DESKTOP</span><b>{{ __('site.download.ready') }}</b></div>
                <div class="download-device-core">
                    <span class="download-device-mode">{{ __('site.download.mode_auto') }}</span>
                    <b class="download-device-location">{{ __('site.download.fastest') }}</b>
                    @include('partials.globe')
                    <strong>{{ __('site.download.not_connected') }}</strong>
                    <small>{{ __('site.download.tap') }}</small>
                </div>
            </div>

            <div class="download-flow" aria-hidden="true">
                <span></span><span></span><span></span>
            </div>

            <div class="download-device download-device--phone">
                <div class="download-phone-island"></div>
                <div class="download-device-core">
                    <span class="download-device-mode">{{ __('site.download.mode_auto') }}</span>
                    <b class="download-device-location">{{ __('site.download.fastest') }}</b>
                    @include('partials.globe')
                    <strong>{{ __('site.download.not_connected') }}</strong>
                    <small>{{ __('site.download.tap') }}</small>
                </div>
            </div>
        </div>
    </section>

    <section class="download-manifest" aria-label="{{ __('site.download.manifest_label') }}">
        <div class="wb-container download-manifest-grid">
            <div data-reveal>
                <span>01</span>
                <h3>{{ __('site.download.manifest')[0][0] }}</h3>
                <p>{{ __('site.download.manifest')[0][1] }}</p>
            </div>
            <div data-reveal data-reveal-delay="80">
                <span>02</span>
                <h3>{{ __('site.download.manifest')[1][0] }}</h3>
                <p>{{ __('site.download.manifest')[1][1] }}</p>
            </div>
            <div data-reveal data-reveal-delay="160">
                <span>03</span>
                <h3>{{ __('site.download.manifest')[2][0] }}</h3>
                <p>{{ __('site.download.manifest')[2][1] }}</p>
            </div>
        </div>
    </section>

    <section class="download-release" id="release-note">
        <div class="wb-container" data-reveal>
            <p class="download-kicker"><span></span> {{ __('site.download.release_kicker') }}</p>
            <h2>{!! __('site.download.release_title') !!}</h2>
            <p>{{ __('site.download.release_text') }}</p>
        </div>
    </section>
</main>


@endsection
