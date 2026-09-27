<x-adm.card>
    <x-adm.table-toolbar placeholder="Действие, объект или автор…" />

    <div class="adm-table-wrap" data-enhance>
        <table class="adm-table adm-table--cards">
            <thead>
                <tr>
                    <th>Действие</th>
                    <th>Объект</th>
                    <th>Кто</th>
                    <th>Когда</th>
                </tr>
            </thead>
            <tbody>
            @forelse($auditRows as $row)
                <tr data-row data-search="{{ $row->search() }}" @if($row->userId) data-open-user="{{ $row->userId }}" tabindex="0" class="is-clickable" @endif>
                    <td class="adm-cell-primary" data-sort="{{ $row->action }}">
                        <span class="adm-cell-title">{{ $row->action }}</span>
                        <span class="adm-cell-sub"><code>{{ $row->actionCode }}</code></span>
                    </td>
                    <td data-label="Объект">{{ $row->target }}</td>
                    <td data-label="Кто">{{ $row->actor }}</td>
                    <td data-label="Когда" class="date-cell" data-sort="{{ $row->createdSort }}">{{ $row->createdAt }}</td>
                </tr>
            @empty
                <tr><td colspan="4" class="adm-empty">Событий пока нет.</td></tr>
            @endforelse
            </tbody>
        </table>
    </div>
</x-adm.card>
