@extends('layout')

@section('title', 'Тарифы WAVEBREAK')
@section('description', 'Тарифы WAVEBREAK: подключение по одной ссылке и управление со смартфона или компьютера.')
@section('body_class', 'wb-shell wb-public')

@push('schema')
<script type="application/ld+json">
{
  "@@context": "https://schema.org",
  "@@type": "Product",
  "name": "WAVEBREAK",
  "description": "Защищенная инфраструктура для бизнеса с тарифами и управлением подключениями в приложении.",
  "brand": {"@@type": "Brand", "name": "WAVEBREAK"},
  "offers": [
    @foreach($plans as $plan)
    {
      "@@type": "Offer",
      "name": "{{ $plan['name'] }}",
      "price": "{{ number_format(($plan['price_cents'] ?? 0) / 100, 2, '.', '') }}",
      "priceCurrency": "USD",
      "availability": "https://schema.org/InStock"
    }@if(!$loop->last),@endif
    @endforeach
  ]
}
</script>
@endpush

@section('content')
@include('partials.public-header', ['active' => 'pricing'])

<main>
    <section class="wb-page-hero">
        <div class="wb-container wb-page-hero-grid">
            <div>
                <p class="wb-kicker">Тарифы</p>
                <h1>Один тариф. Один стабильный канал.</h1>
                <p class="wb-lead">
                    Тариф даёт лимит трафика и число устройств. Никаких пилотов и настроек —
                    выбрали тариф в приложении и получили готовое подключение.
                </p>
            </div>
            <div class="wb-mini-console">
                <span>тариф выбран</span>
                <strong>ссылка готова</strong>
                <em>статус: активно</em>
            </div>
        </div>
    </section>

    <section class="wb-section">
        <div class="wb-container wb-pricing-grid">
            @forelse($plans as $plan)
                @php
                    $code = strtolower($plan['code'] ?? '');
                    $copy = match (true) {
                        str_contains($code, 'starter') => [
                            'Для одного человека и одного устройства.',
                            ['Один линк — QR-код и ссылка', 'Канал сам держит форму при блокировках', 'Статус прямо в приложении']
                        ],
                        str_contains($code, 'plus') => [
                            'Для нескольких устройств в активном использовании.',
                            ['Больше устройств на одном тарифе', 'Выше лимит трафика', 'Все транспорты сразу — VLESS и Hysteria2']
                        ],
                        str_contains($code, 'fleet') => [
                            'Для семьи или небольшой команды.',
                            ['Общий тариф на несколько человек', 'Устройства добавляются в один клик', 'Трафик без строгого лимита']
                        ],
                        default => [
                            'Подключение через WAVEBREAK.',
                            ['Управление в приложении', 'Одна ссылка на подключение', 'Понятный статус']
                        ],
                    };
                @endphp
                <article class="wb-card wb-plan-card">
                    <span class="wb-plan-code">{{ strtoupper($plan['code'] ?? 'PLAN') }}</span>
                    <h2>{{ $plan['name'] }}</h2>
                    <p>{{ $copy[0] }}</p>
                    <div class="wb-price">
                        <strong>${{ number_format(($plan['price_cents'] ?? 0) / 100, 2) }}</strong>
                        <span>/ {{ $plan['interval'] ?? 'month' }}</span>
                    </div>
                    <ul>
                        @foreach($copy[1] as $item)
                            <li>{{ $item }}</li>
                        @endforeach
                    </ul>
                    <a href="/download" class="wb-btn {{ $loop->first ? 'wb-btn--primary' : '' }}">Открыть в приложении</a>
                </article>
            @empty
                <article class="wb-card">
                    <h2>Тарифы временно недоступны</h2>
                    <p>Список тарифов не загрузился. Обновите страницу через несколько минут.</p>
                </article>
            @endforelse
        </div>
    </section>

    <section class="wb-section wb-split-section">
        <div class="wb-container wb-split">
            <div>
                <p class="wb-kicker">После оплаты</p>
                <h2>Открываете приложение — подключение уже готово</h2>
                <p>
                    Тариф, QR-код, ссылка и устройства находятся в приложении.
                    Настраивать транспорт вручную не нужно: подходящий вариант выбирается автоматически.
                </p>
            </div>
            <div class="wb-checklist">
                <span>Аккаунт создан</span>
                <span>Тариф активен</span>
                <span>Ссылка готова</span>
                <span>Устройство подключено</span>
            </div>
        </div>
    </section>
</main>
@endsection
