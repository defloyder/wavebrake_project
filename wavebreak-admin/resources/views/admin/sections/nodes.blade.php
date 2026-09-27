<x-adm.card>
    <x-slot:actions>
        <a class="adm-btn adm-btn-primary" href="/enroll">+ Подключить ноду</a>
    </x-slot:actions>

    <x-adm.table-toolbar placeholder="Код или регион…" />

    <div class="adm-table-wrap" data-enhance>
        <table class="adm-table adm-table--cards">
            <thead>
                <tr>
                    <th>Нода</th>
                    <th>Статус</th>
                    <th>Конфигурация</th>
                    <th>Последний heartbeat</th>
                </tr>
            </thead>
            <tbody>
            @forelse($nodeRows as $row)
                <tr data-row data-search="{{ $row->search() }}">
                    <td class="adm-cell-primary" data-sort="{{ $row->code }}">
                        <span class="adm-cell-title">{{ $row->code }}</span>
                        <span class="adm-cell-sub">регион {{ $row->region }}</span>
                    </td>
                    <td data-label="Статус" data-sort="{{ $row->status->label }}"><x-adm.badge :badge="$row->status" /></td>
                    <td data-label="Конфигурация" data-sort="{{ $row->applied }}">
                        <div class="adm-cell-stack">
                            @if($row->inSync)
                                <span class="adm-text-ok">применена, ревизия {{ $row->applied }}</span>
                            @else
                                <span class="adm-text-warn">применена {{ $row->applied }} из {{ $row->desired }}</span>
                            @endif
                            @if($row->syncError)<span class="adm-cell-sub adm-text-bad">{{ $row->syncError }}</span>@endif
                        </div>
                    </td>
                    <td data-label="Heartbeat" class="date-cell" data-sort="{{ $row->heartbeatSort }}">
                        <div class="adm-cell-stack">
                            <span>{{ $row->heartbeatAgo }}</span>
                            <span class="adm-cell-sub">{{ $row->heartbeat }}</span>
                        </div>
                    </td>
                </tr>
            @empty
                <tr><td colspan="4" class="adm-empty">Ноды пока не зарегистрированы.</td></tr>
            @endforelse
            </tbody>
        </table>
    </div>
</x-adm.card>
