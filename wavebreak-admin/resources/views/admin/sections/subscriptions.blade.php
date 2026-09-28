<x-adm.card>
    <x-adm.table-toolbar placeholder="Email, тариф или статус…" :filters="['live' => 'Активные', 'attention' => 'Требуют внимания', 'ended' => 'Завершённые', 'no-access' => 'Без ключа']" />

    <div class="adm-table-wrap" data-enhance>
        <table class="adm-table adm-table--cards">
            <thead>
                <tr>
                    <th>Пользователь</th>
                    <th>Тариф</th>
                    <th>Статус</th>
                    <th>Трафик</th>
                    <th>Устройств</th>
                    <th>Действует до</th>
                    <th>Источник</th>
                </tr>
            </thead>
            <tbody>
            @forelse($subscriptionRows as $row)
                <tr data-row data-search="{{ $row->search() }}" data-filter-tags="{{ $row->filter }}" data-open-user="{{ $row->userId }}" tabindex="0" class="is-clickable">
                    <td class="adm-cell-primary" data-sort="{{ $row->user }}">
                        <span class="adm-cell-title">{{ $row->user }}</span>
                        @unless($row->hasAccess)<span class="adm-cell-sub adm-text-warn">ключ не выдан</span>@endunless
                    </td>
                    <td data-label="Тариф" data-sort="{{ $row->plan }}"><strong>{{ $row->plan }}</strong></td>
                    <td data-label="Статус" data-sort="{{ $row->status->label }}"><x-adm.badge :badge="$row->status" /></td>
                    <td data-label="Трафик" data-sort="{{ $row->usedBytes }}">
                        <div class="adm-cell-stack">
                            <span>{{ $row->used }} <span class="adm-muted">из {{ $row->limit }}</span></span>
                            <x-adm.progress :percent="$row->usedPercent" />
                        </div>
                    </td>
                    <td data-label="Устройств" class="num-cell">{{ $row->devices }}</td>
                    <td data-label="До" class="date-cell" data-sort="{{ $row->endsSort }}">
                        <div class="adm-cell-stack">
                            <span>{{ $row->endsAt }}</span>
                            @if($row->daysLeft !== null && $row->daysLeft >= 0 && $row->daysLeft <= 7)
                                <span class="adm-cell-sub adm-text-warn">через {{ $row->daysLeft }} дн.</span>
                            @endif
                        </div>
                    </td>
                    <td data-label="Источник">{{ $row->source }}</td>
                </tr>
            @empty
                <tr><td colspan="7" class="adm-empty">Подписок пока нет. Выдать подписку можно в карточке пользователя.</td></tr>
            @endforelse
            </tbody>
        </table>
    </div>
</x-adm.card>
