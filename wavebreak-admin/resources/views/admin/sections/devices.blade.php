<x-adm.card>
    <x-adm.table-toolbar placeholder="Email, устройство, платформа…" :filters="['Активно' => 'Активные', 'Отозвано' => 'Отозванные']" />

    <div class="adm-table-wrap" data-enhance>
        <table class="adm-table adm-table--cards">
            <thead>
                <tr>
                    <th>Устройство</th>
                    <th>Пользователь</th>
                    <th>Платформа</th>
                    <th>Статус</th>
                    <th>Был в сети</th>
                    <th>Добавлено</th>
                </tr>
            </thead>
            <tbody>
            @forelse($deviceRows as $row)
                <tr data-row data-search="{{ $row->search() }}" data-filter-tags="{{ $row->status->label }}" data-open-user="{{ $row->userId }}" tabindex="0" class="is-clickable">
                    <td class="adm-cell-primary" data-sort="{{ $row->name }}"><span class="adm-cell-title">{{ $row->name }}</span></td>
                    <td data-label="Пользователь" data-sort="{{ $row->user }}">{{ $row->user }}</td>
                    <td data-label="Платформа">{{ $row->platform }}</td>
                    <td data-label="Статус" data-sort="{{ $row->status->label }}"><x-adm.badge :badge="$row->status" /></td>
                    <td data-label="В сети" class="date-cell" data-sort="{{ $row->lastSeenSort }}" title="{{ $row->lastSeen }}">{{ $row->lastSeenAgo }}</td>
                    <td data-label="Добавлено" class="date-cell">{{ $row->createdAt }}</td>
                </tr>
            @empty
                <tr><td colspan="6" class="adm-empty">Устройств пока нет.</td></tr>
            @endforelse
            </tbody>
        </table>
    </div>
</x-adm.card>
