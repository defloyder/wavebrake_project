<header class="wb-header">
    <div class="wb-container wb-nav">
        <a href="/" class="wb-brand" aria-label="WAVEBREAK, главная">
            <img src="{{ asset('images/wavebreak-mark.png') }}" width="56" height="40" alt="">
            <span class="wb-brand-name">WAVE<span>BREAK</span></span>
        </a>
        <button type="button" class="wb-burger" id="wb-burger" aria-label="Открыть меню" aria-expanded="false" aria-controls="wb-nav-panel"><span></span><span></span></button>
        <div class="wb-nav-panel" id="wb-nav-panel">
            <nav class="wb-links" aria-label="Основная навигация" data-glass-nav>
                <span class="nav-glass" aria-hidden="true"></span>
                @foreach (['home' => ['/', 'Главная'], 'pricing' => ['/pricing', 'Тарифы'], 'access' => ['/access', 'Технология']] as $key => [$href, $label])
                    <a href="{{ $href }}" @if ($active === $key) class="is-active" aria-current="page" @endif>{{ $label }}</a>
                @endforeach
            </nav>
            <a href="/download" class="wb-btn wb-btn--primary" @if ($active === 'download') aria-current="page" @endif>Скачать <span aria-hidden="true">↗</span></a>
        </div>
    </div>
</header>
