@extends('layout')

@section('title', 'Тарифы WAVEBREAK - защищенная инфраструктура для бизнеса')
@section('description', 'Тарифы WAVEBREAK для запуска управляемого доступа: личный кабинет, серверы доступа, персональные подключения и понятное сопровождение клиентов.')
@section('body_class', 'wb-shell wb-public')

@push('schema')
<script type="application/ld+json">
{
  "@@context": "https://schema.org",
  "@@type": "Product",
  "name": "WAVEBREAK",
  "description": "Защищенная инфраструктура для бизнеса с личным кабинетом, тарифами и управлением подключениями.",
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
                <h1>Начните с пилота и спокойно вырастите до полноценного сервиса</h1>
                <p class="wb-lead">
                    Тариф определяет не только стоимость. Он задает уровень обслуживания:
                    сколько клиентов вы подключаете, какие локации используете и насколько быстро команда сопровождает рост.
                </p>
            </div>
            <div class="wb-mini-console">
                <span>тариф выбран</span>
                <strong>подключение готовится</strong>
                <em>статус: подтверждено</em>
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
                            'Для пилота, первых клиентов и проверки спроса.',
                            ['Личный кабинет', 'Базовая выдача подключения', 'Понятный старт без ручной настройки']
                        ],
                        str_contains($code, 'plus') => [
                            'Для регулярной работы и растущей клиентской базы.',
                            ['Больше рабочих сценариев', 'Удобная смена локации', 'Подходит для небольшой команды']
                        ],
                        str_contains($code, 'fleet') => [
                            'Для нескольких локаций и коммерческой нагрузки.',
                            ['Несколько серверов доступа', 'Операционный контроль', 'Подходит для масштабирования']
                        ],
                        default => [
                            'Для управляемого доступа через WAVEBREAK.',
                            ['Личный кабинет', 'Персональное подключение', 'Контроль состояния']
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
                    <a href="/register" class="wb-btn {{ $loop->first ? 'wb-btn--primary' : '' }}">Выбрать тариф</a>
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
                <p class="wb-kicker">После выбора</p>
                <h2>Клиент видит сервис, а не техническую кухню</h2>
                <p>
                    После активации тарифа клиент переходит в кабинет: выбирает локацию, добавляет устройство
                    и получает готовое подключение. Команда видит статус и сопровождает клиента без догадок.
                </p>
            </div>
            <div class="wb-checklist">
                <span>Аккаунт создан</span>
                <span>Тариф активен</span>
                <span>Локация выбрана</span>
                <span>Подключение готово</span>
            </div>
        </div>
    </section>
</main>
@endsection
