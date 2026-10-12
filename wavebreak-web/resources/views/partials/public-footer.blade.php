@php use App\Support\Locales; @endphp
<footer class="site-footer">
    <div class="wb-container footer-top">
        <a href="{{ Locales::path('home') }}" class="wb-brand" aria-label="{{ __('site.meta.brand_home') }}">
            <img src="{{ asset('images/wavebreak-mark.png') }}" width="56" height="40" alt="">
            <span class="wb-brand-name">WAVE<span>BREAK</span></span>
        </a>
        <p>{!! __('site.footer.tagline') !!}</p>
    </div>
    <div class="wb-container footer-bottom">
        <nav aria-label="{{ __('site.meta.nav_footer') }}">
            <a href="{{ Locales::path('home') }}">{{ __('site.nav.home') }}</a>
            <a href="{{ Locales::path('pricing') }}">{{ __('site.nav.pricing') }}</a>
            <a href="{{ Locales::path('access') }}">{{ __('site.nav.access') }}</a>
            <a href="{{ Locales::path('download') }}">{{ __('site.nav.apps') }}</a>
        </nav>
        <div class="footer-legal">
            <a href="{{ Locales::path('terms') }}">{{ __('site.footer.terms') }}</a>
            <a href="{{ Locales::path('privacy') }}">{{ __('site.footer.privacy') }}</a>
            <a href="mailto:support@wavebreak.com.tr">support@wavebreak.com.tr</a>
            <small>© {{ date('Y') }} WAVEBREAK</small>
        </div>
    </div>
</footer>
