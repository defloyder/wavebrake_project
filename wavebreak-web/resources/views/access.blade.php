@extends('layout')
@php use App\Support\Locales; @endphp
@section('title', __('site.access.title'))
@section('description', __('site.access.description'))
@section('breadcrumb', __('site.nav.access'))
@section('body_class', 'wb-public page-access')
@section('content')
<main id="main">
    <section class="download-hero site-hero site-hero--compact" aria-labelledby="access-title">
        @include('partials.tide')
        <div class="wb-container site-hero-inner">
            <div class="hero-copy" data-reveal>
                <p class="download-kicker"><span></span> {{ __('site.access.kicker') }}</p>
                <h1 id="access-title">{!! __('site.access.h1') !!}</h1>
                <p class="hero-description">{{ __('site.access.lede') }}</p>
                <a class="download-discover" href="#profiles"><span>{{ __('site.access.discover') }}</span><span aria-hidden="true">↓</span></a>
            </div>
            <div class="hero-bottom"><span>{{ __('site.access.bottom')[0] }}</span><span>{{ __('site.access.bottom')[1] }}</span></div>
        </div>
    </section>
    <section class="site-section" id="profiles">
        <div class="wb-container">
            <div class="section-heading" data-reveal><p class="download-kicker"><span></span> {{ __('site.access.profiles_kicker') }}</p><h2>{!! __('site.access.profiles_title') !!}</h2></div>
            <div class="choice-grid">
                @foreach (__('site.access.profiles') as [$number, $heading, $text])
                    <article data-reveal><span class="section-number">{{ $number }}</span><h3>{{ $heading }}</h3><p>{{ $text }}</p></article>
                @endforeach
            </div>
        </div>
    </section>
    <section class="site-section product-band">
        <div class="wb-container steps-layout"><div data-reveal><p class="download-kicker"><span></span> {{ __('site.access.steps_kicker') }}</p><h2>{!! __('site.access.steps_title') !!}</h2></div>
            <ol class="steps">
                @foreach (__('site.access.steps') as $i => [$heading, $text])
                    <li><span>{{ str_pad($i + 1, 2, '0', STR_PAD_LEFT) }}</span><div><h3>{{ $heading }}</h3><p>{{ $text }}</p></div></li>
                @endforeach
            </ol>
        </div>
    </section>
    <section class="site-section product-band" aria-labelledby="access-band-title">
        <div class="wb-container product-layout">
            <div data-reveal><p class="download-kicker"><span></span> {{ __('site.access.band_kicker') }}</p><h2 id="access-band-title">{!! __('site.access.band_title') !!}</h2><p class="section-copy">{{ __('site.access.band_text') }}</p><a class="text-link" href="{{ Locales::path('download') }}">{{ __('site.access.band_link') }} <span aria-hidden="true">↗</span></a></div>
            <div class="product-globe" aria-hidden="true">
                @include('partials.globe')
                <span class="section-number">{{ __('site.access.band_label') }}</span>
            </div>
        </div>
    </section>
    <section class="site-section">
        <div class="wb-container faq-layout"><h2>{!! __('site.access.faq_title') !!}</h2>@include('partials.faq', ['faq' => __('site.access.faq')])</div>
    </section>
    <section class="site-cta"><div class="wb-container"><h2>{!! __('site.access.cta_title') !!}</h2><a href="{{ Locales::path('download') }}" class="download-discover"><span>{{ __('site.access.cta_link') }}</span><span aria-hidden="true">↗</span></a></div></section>
</main>
@endsection
