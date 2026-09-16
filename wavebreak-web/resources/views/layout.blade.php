<!doctype html>
<html lang="ru">
<head>
    <script>document.documentElement.classList.add('js');</script>
    @php
        $siteUrl = rtrim(config('app.url'), '/');
        $canonical = trim($__env->yieldContent('canonical')) ?: $siteUrl . request()->getPathInfo();
        $description = trim($__env->yieldContent('description')) ?: 'WAVEBREAK - защищенная инфраструктура для бизнеса: кабинет, тарифы, серверы доступа и свои ссылки подключения.';
        $image = trim($__env->yieldContent('og_image')) ?: asset('images/wavebreak-logo.png');
        $title = trim($__env->yieldContent('title')) ?: 'WAVEBREAK - защищенная инфраструктура для бизнеса';
        $cssPath = public_path('css/wavebreak-site.css');
        $cssVersion = file_exists($cssPath) ? filemtime($cssPath) : time();
    @endphp
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="csrf-token" content="{{ csrf_token() }}">
    <title>{{ $title }}</title>
    <meta name="description" content="{{ $description }}">
    <meta name="robots" content="@yield('robots', 'index, follow, max-image-preview:large')">
    <link rel="canonical" href="{{ $canonical }}">
    <meta property="og:type" content="@yield('og_type', 'website')">
    <meta property="og:site_name" content="WAVEBREAK">
    <meta property="og:title" content="{{ $title }}">
    <meta property="og:description" content="{{ $description }}">
    <meta property="og:url" content="{{ $canonical }}">
    <meta property="og:image" content="{{ $image }}">
    <meta name="twitter:card" content="summary_large_image">
    <meta name="twitter:title" content="{{ $title }}">
    <meta name="twitter:description" content="{{ $description }}">
    <meta name="theme-color" content="#050812">
    <link rel="icon" href="{{ asset('favicon.ico') }}">
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800;900&family=JetBrains+Mono:wght@500;700&display=swap" rel="stylesheet">
    <link rel="stylesheet" href="{{ asset('css/wavebreak-site.css') }}?v={{ $cssVersion }}">
    @stack('schema')
    @stack('styles')
</head>
<body class="@yield('body_class')">
    @yield('content')
    @stack('scripts')
    <script src="{{ asset('js/wavebreak-motion.js') }}" defer></script>
</body>
</html>
