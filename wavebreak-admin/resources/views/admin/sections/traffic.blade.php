<x-adm.card title="Трафик сейчас" subtitle="Опрос раз в 4 секунды: сколько прошло с прошлого опроса." class="adm-chart-card">
    <x-slot:actions>
        <div class="adm-live-controls">
            <button type="button" class="adm-icon-btn adm-icon-btn--live" id="live-traffic-reveal" aria-label="Показать live-трафик" title="Показать live-трафик">
                <svg viewBox="0 0 24 24" fill="none" aria-hidden="true"><path d="m8 5 11 7-11 7V5Z" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"/></svg>
            </button>
            <button type="button" class="adm-icon-btn adm-icon-btn--live" id="live-traffic-toggle" aria-label="Пауза" title="Пауза" hidden>
                <svg viewBox="0 0 24 24" fill="none" aria-hidden="true"><path d="M9 6v12M15 6v12" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></svg>
            </button>
            <button type="button" class="adm-icon-btn adm-icon-btn--live" id="live-traffic-hide" aria-label="Скрыть live-трафик" title="Скрыть live-трафик" hidden>
                <svg viewBox="0 0 24 24" fill="none" aria-hidden="true"><path d="M18 6 6 18M6 6l12 12" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></svg>
            </button>
        </div>
    </x-slot:actions>
    <div class="adm-chart-wrap adm-chart-wrap--live" id="live-traffic-wrap" hidden>
        <canvas id="chart-traffic-live"></canvas>
    </div>
</x-adm.card>

<x-adm.card title="Трафик по дням" subtitle="Загрузка и выгрузка по всем подпискам." class="adm-chart-card">
    @if(count($trafficHistory) > 0)
        <x-slot:actions>
            <div class="adm-range-toggle" data-range-for="chart-traffic-detail">
                <button type="button" data-range="1">Сегодня</button>
                <button type="button" data-range="7">7 дней</button>
                <button type="button" data-range="30" class="is-active">30 дней</button>
            </div>
        </x-slot:actions>
    @endif
    <div class="adm-chart-wrap">
        @if(count($trafficHistory) > 0)
            <canvas id="chart-traffic-detail"></canvas>
        @else
            <p class="adm-chart-empty">Пока нет исторических данных по трафику.</p>
        @endif
    </div>
</x-adm.card>

<x-adm.card title="По подпискам" subtitle="Счётчики за текущий период подписки.">
    <x-adm.table-toolbar placeholder="Email, тариф или статус…" />

    <div class="adm-table-wrap" data-enhance>
        <table class="adm-table adm-table--cards">
            <thead>
                <tr>
                    <th>Пользователь</th>
                    <th>Тариф</th>
                    <th>Статус</th>
                    <th>Загрузка</th>
                    <th>Выгрузка</th>
                    <th>Всего</th>
                    <th>Лимит</th>
                </tr>
            </thead>
            <tbody>
            @forelse($trafficRows as $row)
                <tr data-row data-search="{{ $row->search() }}" data-open-user="{{ $row->userId }}" tabindex="0" class="is-clickable">
                    <td class="adm-cell-primary" data-sort="{{ $row->user }}"><span class="adm-cell-title">{{ $row->user }}</span></td>
                    <td data-label="Тариф">{{ $row->plan }}</td>
                    <td data-label="Статус" data-sort="{{ $row->status->label }}"><x-adm.badge :badge="$row->status" /></td>
                    <td data-label="Загрузка" class="num-cell">{{ $row->down }}</td>
                    <td data-label="Выгрузка" class="num-cell">{{ $row->up }}</td>
                    <td data-label="Всего" class="num-cell" data-sort="{{ $row->totalBytes }}">
                        <div class="adm-cell-stack">
                            <strong>{{ $row->total }}</strong>
                            <x-adm.progress :percent="$row->usedPercent" />
                        </div>
                    </td>
                    <td data-label="Лимит" class="num-cell">{{ $row->limit }}</td>
                </tr>
            @empty
                <tr><td colspan="7" class="adm-empty">Данных о трафике пока нет.</td></tr>
            @endforelse
            </tbody>
        </table>
    </div>
</x-adm.card>

@push('scripts')
<script>
document.addEventListener('DOMContentLoaded', () => {
    const reveal = document.getElementById('live-traffic-reveal');
    const toggle = document.getElementById('live-traffic-toggle');
    const hide = document.getElementById('live-traffic-hide');
    const wrap = document.getElementById('live-traffic-wrap');
    let liveTraffic = null;
    reveal?.addEventListener('click', () => {
        reveal.hidden = true;
        toggle.hidden = false;
        hide.hidden = false;
        wrap.hidden = false;
        if (liveTraffic) liveTraffic.start();
        else liveTraffic = window.admInitLiveTraffic('chart-traffic-live', 'live-traffic-toggle');
    });
    hide?.addEventListener('click', () => {
        liveTraffic?.stop();
        wrap.hidden = true;
        toggle.hidden = true;
        hide.hidden = true;
        reveal.hidden = false;
    });

    const raw = @json($trafficHistory);
    window.admInitRangeChart('chart-traffic-detail', raw, (rows) => ({
        datasets: [
            { label: 'Загрузка, ГБ', data: rows.map(r => (r.bytes_down || 0) / 1073741824), borderColor: '#35E0A1', backgroundColor: 'rgba(53,224,161,.1)', fill: true, tension: .35, pointRadius: 2 },
            { label: 'Выгрузка, ГБ', data: rows.map(r => (r.bytes_up || 0) / 1073741824), borderColor: '#00D6FF', backgroundColor: 'rgba(0,214,255,.1)', fill: true, tension: .35, pointRadius: 2 },
        ],
        plugins: { legend: { labels: { color: 'rgba(230,242,247,.8)' } } },
    }));
});
</script>
@endpush
