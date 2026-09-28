@extends('layout')
@section('title', 'Тарифы WAVEBREAK | Условия подключения')
@section('description', 'Тарифы WAVEBREAK: стоимость, срок действия, количество устройств и доступный трафик. Подписка и управление подключениями в приложении.')
@section('body_class', 'wb-public page-pricing')
@section('content')
<main id="main">
    <section class="download-hero site-hero site-hero--compact" aria-labelledby="pricing-title">
        @include('partials.tide')
        <div class="wb-container site-hero-inner">
            <div class="hero-copy" data-reveal>
                <p class="download-kicker"><span></span> Подписка на сервис</p>
                <h1 id="pricing-title">Тарифы<br><em>WAVEBREAK.</em></h1>
                <p class="hero-description">Выберите подходящие условия. Оформление и управление подпиской доступны в приложении.</p>
                <a class="download-discover" href="#plans"><span>Посмотреть тарифы</span><span aria-hidden="true">↓</span></a>
            </div>
            <div class="hero-bottom"><span>Стоимость / Устройства / Трафик</span><span>Без веб-кабинета</span></div>
        </div>
    </section>
    <section class="site-section" id="plans" aria-label="Доступные тарифы">
        <div class="wb-container">
            @if ($plans === [])
                <div class="plans-unavailable" role="status"><span class="section-number">ТАРИФЫ</span><h2>Сейчас не удалось<br><em>загрузить цены.</em></h2><p>Попробуйте обновить страницу немного позже. Ваши действующие подписки от этого не меняются.</p><a href="/pricing" class="text-link">Обновить страницу <span aria-hidden="true">↻</span></a></div>
            @else
                @php
                    $money = fn (float $v) => number_format($v, $v == floor($v) ? 0 : 2, ',', ' ');
                    $switchable = $hasYearly && $hasMonthly;
                @endphp
                <div class="plan-catalog{{ $switchable ? ' plan-catalog--switch' : '' }}">
                    @if ($switchable)
                        <input class="period-radio" type="radio" name="billing-period" id="period-month" value="month" checked>
                        <input class="period-radio" type="radio" name="billing-period" id="period-year" value="year">
                        <div class="period-switch" aria-label="Период оплаты">
                            <label for="period-month">Месяц</label>
                            <label for="period-year">Год @if ($maxDiscount)<span class="period-badge">−{{ $maxDiscount }}%</span>@endif</label>
                        </div>
                    @endif
                    <div class="plan-grid">
                        @foreach ($tiers as $tier)
                            <article class="plan" data-reveal>
                                <span class="section-number">{{ str_pad($loop->iteration, 2, '0', STR_PAD_LEFT) }} / ПОДПИСКА</span>
                                <h2>{{ $tier['name'] }}</h2>
                                @foreach (['month', 'year'] as $kind)
                                    @php $offer = $tier[$kind]; @endphp
                                    @continue(! $switchable && $offer === null)
                                    <div class="plan-offer{{ $switchable ? ' plan-offer--'.$kind : '' }}">
                                        @if ($offer === null)
                                            <p class="plan-price plan-price--none">—</p>
                                            <p class="plan-period">{{ $kind === 'year' ? 'Только помесячная оплата' : 'Только годовая оплата' }}</p>
                                        @else
                                            <p class="plan-price">{{ $money($offer['price']) }} <span>{{ $offer['currency_label'] }}</span></p>
                                            <p class="plan-period">за {{ $offer['period'] }}</p>
                                            @if ($offer['per_month'] !== null)
                                                <p class="plan-equiv">≈ {{ $money(round($offer['per_month'])) }} {{ $offer['currency_label'] }} в месяц@if ($offer['saving']) · <b>выгода {{ $money($offer['saving']) }} {{ $offer['currency_label'] }}</b>@endif</p>
                                            @endif
                                            <dl>
                                                <div><dt>Устройства</dt><dd>{{ $offer['devices'] ?? 'По условиям тарифа' }}</dd></div>
                                                <div><dt>Трафик</dt><dd>{{ $offer['traffic'] === null || $offer['traffic'] === 0 ? 'Без лимита' : number_format($offer['traffic'] / 1073741824, 1, ',', ' ').' ГБ' }}</dd></div>
                                                @if ($offer['concurrent'] !== null)
                                                    <div><dt>Одновременно</dt><dd>{{ $offer['concurrent'] }}</dd></div>
                                                @endif
                                            </dl>
                                        @endif
                                        <a href="/download" class="wb-btn wb-btn--outline">К приложению <span aria-hidden="true">↗</span><span class="sr-only">: {{ $tier['name'] }}</span></a>
                                    </div>
                                @endforeach
                            </article>
                        @endforeach
                    </div>
                </div>
                <p class="price-note">Перед оформлением проверьте срок и условия подписки в приложении.</p>
            @endif
        </div>
    </section>
    <section class="site-section product-band">
        <div class="wb-container faq-layout"><h2>Уже есть<br><em>своя ссылка?</em></h2><div><p class="section-copy">Для профилей других провайдеров подписка WAVEBREAK не требуется. Достаточно совместимой ссылки подключения.</p><a class="text-link" href="/access#profiles">Подробнее о профилях <span aria-hidden="true">↗</span></a></div></div>
    </section>
</main>
@endsection
