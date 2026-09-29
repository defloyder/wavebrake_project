@extends('layout')
@php
    use App\Support\Locales;
    $fmt = fn (float $v) => number_format($v, $v == floor($v) ? 0 : 2, __('site.pricing.decimal'), __('site.pricing.thousands'));
    $monthly = collect($tiers)->pluck('month')->filter()->where('currency', 'RUB');
    $minMonthly = $monthly->min('price');
    $seoOffers = collect($tiers)->flatMap(fn (array $tier) => collect(['month' => __('site.pricing.offer_month'), 'year' => __('site.pricing.offer_year')])
        ->filter(fn ($label, $kind) => $tier[$kind] !== null)
        ->map(fn ($label, $kind) => [
            '@type' => 'Offer',
            'name' => $tier['name'].' — '.$label,
            'price' => number_format($tier[$kind]['price'], 2, '.', ''),
            'priceCurrency' => $tier[$kind]['currency'],
            'url' => Locales::url('pricing'),
            'availability' => 'https://schema.org/InStock',
        ])->values())->values()->all();
@endphp
@section('title', $minMonthly ? __('site.pricing.title_from', ['price' => $fmt($minMonthly).' ₽']) : __('site.pricing.title'))
@section('description', __('site.pricing.description'))
@section('breadcrumb', __('site.nav.pricing'))
@section('body_class', 'wb-public page-pricing')
@if ($seoOffers !== [])
@push('schema')
<script type="application/ld+json">{!! json_encode([
    '@context' => 'https://schema.org',
    '@type' => 'Service',
    'name' => 'WAVEBREAK',
    'serviceType' => __('site.meta.service_type'),
    'provider' => ['@id' => 'https://wavebreak.com.tr/#organization'],
    'areaServed' => 'RU',
    'url' => Locales::url('pricing'),
    'offers' => $seoOffers,
], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_HEX_TAG) !!}</script>
@endpush
@endif
@section('content')
<main id="main">
    <section class="download-hero site-hero site-hero--compact" aria-labelledby="pricing-title">
        @include('partials.tide')
        <div class="wb-container site-hero-inner">
            <div class="hero-copy" data-reveal>
                <p class="download-kicker"><span></span> {{ __('site.pricing.kicker') }}</p>
                <h1 id="pricing-title">{!! __('site.pricing.h1') !!}</h1>
                <p class="hero-description">{{ __('site.pricing.lede') }}</p>
                <a class="download-discover" href="#plans"><span>{{ __('site.pricing.discover') }}</span><span aria-hidden="true">↓</span></a>
            </div>
            <div class="hero-bottom"><span>{{ __('site.pricing.bottom')[0] }}</span><span>{{ __('site.pricing.bottom')[1] }}</span></div>
        </div>
    </section>
    <section class="site-section" id="plans" aria-label="{{ __('site.pricing.plans_label') }}">
        <div class="wb-container">
            @if ($plans === [])
                <div class="plans-unavailable" role="status"><span class="section-number">{{ __('site.pricing.unavailable_num') }}</span><h2>{!! __('site.pricing.unavailable_title') !!}</h2><p>{{ __('site.pricing.unavailable_text') }}</p><a href="{{ Locales::path('pricing') }}" class="text-link">{{ __('site.pricing.reload') }} <span aria-hidden="true">↻</span></a></div>
            @else
                @php
                    $money = $fmt;
                    $switchable = $hasYearly && $hasMonthly;
                @endphp
                <div class="plan-catalog{{ $switchable ? ' plan-catalog--switch' : '' }}">
                    @if ($switchable)
                        <input class="period-radio" type="radio" name="billing-period" id="period-month" value="month" checked>
                        <input class="period-radio" type="radio" name="billing-period" id="period-year" value="year">
                        <div class="period-switch" aria-label="{{ __('site.pricing.period_label') }}">
                            <label for="period-month">{{ __('site.pricing.month') }}</label>
                            <label for="period-year">{{ __('site.pricing.year') }} @if ($maxDiscount)<span class="period-badge">−{{ $maxDiscount }}%</span>@endif</label>
                        </div>
                    @endif
                    <div class="plan-grid">
                        @foreach ($tiers as $tier)
                            <article class="plan" data-reveal>
                                <span class="section-number">{{ str_pad($loop->iteration, 2, '0', STR_PAD_LEFT) }} / {{ __('site.pricing.subscription') }}</span>
                                <h2>{{ $tier['name'] }}</h2>
                                @foreach (['month', 'year'] as $kind)
                                    @php $offer = $tier[$kind]; @endphp
                                    @continue(! $switchable && $offer === null)
                                    <div class="plan-offer{{ $switchable ? ' plan-offer--'.$kind : '' }}">
                                        @if ($offer === null)
                                            <p class="plan-price plan-price--none">—</p>
                                            <p class="plan-period">{{ $kind === 'year' ? __('site.pricing.only_monthly') : __('site.pricing.only_yearly') }}</p>
                                        @else
                                            <p class="plan-price">{{ $money($offer['price']) }} <span>{{ $offer['currency_label'] }}</span></p>
                                            <p class="plan-period">{{ __('site.pricing.per', ['period' => $offer['period']]) }}</p>
                                            @if ($offer['per_month'] !== null)
                                                <p class="plan-equiv">{{ __('site.pricing.per_month', ['amount' => $money(round($offer['per_month'])).' '.$offer['currency_label']]) }}@if ($offer['saving']) · <b>{{ __('site.pricing.saving', ['amount' => $money($offer['saving']).' '.$offer['currency_label']]) }}</b>@endif</p>
                                            @endif
                                            <dl>
                                                <div><dt>{{ __('site.pricing.devices') }}</dt><dd>{{ $offer['devices'] ?? __('site.pricing.devices_default') }}</dd></div>
                                                <div><dt>{{ __('site.pricing.traffic') }}</dt><dd>{{ $offer['traffic'] === null || $offer['traffic'] === 0 ? __('site.pricing.unlimited') : number_format($offer['traffic'] / 1073741824, 1, __('site.pricing.decimal'), __('site.pricing.thousands')).' '.__('site.pricing.gb') }}</dd></div>
                                                @if ($offer['concurrent'] !== null)
                                                    <div><dt>{{ __('site.pricing.concurrent') }}</dt><dd>{{ $offer['concurrent'] }}</dd></div>
                                                @endif
                                            </dl>
                                        @endif
                                        <a href="{{ Locales::path('download') }}" class="wb-btn wb-btn--outline">{{ __('site.pricing.to_app') }} <span aria-hidden="true">↗</span><span class="sr-only">: {{ $tier['name'] }}</span></a>
                                    </div>
                                @endforeach
                            </article>
                        @endforeach
                    </div>
                </div>
                <p class="price-note">{{ __('site.pricing.note') }}</p>
            @endif
        </div>
    </section>
    <section class="site-section product-band">
        <div class="wb-container faq-layout"><h2>{!! __('site.pricing.own_title') !!}</h2><div><p class="section-copy">{{ __('site.pricing.own_text') }}</p><a class="text-link" href="{{ Locales::path('access') }}#profiles">{{ __('site.pricing.own_link') }} <span aria-hidden="true">↗</span></a></div></div>
    </section>
</main>
@endsection
