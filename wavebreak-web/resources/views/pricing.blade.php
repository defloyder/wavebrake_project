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
                <div class="plan-grid">
                    @foreach ($plans as $plan)
                        @php
                            $price = ($plan['price_minor'] ?? $plan['price_cents'] ?? 0) / 100;
                            $currency = strtoupper($plan['currency'] ?? 'USD');
                            $currencyLabel = ['RUB' => '₽', 'USD' => '$', 'EUR' => '€', 'TRY' => '₺'][$currency] ?? $currency;
                            $period = isset($plan['duration_days']) ? $plan['duration_days'].' дней' : (['month' => 'месяц', 'year' => 'год', 'week' => 'неделю'][$plan['interval'] ?? ''] ?? ($plan['interval'] ?? 'период'));
                            $traffic = $plan['traffic_limit_bytes'] ?? null;
                        @endphp
                        <article class="plan" data-reveal>
                            <span class="section-number">{{ str_pad($loop->iteration, 2, '0', STR_PAD_LEFT) }} / ПОДПИСКА</span>
                            <h2>{{ $plan['name'] }}</h2>
                            <p class="plan-price">{{ number_format($price, $price == floor($price) ? 0 : 2, ',', ' ') }} <span>{{ $currencyLabel }}</span></p>
                            <p class="plan-period">за {{ $period }}</p>
                            <dl>
                                <div><dt>Устройства</dt><dd>{{ $plan['device_limit'] ?? 'По условиям тарифа' }}</dd></div>
                                <div><dt>Трафик</dt><dd>{{ $traffic === null || $traffic === 0 ? 'Без лимита' : number_format($traffic / 1073741824, 1, ',', ' ').' ГБ' }}</dd></div>
                                @if (isset($plan['concurrent_connection_limit']))
                                    <div><dt>Одновременно</dt><dd>{{ $plan['concurrent_connection_limit'] }}</dd></div>
                                @endif
                            </dl>
                            <a href="/download" class="wb-btn wb-btn--outline">К приложению <span aria-hidden="true">↗</span><span class="sr-only">: {{ $plan['name'] }}</span></a>
                        </article>
                    @endforeach
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
