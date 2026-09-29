@extends('layout')
@php use App\Support\Locales; @endphp
@section('title', __('site.home.title'))
@section('description', __('site.home.description'))
@section('body_class', 'wb-public page-home')
@section('content')
<main id="main">
    <section class="download-hero site-hero" aria-labelledby="home-title">
        @include('partials.tide')
        <div class="wb-container site-hero-inner">
            <div class="hero-copy" data-reveal>
                <h1 id="home-title" class="brand-heading"><span class="download-kicker hero-kicker"><span></span> {{ __('site.home.kicker') }}</span> WAVEBREAK</h1>
                <p class="hero-statement">{!! __('site.home.statement') !!}</p>
                <p class="hero-description">{{ __('site.home.lede') }}</p>
                <a class="download-discover" href="{{ Locales::path('download') }}"><span>{{ __('site.home.cta') }}</span><span aria-hidden="true">↗</span></a>
            </div>
            <div class="hero-bottom"><span>Windows / Android / iOS</span><a href="#choice">{{ __('site.home.more') }} <span aria-hidden="true">↓</span></a></div>
        </div>
    </section>
    <section class="site-section" id="choice" aria-labelledby="choice-title">
        <div class="wb-container">
            <div class="section-heading" data-reveal><p class="download-kicker"><span></span> {{ __('site.home.choice_kicker') }}</p><h2 id="choice-title">{!! __('site.home.choice_title') !!}</h2></div>
            <div class="choice-grid">
                @foreach (__('site.home.choice') as $i => [$number, $heading, $text, $link])
                    <article data-reveal><span class="section-number">{{ $number }}</span><h3>{{ $heading }}</h3><p>{{ $text }}</p><a class="text-link" href="{{ $i === 0 ? Locales::path('pricing') : Locales::path('access').'#profiles' }}">{{ $link }} <span aria-hidden="true">↗</span></a></article>
                @endforeach
            </div>
        </div>
    </section>
    <section class="site-section product-band" aria-labelledby="app-title">
        <div class="wb-container product-layout">
            <div data-reveal><p class="download-kicker"><span></span> {{ __('site.home.app_kicker') }}</p><h2 id="app-title">{!! __('site.home.app_title') !!}</h2><p class="section-copy">{{ __('site.home.app_text') }}</p><a class="text-link" href="{{ Locales::path('download') }}">{{ __('site.home.app_link') }} <span aria-hidden="true">↗</span></a></div>
            <div class="product-globe" aria-hidden="true">
                <span class="download-core-ring"><i class="download-globe-meridian"></i><i class="download-globe-latitude"></i><img src="{{ asset('images/wavebreak-mark.png') }}" alt=""></span>
                <span class="section-number">{{ __('site.home.app_label') }}</span>
            </div>
        </div>
    </section>
    <section class="site-section" aria-labelledby="audience-title">
        <div class="wb-container">
            <div class="section-heading" data-reveal><p class="download-kicker"><span></span> {{ __('site.home.audience_kicker') }}</p><h2 id="audience-title">{!! __('site.home.audience_title') !!}</h2></div>
            <div class="choice-grid choice-grid--three">
                @foreach (__('site.home.audience') as $i => [$number, $heading, $text])
                    <article data-reveal @if ($i) data-reveal-delay="{{ $i * 80 }}" @endif><span class="section-number">{{ $number }}</span><h3>{{ $heading }}</h3><p>{{ $text }}</p></article>
                @endforeach
            </div>
        </div>
    </section>
    <section class="site-section">
        <div class="wb-container faq-layout">
            <h2 data-reveal>{!! __('site.home.faq_title') !!}</h2>
            @include('partials.faq', ['faq' => __('site.home.faq')])
        </div>
    </section>
</main>
@endsection
