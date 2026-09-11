<!doctype html>
<html lang="ru" prefix="og: https://ogp.me/ns#">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <meta name="csrf-token" content="{{ csrf_token() }}">
    <title>{{ $meta['title'] ?? 'Auralith' }}</title>
    @if(! empty($meta['description']))
        <meta name="description" content="{{ $meta['description'] }}">
    @endif
    <meta name="robots" content="{{ $meta['robots'] ?? 'index, follow, max-snippet:-1, max-image-preview:large' }}">
    @if(! empty($meta['canonical']))
        <link rel="canonical" href="{{ $meta['canonical'] }}">
    @endif
    <meta property="og:type" content="{{ $meta['og_type'] ?? 'website' }}">
    <meta property="og:title" content="{{ $meta['og_title'] ?? ($meta['title'] ?? 'Auralith') }}">
    @if(! empty($meta['description']))
        <meta property="og:description" content="{{ $meta['description'] }}">
    @endif
    <meta property="og:image" content="{{ url('/images/logo-mark.png') }}?v=brand4">
    <meta property="og:locale" content="ru_RU">
    <meta property="og:site_name" content="Auralith">
    <link rel="icon" type="image/png" sizes="32x32" href="{{ asset('images/favicon-32.png') }}?v=brand4">
    <link rel="apple-touch-icon" sizes="180x180" href="{{ asset('images/apple-touch-icon.png') }}?v=brand4">
    <link rel="stylesheet" href="{{ asset('css/landing.css') }}?v=50">
    <link rel="stylesheet" href="{{ asset('css/faq.css') }}">
    <link rel="stylesheet" href="{{ asset('css/legal.css') }}">
    <link rel="stylesheet" href="{{ asset('css/auth.css') }}?v=9">
    <link rel="stylesheet" href="{{ asset('css/public-redesign.css') }}?v=28">
    @viteReactRefresh
    @php
        $publicRoutes = ($routes ?? []) + [
            'home' => route('home', [], false),
            'b2b' => route('b2b', [], false),
            'faq' => route('faq', [], false),
            'offer' => route('offer', [], false),
            'privacy' => route('privacy_policy', [], false),
            'legal' => route('legal_info', [], false),
            'cookies' => route('cookie_policy', [], false),
            'profile' => route('profile.index', [], false),
            'login' => route('login', [], false),
            'loginSubmit' => route('login.submit', [], false),
            'register' => route('register', [], false),
            'registerSubmit' => route('register.submit', [], false),
            'forgot' => route('account-recovery.request', [], false),
            'forgotSubmit' => route('account-recovery.request.submit', [], false),
            'contact' => route('contact.store', [], false),
            'telegramStatus' => route('auth.telegram-login.status.alias', [], false),
        ];
    @endphp
    <script>
        window.AURALITH_ROUTES = @json($publicRoutes, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
        window.AURALITH_LEGAL = @json(config('legal'), JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    </script>
    @vite('resources/js/public.jsx')
    @if(! empty($schema))
        <script type="application/ld+json">{!! json_encode($schema, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) !!}</script>
    @endif
</head>
<body class="{{ $bodyClass ?? '' }}">
<div
    id="public-react-root"
    data-page="{{ $page }}"
    data-props='@json($props ?? [], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES)'
></div>
@if(in_array($page, ['offer', 'privacy', 'legal-info', 'cookie-policy'], true))
    @include('partials.legal-static-fallback', ['documentPage' => $page])
@endif
<div hidden>
    @if($page === 'login')
        <span>Вход через Telegram</span>
        <span>Старые ссылки из бота одноразовые</span>
    @elseif($page === 'landing')
        <span>Auralith</span>
        <span>Ауралит</span>
    @elseif($page === 'faq')
        <span>FAQ</span>
    @endif
</div>
</body>
</html>
