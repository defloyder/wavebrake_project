@php use App\Support\Locales; @endphp
<header class="wb-header">
    <div class="wb-container wb-nav">
        <a href="{{ Locales::path('home') }}" class="wb-brand" aria-label="{{ __('site.meta.brand_home') }}">
            <img src="{{ asset('images/wavebreak-mark.png') }}" width="56" height="40" alt="">
            <span class="wb-brand-name">WAVE<span>BREAK</span></span>
        </a>
        <button type="button" class="wb-burger" id="wb-burger" aria-label="{{ __('site.meta.open_menu') }}" data-label-open="{{ __('site.meta.open_menu') }}" data-label-close="{{ __('site.meta.close_menu') }}" aria-expanded="false" aria-controls="wb-nav-panel"><span></span><span></span></button>
        <div class="wb-nav-panel" id="wb-nav-panel">
            <nav class="wb-links" aria-label="{{ __('site.meta.nav_main') }}" data-glass-nav>
                <span class="nav-glass" aria-hidden="true"></span>
                @foreach (['home', 'pricing', 'access'] as $key)
                    <a href="{{ Locales::path($key) }}" @if ($active === $key) class="is-active" aria-current="page" @endif>{{ __('site.nav.'.$key) }}</a>
                @endforeach
            </nav>
            <nav class="wb-lang" aria-label="{{ __('site.meta.lang_label') }}">
                @foreach (Locales::SUPPORTED as $code => [$label, $native])
                    <a href="{{ Locales::path($page ?? 'home', $code) }}" hreflang="{{ $code }}" lang="{{ $code }}" title="{{ $native }}" @if ($code === $locale) class="is-active" aria-current="true" @endif>{{ $label }}</a>
                @endforeach
            </nav>
            <a href="{{ Locales::path('download') }}" class="wb-btn wb-btn--primary" @if ($active === 'download') aria-current="page" @endif>{{ __('site.nav.download') }} <span aria-hidden="true">↗</span></a>
        </div>
    </div>
</header>
