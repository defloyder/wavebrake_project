<x-adm.card>
    <x-adm.table-toolbar placeholder="Email, ключ, нода, протокол…" :filters="['Активен' => 'Активные', 'Отозван' => 'Отозванные']" />

    <div class="adm-table-wrap" data-enhance>
        <table class="adm-table adm-table--cards">
            <thead>
                <tr>
                    <th>Пользователь</th>
                    <th>Ключ</th>
                    <th>Нода</th>
                    <th>Протокол</th>
                    <th>Статус</th>
                    <th>Выдан</th>
                    <th>Действует до</th>
                </tr>
            </thead>
            <tbody>
            @forelse($grantRows as $row)
                <tr data-row data-search="{{ $row->search() }}" data-filter-tags="{{ $row->status->label }}" @if($row->userId) data-open-user="{{ $row->userId }}" tabindex="0" class="is-clickable" @endif>
                    <td class="adm-cell-primary" data-sort="{{ $row->user }}"><span class="adm-cell-title">{{ $row->user }}</span></td>
                    <td data-label="Ключ"><div class="adm-cell-stack"><code>{{ $row->label }}</code><span class="adm-cell-sub">{{ $row->kind }}</span></div></td>
                    <td data-label="Нода">{{ $row->node }}</td>
                    <td data-label="Протокол">{{ $row->protocol }}</td>
                    <td data-label="Статус" data-sort="{{ $row->status->label }}"><x-adm.badge :badge="$row->status" /></td>
                    <td data-label="Выдан" class="date-cell" data-sort="{{ $row->createdSort }}">{{ $row->createdAt }}</td>
                    <td data-label="До" class="date-cell">{{ $row->expiresAt }}</td>
                </tr>
            @empty
                <tr><td colspan="7" class="adm-empty">Ключей доступа пока нет.</td></tr>
            @endforelse
            </tbody>
        </table>
    </div>
</x-adm.card>
