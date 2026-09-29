<!doctype html>
@php
    use App\Support\Locales;

    $locale = Locales::current();
    $page = Locales::page();
    $siteUrl = 'https://wavebreak.com.tr';
    $inLanguage = ['ru' => 'ru-RU', 'en' => 'en-US', 'tr' => 'tr-TR'][$locale];
    $positioning = __('site.meta.positioning');
    $canonical = trim($__env->yieldContent('canonical')) ?: ($page ? Locales::url($page) : $siteUrl.rtrim(request()->getPathInfo(), '/'));
    $description = trim($__env->yieldContent('description')) ?: __('site.meta.description_default');
    $image = trim($__env->yieldContent('og_image')) ?: $siteUrl.'/images/og-cover.png';
    $imageAlt = __('site.meta.og_alt');
    $title = trim($__env->yieldContent('title')) ?: __('site.meta.title_default');
    $crumb = trim($__env->yieldContent('breadcrumb'));
    $cssPath = public_path('css/wavebreak-site.css');
    $cssVersion = file_exists($cssPath) ? filemtime($cssPath) : time();
    $jsPath = public_path('js/wavebreak-motion.js');
    $jsVersion = file_exists($jsPath) ? filemtime($jsPath) : time();
    $webPage = [
        '@type' => 'WebPage',
        '@id' => $canonical.'#webpage',
        'url' => $canonical,
        'name' => $title,
        'description' => $description,
        'inLanguage' => $inLanguage,
        'isPartOf' => ['@id' => $siteUrl.'/#website'],
        'about' => ['@id' => $siteUrl.'/#organization'],
        'primaryImageOfPage' => ['@type' => 'ImageObject', 'url' => $image, 'width' => 1200, 'height' => 630],
    ];
    $graph = [
        [
            '@type' => 'Organization',
            '@id' => $siteUrl.'/#organization',
            'name' => 'WAVEBREAK',
            'alternateName' => 'WAVE BREAK',
            'url' => $siteUrl.'/',
            'logo' => ['@type' => 'ImageObject', 'url' => $siteUrl.'/images/wavebreak-logo.png'],
            'image' => $siteUrl.'/images/og-cover.png',
            'description' => $positioning,
            'email' => 'support@wavebreak.com.tr',
            'contactPoint' => [['@type' => 'ContactPoint', 'contactType' => 'customer support', 'email' => 'support@wavebreak.com.tr', 'availableLanguage' => ['ru', 'en', 'tr']]],
        ],
        [
            '@type' => 'WebSite',
            '@id' => $siteUrl.'/#website',
            'name' => 'WAVEBREAK',
            'url' => $siteUrl.'/',
            'description' => $positioning,
            'inLanguage' => ['ru-RU', 'en-US', 'tr-TR'],
            'publisher' => ['@id' => $siteUrl.'/#organization'],
        ],
    ];
    if ($crumb !== '') {
        $webPage['breadcrumb'] = ['@id' => $canonical.'#breadcrumb'];
        $graph[] = [
            '@type' => 'BreadcrumbList',
            '@id' => $canonical.'#breadcrumb',
            'itemListElement' => [
                ['@type' => 'ListItem', 'position' => 1, 'name' => __('site.meta.crumb_home'), 'item' => Locales::url('home')],
                ['@type' => 'ListItem', 'position' => 2, 'name' => $crumb, 'item' => $canonical],
            ],
        ];
    }
    $graph[] = $webPage;
    $structuredData = ['@context' => 'https://schema.org', '@graph' => $graph];
@endphp
<html lang="{{ $locale }}">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="csrf-token" content="{{ csrf_token() }}">
    <title>{{ $title }}</title>
    <meta name="description" content="{{ $description }}">
    <meta name="robots" content="@yield('robots', 'index, follow, max-snippet:-1, max-image-preview:large, max-video-preview:-1')">
    <link rel="canonical" href="{{ $canonical }}">
    @if ($page)
        @foreach (array_keys(Locales::SUPPORTED) as $code)
    <link rel="alternate" hreflang="{{ $code }}" href="{{ Locales::url($page, $code) }}">
        @endforeach
    <link rel="alternate" hreflang="x-default" href="{{ Locales::url($page, 'en') }}">
    @endif
    <meta name="application-name" content="WAVEBREAK">
    <meta name="apple-mobile-web-app-title" content="WAVEBREAK">
    <meta name="format-detection" content="telephone=no">
    <meta name="theme-color" content="#020507">
    <meta property="og:type" content="@yield('og_type', 'website')">
    <meta property="og:site_name" content="WAVEBREAK">
    <meta property="og:locale" content="{{ Locales::SUPPORTED[$locale][2] }}">
    @foreach (Locales::SUPPORTED as $code => [, , $ogLocale])
        @continue($code === $locale)
    <meta property="og:locale:alternate" content="{{ $ogLocale }}">
    @endforeach
    <meta property="og:title" content="{{ $title }}">
    <meta property="og:description" content="{{ $description }}">
    <meta property="og:url" content="{{ $canonical }}">
    <meta property="og:image" content="{{ $image }}">
    <meta property="og:image:secure_url" content="{{ $image }}">
    <meta property="og:image:type" content="image/png">
    <meta property="og:image:width" content="1200">
    <meta property="og:image:height" content="630">
    <meta property="og:image:alt" content="{{ $imageAlt }}">
    <meta name="twitter:card" content="summary_large_image">
    <meta name="twitter:title" content="{{ $title }}">
    <meta name="twitter:description" content="{{ $description }}">
    <meta name="twitter:image" content="{{ $image }}">
    <meta name="twitter:image:alt" content="{{ $imageAlt }}">
    <link rel="icon" href="{{ asset('favicon.ico') }}" sizes="any">
    <link rel="icon" type="image/png" sizes="192x192" href="{{ asset('images/favicon.png') }}">
    <link rel="apple-touch-icon" href="{{ asset('images/apple-touch-icon.png') }}">
    <link rel="manifest" href="{{ asset('site.webmanifest') }}">
    <link rel="preload" href="{{ asset($locale === 'ru' ? 'fonts/inter-cyrillic.woff2' : 'fonts/inter-latin.woff2') }}" as="font" type="font/woff2" crossorigin>
    <link rel="preload" href="{{ asset('fonts/michroma-latin.woff2') }}" as="font" type="font/woff2" crossorigin>
    <link rel="stylesheet" href="{{ asset('css/wavebreak-fonts.css') }}?v={{ filemtime(public_path('css/wavebreak-fonts.css')) }}">
    <link rel="stylesheet" href="{{ asset('css/wavebreak-site.css') }}?v={{ $cssVersion }}">
    <script type="application/ld+json">{!! json_encode($structuredData, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_HEX_TAG) !!}</script>
    @stack('schema')
    @stack('styles')
</head>
<body class="@yield('body_class')">
    <a class="skip-link" href="#main">{{ __('site.meta.skip') }}</a>
    @include('partials.public-header', ['active' => $page, 'page' => $page, 'locale' => $locale])
    @yield('content')
    @include('partials.public-footer')
    @stack('scripts')
    <script src="{{ asset('js/wavebreak-motion.js') }}?v={{ $jsVersion }}" defer></script>
</body>
</html>
