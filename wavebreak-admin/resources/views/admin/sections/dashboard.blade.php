@php
    $onlineNodes = collect($nodes)->where('status', 'online')->count();
    $kpis = [
        ['label' => 'Пользователи', 'value' => $dashboard['users'] ?? '—', 'hint' => 'активных: '.($dashboard['active_users'] ?? '—'), 'href' => '/users'],
        ['label' => 'Активные подписки', 'value' => $dashboard['active_subscriptions'] ?? '—', 'hint' => 'всего: '.($dashboard['subscriptions'] ?? '—'), 'href' => '/subscriptions'],
        ['label' => 'Ноды онлайн', 'value' => $onlineNodes.' / '.count($nodes), 'hint' => $onlineNodes === count($nodes) ? 'все на связи' : 'есть недоступные', 'href' => '/nodes'],
        ['label' => 'Трафик всего', 'value' => \App\Support\ByteFormatter::format((int) ($dashboard['bytes_total'] ?? 0)), 'hint' => 'по всем подпискам', 'href' => '/traffic'],
    ];
    $links = [
        ['href' => '/plans', 'title' => 'Тарифы', 'text' => 'Цены, лимиты трафика и устройств.', 'count' => $dashboard['plans'] ?? null],
        ['href' => '/grants', 'title' => 'Ключи доступа', 'text' => 'Выданные учётные данные VPN.', 'count' => $dashboard['access_grants'] ?? null],
        ['href' => '/enroll', 'title' => 'Подключить ноду', 'text' => 'Регистрация новой ноды через Core.', 'count' => null],
    ];
@endphp

<section class="adm-kpi-grid">
    @foreach($kpis as $kpi)
        <a class="adm-stat" href="{{ $kpi['href'] }}">
            <span>{{ $kpi['label'] }}</span>
            <strong>{{ $kpi['value'] }}</strong>
            <small>{{ $kpi['hint'] }}</small>
        </a>
    @endforeach
</section>

<x-adm.card title="Трафик по дням" subtitle="Сумма загрузки и выгрузки по всем подпискам." class="adm-chart-card">
    @if(count($trafficHistory) > 0)
        <x-slot:actions>
            <div class="adm-range-toggle" data-range-for="chart-traffic-overview">
                <button type="button" data-range="1">Сегодня</button>
                <button type="button" data-range="7">7 дней</button>
                <button type="button" data-range="30" class="is-active">30 дней</button>
            </div>
        </x-slot:actions>
    @endif
    <div class="adm-chart-wrap">
        @if(count($trafficHistory) > 0)
            <canvas id="chart-traffic-overview"></canvas>
        @else
            <p class="adm-chart-empty">Пока нет данных: ни одна подписка ещё не сообщила суточный трафик.</p>
        @endif
    </div>
</x-adm.card>

<div class="adm-split">
    <x-adm.card title="Последние действия" subtitle="Из журнала аудита Core.">
        <x-slot:actions><a class="adm-btn adm-btn--ghost adm-btn--sm" href="/audit">Весь аудит</a></x-slot:actions>
        @if($auditRows)
            <ul class="adm-feed">
                @foreach($auditRows as $row)
                    <li @if($row->userId) data-open-user="{{ $row->userId }}" tabindex="0" class="is-clickable" @endif>
                        <div>
                            <strong>{{ $row->action }}</strong>
                            <span>{{ $row->target }}</span>
                        </div>
                        <small>{{ $row->actor }} · {{ $row->createdAt }}</small>
                    </li>
                @endforeach
            </ul>
        @else
            <p class="adm-empty">Событий пока нет.</p>
        @endif
    </x-adm.card>

    <div class="adm-link-grid">
        @foreach($links as $link)
            <a href="{{ $link['href'] }}" class="adm-card adm-menu-card">
                <div>
                    <h6>{{ $link['title'] }}</h6>
                    <p>{{ $link['text'] }}</p>
                </div>
                @if($link['count'] !== null)<span class="adm-settings-status">{{ $link['count'] }}</span>@endif
            </a>
        @endforeach
    </div>
</div>

@push('scripts')
<script>
document.addEventListener('DOMContentLoaded', () => {
    const raw = @json($trafficHistory);
    window.admInitRangeChart('chart-traffic-overview', raw, (rows) => ({
        datasets: [{
            label: 'ГБ / день',
            data: rows.map(r => ((r.bytes_up || 0) + (r.bytes_down || 0)) / 1073741824),
            borderColor: '#00D6FF',
            backgroundColor: 'rgba(0,214,255,.12)',
            fill: true,
            tension: .35,
            pointRadius: 2,
            pointBackgroundColor: '#00D6FF',
        }],
        plugins: { legend: { display: false } },
    }));
});
</script>
@endpush
