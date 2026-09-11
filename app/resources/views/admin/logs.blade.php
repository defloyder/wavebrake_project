@extends('admin.layout')

@section('title', 'Журнал действий')

@section('content')
<div style="margin-bottom:20px">
    <p style="margin:0;font-size:.72rem;color:var(--muted);letter-spacing:.1em;text-transform:uppercase">Auralith Admin</p>
    <h2 style="margin:4px 0 0;font-family:'Montserrat',sans-serif;font-size:1.5rem">Журнал действий</h2>
</div>

<div class="adm-card">
    @if(!empty($logsUnavailable))
        <div class="adm-alert" style="margin-bottom:14px;border-color:rgba(251,191,36,.35);background:rgba(251,191,36,.1);color:#fde68a;">
            Таблица журнала пока не создана. Выполни миграции на сервере: <code>php artisan migrate --force</code>
        </div>
    @endif

    @php
        $currentSort = request('sort', 'created_at');
        $currentDir = request('dir', 'desc') === 'asc' ? 'asc' : 'desc';
        $sortUrl = function (string $column) use ($currentSort, $currentDir) {
            $nextDir = ($currentSort === $column && $currentDir === 'asc') ? 'desc' : 'asc';
            return request()->fullUrlWithQuery(['sort' => $column, 'dir' => $nextDir, 'page' => 1]);
        };
        $sortIcon = function (string $column) use ($currentSort, $currentDir) {
            if ($currentSort !== $column) return '↕';
            return $currentDir === 'asc' ? '↑' : '↓';
        };
    @endphp

    {{-- Filters --}}
    <form method="GET" action="{{ route('admin.logs') }}"
          class="adm-toolbar">

        <select name="admin_id" class="adm-input" style="width:auto;min-width:140px">
            <option value="">Все администраторы</option>
            @foreach($admins as $adm)
                <option value="{{ $adm->id }}" {{ request('admin_id') == $adm->id ? 'selected' : '' }}>
                    {{ $adm->username }}
                </option>
            @endforeach
        </select>

        <select name="action" class="adm-input" style="width:auto;min-width:120px">
            <option value="">Все действия</option>
            @foreach(['create','update','delete','login','logout'] as $act)
                <option value="{{ $act }}" {{ request('action') === $act ? 'selected' : '' }}>{{ $act }}</option>
            @endforeach
        </select>

        <button type="submit" class="adm-btn adm-btn-sm">Фильтр</button>
        @if(request('admin_id') || request('action') || request('sort') || request('dir'))
            <a href="{{ route('admin.logs') }}" class="adm-btn adm-btn-sm"
               style="background:rgba(138,148,166,.15);color:var(--muted);text-decoration:none">Сбросить</a>
        @endif
    </form>

    <div style="overflow-x:auto">
        <table class="adm-table">
            <thead>
                <tr>
                    <th><a class="adm-sort-link {{ $currentSort === 'id' ? 'is-active' : '' }}" href="{{ $sortUrl('id') }}">ID <span>{{ $sortIcon('id') }}</span></a></th>
                    <th><a class="adm-sort-link {{ $currentSort === 'admin_id' ? 'is-active' : '' }}" href="{{ $sortUrl('admin_id') }}">Администратор <span>{{ $sortIcon('admin_id') }}</span></a></th>
                    <th><a class="adm-sort-link {{ $currentSort === 'action' ? 'is-active' : '' }}" href="{{ $sortUrl('action') }}">Действие <span>{{ $sortIcon('action') }}</span></a></th>
                    <th><a class="adm-sort-link {{ $currentSort === 'resource' ? 'is-active' : '' }}" href="{{ $sortUrl('resource') }}">Ресурс <span>{{ $sortIcon('resource') }}</span></a></th>
                    <th><a class="adm-sort-link {{ $currentSort === 'resource_id' ? 'is-active' : '' }}" href="{{ $sortUrl('resource_id') }}">ID записи <span>{{ $sortIcon('resource_id') }}</span></a></th>
                    <th><a class="adm-sort-link {{ $currentSort === 'ip' ? 'is-active' : '' }}" href="{{ $sortUrl('ip') }}">IP <span>{{ $sortIcon('ip') }}</span></a></th>
                    <th>Изменения</th>
                    <th><a class="adm-sort-link {{ $currentSort === 'created_at' ? 'is-active' : '' }}" href="{{ $sortUrl('created_at') }}">Время <span>{{ $sortIcon('created_at') }}</span></a></th>
                </tr>
            </thead>
            <tbody>
            @forelse($logs as $log)
                <tr>
                    <td data-label="ID" style="color:var(--muted);font-size:.8rem">{{ $log->id }}</td>
                    <td data-label="Администратор">
                        <span style="font-weight:600;color:var(--accent-2)">
                            {{ optional($log->admin)->username ?? '—' }}
                        </span>
                    </td>
                    <td data-label="Действие">
                        @php
                        $actionColors = [
                            'create' => '#4ade80',
                            'update' => '#fbbf24',
                            'delete' => '#f87171',
                            'login'  => '#6b93c0',
                            'logout' => '#8a94a6',
                        ];
                        $color = $actionColors[$log->action] ?? 'var(--text)';
                        @endphp
                        <span style="color:{{ $color }};font-weight:600;font-size:.82rem;text-transform:uppercase">
                            {{ $log->action }}
                        </span>
                    </td>
                    <td data-label="Ресурс" style="color:var(--muted)">{{ $log->resource ?? '—' }}</td>
                    <td data-label="ID записи" style="color:var(--muted);font-size:.8rem">{{ $log->resource_id ?? '—' }}</td>
                    <td data-label="IP" style="color:var(--muted);font-size:.78rem">{{ $log->ip ?? '—' }}</td>
                    <td data-label="Изменения" style="max-width:300px">
                        @if(!empty($log->changes))
                            <details class="adm-log-details">
                                <summary>Показать JSON</summary>
                                <pre>{{ json_encode($log->changes, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) }}</pre>
                            </details>
                        @else
                            <span style="color:var(--muted)">—</span>
                        @endif
                    </td>
                    <td data-label="Время" style="color:var(--muted);font-size:.78rem;white-space:nowrap">
                        {{ $log->created_at->format('d.m.Y H:i:s') }}
                    </td>
                </tr>
            @empty
                <tr>
                    <td colspan="8" style="text-align:center;color:var(--muted);padding:32px">
                        Записей не найдено
                    </td>
                </tr>
            @endforelse
            </tbody>
        </table>
    </div>

    @if($logs->hasPages())
    <div style="margin-top:16px;display:flex;align-items:center;gap:6px;flex-wrap:wrap">
        @if($logs->onFirstPage())
            <span style="padding:5px 12px;border-radius:7px;border:1px solid var(--line);color:var(--muted);font-size:.82rem">‹</span>
        @else
            <a href="{{ $logs->previousPageUrl() }}" style="padding:5px 12px;border-radius:7px;border:1px solid var(--line);color:var(--text);font-size:.82rem;text-decoration:none">‹</a>
        @endif

        @foreach($logs->getUrlRange(1, $logs->lastPage()) as $page => $url)
            @if($page == $logs->currentPage())
                <span style="padding:5px 12px;border-radius:7px;background:rgba(79,126,181,.25);border:1px solid rgba(79,126,181,.4);color:var(--accent-2);font-size:.82rem">{{ $page }}</span>
            @else
                <a href="{{ $url }}" style="padding:5px 12px;border-radius:7px;border:1px solid var(--line);color:var(--muted);font-size:.82rem;text-decoration:none">{{ $page }}</a>
            @endif
        @endforeach

        @if($logs->hasMorePages())
            <a href="{{ $logs->nextPageUrl() }}" style="padding:5px 12px;border-radius:7px;border:1px solid var(--line);color:var(--text);font-size:.82rem;text-decoration:none">›</a>
        @else
            <span style="padding:5px 12px;border-radius:7px;border:1px solid var(--line);color:var(--muted);font-size:.82rem">›</span>
        @endif

        <span style="font-size:.78rem;color:var(--muted);margin-left:8px">
            {{ $logs->firstItem() }}–{{ $logs->lastItem() }} из {{ $logs->total() }}
        </span>
    </div>
    @endif
</div>
@endsection
