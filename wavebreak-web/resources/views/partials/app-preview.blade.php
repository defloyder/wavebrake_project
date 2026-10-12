<div class="app-preview" data-reveal>
    <div class="app-preview-top"><span>WAVEBREAK</span><svg aria-hidden="true" width="21" height="21" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"><path d="M12 3v8M6.3 5.7a8 8 0 1 0 11.4 0"/></svg></div>
    <div class="app-preview-location"><span class="app-location-icon" aria-hidden="true">◎</span><div><strong>{{ __('site.visual.connection') }}</strong><small>{{ __('site.visual.location') }}</small></div><span aria-hidden="true">›</span></div>
    <div class="app-preview-protocols" aria-hidden="true"><span>Direct</span><span>Hysteria2</span></div>
    <div class="app-preview-globe" aria-hidden="true">
        <div class="earth-fallback"></div>
        <canvas data-earth data-hologram="true" data-texture="{{ asset('images/earth-blue-marble.jpg') }}"></canvas>
        <img src="{{ asset('images/wavebreak-mark.png') }}" alt="" width="110" height="80" loading="lazy">
        <span class="app-globe-orbit"></span>
    </div>
    <div class="app-preview-status"><svg aria-hidden="true" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><path d="m12 3 8 3v6c0 4-4 7-8 9-4-2-8-5-8-9V6z"/><path d="m8.5 12 2.5 2.5 4.5-5"/></svg><strong>{{ __('site.visual.protection') }}</strong><span class="status-light" aria-hidden="true"></span></div>
    <div class="app-preview-tabs"><span>{{ __('site.visual.profiles') }}</span><span>{{ __('site.visual.locations') }}</span><span>{{ __('site.visual.devices') }}</span></div>
    <p class="app-preview-caption">{{ __('site.visual.preview') }}</p>
</div>
