@extends('admin.layout')

@section('title', 'Просмотр - ' . $config['title'])

@section('content')
<div style="margin-bottom:20px">
    <p style="margin:0;font-size:.72rem;color:var(--muted);letter-spacing:.1em;text-transform:uppercase">{{ $config['title'] }}</p>
    <h2 style="margin:4px 0 0;font-family:'Montserrat',sans-serif;font-size:1.5rem">Просмотр записи #{{ $row->id }}</h2>
    @if($resource === 'users')
        <p style="margin:6px 0 0;color:var(--muted);font-size:.84rem">
            Локальный ID: {{ $row->id }} · Core ID: {{ $row->core_user_id ?: 'не привязан' }}
        </p>
    @endif
</div>

<div class="adm-card">
    <div style="display:grid;grid-template-columns:repeat(auto-fit,minmax(280px,1fr));gap:16px">
        @foreach($config['fields'] as $field)
            <div>
                <label style="display:block;font-size:.78rem;color:var(--muted);margin-bottom:6px;text-transform:uppercase;letter-spacing:.05em">
                    {{ $field }}
                </label>
                <div style="padding:10px 14px;background:rgba(8,13,22,.6);border:1px solid var(--line);border-radius:9px;color:var(--text);font-size:.88rem;word-break:break-word">
                    {{ is_array($row->{$field}) ? json_encode($row->{$field}, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE) : ($row->{$field} ?? '—') }}
                </div>
            </div>
        @endforeach
    </div>

    <div class="adm-record-actions" style="margin-top:24px;display:flex;gap:10px;flex-wrap:wrap">
        @if($config['editable'] ?? true)
            <a href="{{ route('admin.resource.edit', [$resource, $row->id]) }}" class="adm-btn" style="text-decoration:none">
                Редактировать
            </a>
        @endif
        <a href="{{ route('admin.resource.index', $resource) }}" class="adm-btn adm-btn-ghost" style="text-decoration:none">
            ← Назад к списку
        </a>
        @if($config['deletable'] ?? true)
        <form method="post" action="{{ route('admin.resource.destroy', [$resource, $row->id]) }}"
              class="adm-record-delete-form"
              onsubmit="return confirm('Удалить запись #{{ $row->id }}?')" style="margin:0;margin-left:auto">
            @csrf
            @method('DELETE')
            <button type="submit" class="adm-btn adm-btn-danger adm-btn-icon-text" title="Удалить запись">
                <svg viewBox="0 0 24 24" fill="none" aria-hidden="true"><path d="M4 7h16M10 11v6M14 11v6M6 7l1 14h10l1-14M9 7V4h6v3" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/></svg>
                <span>Удалить запись</span>
            </button>
        </form>
        @endif
    </div>
</div>

@if($resource === 'users')
    @php
        $fmtCoreBytes = static function ($bytes): string {
            if ($bytes === null || $bytes === '') return '—';
            $bytes = max(0, (float) $bytes);
            $units = ['Б', 'КБ', 'МБ', 'ГБ', 'ТБ'];
            $power = $bytes > 0 ? min((int) floor(log($bytes, 1024)), count($units) - 1) : 0;
            $value = $power > 0 ? $bytes / (1024 ** $power) : $bytes;
            return number_format($value, $power >= 3 ? 1 : 0, '.', ' ') . ' ' . $units[$power];
        };
        $deviceTraffic = static function (array $device): ?float {
            foreach (['traffic_bytes', 'total_bytes', 'used_bytes', 'bytes', 'total_traffic_bytes', 'traffic_total_bytes'] as $key) {
                if (is_numeric($device[$key] ?? null)) return (float) $device[$key];
            }
            foreach (['traffic_gb', 'used_gb', 'total_gb'] as $key) {
                if (is_numeric($device[$key] ?? null)) return (float) $device[$key] * 1024 * 1024 * 1024;
            }
            $rx = null;
            $tx = null;
            foreach (['rx_bytes', 'download_bytes', 'downloaded_bytes', 'down_bytes'] as $key) {
                if (is_numeric($device[$key] ?? null)) { $rx = (float) $device[$key]; break; }
            }
            foreach (['tx_bytes', 'upload_bytes', 'uploaded_bytes', 'up_bytes'] as $key) {
                if (is_numeric($device[$key] ?? null)) { $tx = (float) $device[$key]; break; }
            }
            $rx ??= 0;
            $tx ??= 0;
            return ($rx + $tx) > 0 ? $rx + $tx : null;
        };
        $trafficBytesFrom = static function (array $payload, array $keys) {
            foreach ($keys as $key) {
                if (is_numeric($payload[$key] ?? null)) return (float) $payload[$key];
            }
            return null;
        };
        $trafficPayload = is_array($coreTraffic) ? (($coreTraffic['traffic'] ?? $coreTraffic['data'] ?? $coreTraffic['summary'] ?? $coreTraffic)) : [];
        $trafficPayload = is_array($trafficPayload) ? $trafficPayload : [];
        $localSubscription = $row->subscriptions()->latest('last_sync_at')->latest()->first();
        $trafficDevices = $trafficPayload['devices'] ?? $coreTraffic['devices'] ?? $coreDevices ?? [];
        $trafficDevices = is_array($trafficDevices) ? $trafficDevices : [];
        $trafficTotal = $trafficBytesFrom($trafficPayload, ['total_bytes', 'traffic_bytes', 'used_bytes', 'bytes', 'total_traffic_bytes', 'traffic_total_bytes']);
        if ($trafficTotal === null && is_numeric($trafficPayload['total_gb'] ?? null)) {
            $trafficTotal = (float) $trafficPayload['total_gb'] * 1024 * 1024 * 1024;
        }
        $trafficUpload = $trafficBytesFrom($trafficPayload, ['upload_bytes', 'uploaded_bytes', 'tx_bytes', 'up_bytes']);
        $trafficDownload = $trafficBytesFrom($trafficPayload, ['download_bytes', 'downloaded_bytes', 'rx_bytes', 'down_bytes']);
        if ($trafficTotal === null || $trafficUpload === null || $trafficDownload === null) {
            $sumTotal = 0;
            $sumUpload = 0;
            $sumDownload = 0;
            foreach ($trafficDevices as $trafficDevice) {
                if (! is_array($trafficDevice)) continue;
                $sumTotal += (float) ($deviceTraffic($trafficDevice) ?? 0);
                $sumUpload += (float) ($trafficDevice['tx_bytes'] ?? $trafficDevice['upload_bytes'] ?? $trafficDevice['uploaded_bytes'] ?? $trafficDevice['up_bytes'] ?? 0);
                $sumDownload += (float) ($trafficDevice['rx_bytes'] ?? $trafficDevice['download_bytes'] ?? $trafficDevice['downloaded_bytes'] ?? $trafficDevice['down_bytes'] ?? 0);
            }
            $trafficTotal ??= $sumTotal > 0 ? $sumTotal : null;
            $trafficUpload ??= $sumUpload > 0 ? $sumUpload : null;
            $trafficDownload ??= $sumDownload > 0 ? $sumDownload : null;
        }
        if ($trafficTotal === null && $localSubscription && is_numeric($localSubscription->traffic_used_gb)) {
            $trafficTotal = (float) $localSubscription->traffic_used_gb * 1024 * 1024 * 1024;
        }
    @endphp
    <div class="adm-user-core-stack">
        <section class="adm-card adm-core-card" id="user-traffic">
            <div class="adm-card-head adm-card-head--row">
                <div>
                    <h6>Трафик пользователя</h6>
                    <p>Сводка из Core по пользователю и устройствам.</p>
                </div>
            </div>
            <div class="adm-core-session">
                <div>
                    <span>Всего</span>
                    <strong>{{ $fmtCoreBytes($trafficTotal) }}</strong>
                </div>
                <div>
                    <span>Upload</span>
                    <strong>{{ $fmtCoreBytes($trafficUpload) }}</strong>
                </div>
                <div>
                    <span>Download</span>
                    <strong>{{ $fmtCoreBytes($trafficDownload) }}</strong>
                </div>
            </div>
        </section>

        <section class="adm-card adm-core-card" data-core-user="{{ $row->id }}">
            <div class="adm-card-head adm-card-head--row">
                <div>
                    <h6>Устройства подписки</h6>
                    <p>Данные из Core. Лимит устройств сейчас не считается жёсткой блокировкой.</p>
                </div>
                <button type="button" class="adm-btn adm-btn-ghost adm-btn-sm" onclick="admReloadUserDevices()">Обновить</button>
            </div>

            <div id="admUserDevicesState" class="adm-core-status" @if(is_array($coreDevices)) hidden @endif>
                {{ $coreDevices === null ? 'Core не вернул список устройств.' : 'Загружаем устройства...' }}
            </div>

            <div class="adm-core-table-wrap adm-core-table-wrap--devices" id="admUserDevicesWrap" @if(! is_array($coreDevices) || count($coreDevices) === 0) hidden @endif>
                <table class="adm-table adm-core-table">
                    <thead>
                        <tr>
                            <th>Устройство</th>
                            <th>Активность</th>
                            <th>Трафик</th>
                            <th>Сеть</th>
                            <th></th>
                        </tr>
                    </thead>
                    <tbody id="admUserDevicesRows">
                        @foreach(($coreDevices ?? []) as $device)
                            @php
                                $isDeviceActive = (bool) ($device['is_active'] ?? false);
                                $deviceTrafficBytes = $deviceTraffic($device);
                            @endphp
                            <tr data-device-id="{{ $device['id'] ?? '' }}">
                                <td>
                                    <strong>{{ $device['display_name'] ?? ('Device #' . ($device['id'] ?? '—')) }}</strong>
                                    <span>{{ $device['platform'] ?? 'unknown' }} · fetch {{ $device['fetch_count'] ?? 0 }}</span>
                                </td>
                                <td>
                                    <span class="adm-core-pill {{ $isDeviceActive ? 'is-ok' : 'is-muted' }}">{{ $isDeviceActive ? 'Активно' : 'Отключено' }}</span>
                                    <small>last: {{ $device['last_seen'] ?? '—' }}</small>
                                </td>
                                <td>
                                    <span>{{ $fmtCoreBytes($deviceTrafficBytes) }}</span>
                                    <small>rx {{ $fmtCoreBytes($device['rx_bytes'] ?? $device['download_bytes'] ?? $device['downloaded_bytes'] ?? $device['down_bytes'] ?? null) }} · tx {{ $fmtCoreBytes($device['tx_bytes'] ?? $device['upload_bytes'] ?? $device['uploaded_bytes'] ?? $device['up_bytes'] ?? null) }}</small>
                                </td>
                                <td>
                                    <span>{{ $device['ip_address'] ?? '—' }}</span>
                                    <small>{{ $device['user_agent'] ?? '—' }}</small>
                                </td>
                                <td class="adm-core-actions">
                                    @if($isDeviceActive)
                                        <button type="button" class="adm-btn adm-btn-sm adm-btn-danger adm-btn-icon-text" onclick="admToggleUserDevice({{ (int) ($device['id'] ?? 0) }}, false)" title="Отключить устройство">
                                            <svg viewBox="0 0 24 24" fill="none" aria-hidden="true"><path d="M18 6 6 18M6 6l12 12" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></svg>
                                            <span>Отключить</span>
                                        </button>
                                    @else
                                        <button type="button" class="adm-btn adm-btn-sm adm-btn-ghost" onclick="admToggleUserDevice({{ (int) ($device['id'] ?? 0) }}, true)">Включить</button>
                                    @endif
                                </td>
                            </tr>
                        @endforeach
                    </tbody>
                </table>
            </div>

            <p class="adm-empty-state" id="admUserDevicesEmpty" @if(is_array($coreDevices) && count($coreDevices) === 0) @else hidden @endif>
                Устройств пока нет.
            </p>
        </section>

        <section class="adm-card adm-core-card">
            <div class="adm-card-head adm-card-head--row">
                <div>
                    <h6>Активные сессии</h6>
                    <p>Best-effort оценка подключений пользователя по данным Core.</p>
                </div>
                <button type="button" class="adm-btn adm-btn-ghost adm-btn-sm" onclick="admReloadUserSessions()">Проверить</button>
            </div>

            <div class="adm-core-session" id="admUserSessions">
                @if(is_array($coreActiveSessions))
                    <div>
                        <span>Устройств отслеживается</span>
                        <strong>{{ $coreActiveSessions['tracked_devices'] ?? '—' }}</strong>
                    </div>
                    <div>
                        <span>Активных сейчас</span>
                        <strong>{{ $coreActiveSessions['estimated_active'] ?? '—' }}</strong>
                    </div>
                    <div>
                        <span>Ноды</span>
                        <strong>
                            @forelse(($coreActiveSessions['nodes'] ?? []) as $node)
                                {{ $node['name'] ?? 'node' }}: {{ $node['active_ips'] ?? 0 }}@if(! $loop->last), @endif
                            @empty
                                —
                            @endforelse
                        </strong>
                    </div>
                @else
                    <p class="adm-empty-state">Core не вернул активные сессии. Возможно, SSH/логи xray не настроены.</p>
                @endif
            </div>
        </section>
    </div>
@endif

@if($resource === 'users')
@push('scripts')
<script>
const admCoreUserId = @json($row->id);
const admCoreRoutes = {
    devices: @json(route('admin.users.core-devices', ['user' => $row->id])),
    sessions: @json(route('admin.users.active-sessions', ['user' => $row->id])),
    traffic: @json(route('admin.users.traffic', ['user' => $row->id])),
    deactivateTemplate: @json(route('admin.users.core-devices.deactivate', ['user' => $row->id, 'device' => '__DEVICE__'])),
    reactivateTemplate: @json(route('admin.users.core-devices.reactivate', ['user' => $row->id, 'device' => '__DEVICE__'])),
};

function admCsrf() {
    return document.querySelector('meta[name="csrf-token"]')?.content || '';
}

function admRenderDevices(devices) {
    const wrap = document.getElementById('admUserDevicesWrap');
    const rows = document.getElementById('admUserDevicesRows');
    const empty = document.getElementById('admUserDevicesEmpty');
    const state = document.getElementById('admUserDevicesState');
    if (!wrap || !rows) return;

    rows.innerHTML = '';
    if (!devices || !devices.length) {
        wrap.hidden = true;
        if (empty) empty.hidden = false;
        if (state) state.hidden = true;
        return;
    }

    devices.forEach(function(device) {
        const active = !!device.is_active;
        const totalTraffic = admDeviceTrafficBytes(device);
        const tr = document.createElement('tr');
        tr.dataset.deviceId = device.id || '';
        tr.innerHTML =
            '<td><strong>' + admEscape(device.display_name || ('Device #' + (device.id || '—'))) + '</strong><span>' + admEscape(device.platform || 'unknown') + ' · fetch ' + admEscape(String(device.fetch_count || 0)) + '</span></td>' +
            '<td><span class="adm-core-pill ' + (active ? 'is-ok' : 'is-muted') + '">' + (active ? 'Активно' : 'Отключено') + '</span><small>last: ' + admEscape(device.last_seen || '—') + '</small></td>' +
            '<td><span>' + admEscape(admFmtBytes(totalTraffic)) + '</span><small>rx ' + admEscape(admFmtBytes(admFirstNumber(device, ['rx_bytes', 'download_bytes', 'downloaded_bytes', 'down_bytes']))) + ' · tx ' + admEscape(admFmtBytes(admFirstNumber(device, ['tx_bytes', 'upload_bytes', 'uploaded_bytes', 'up_bytes']))) + '</small></td>' +
            '<td><span>' + admEscape(device.ip_address || '—') + '</span><small>' + admEscape(device.user_agent || '—') + '</small></td>' +
            '<td class="adm-core-actions"><button type="button" class="adm-btn adm-btn-sm ' + (active ? 'adm-btn-danger adm-btn-icon-text' : 'adm-btn-ghost') + '" onclick="admToggleUserDevice(' + Number(device.id || 0) + ', ' + (!active) + ')" title="' + (active ? 'Отключить устройство' : 'Включить устройство') + '">' + (active ? '<svg viewBox="0 0 24 24" fill="none" aria-hidden="true"><path d="M18 6 6 18M6 6l12 12" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></svg><span>Отключить</span>' : 'Включить') + '</button></td>';
        rows.appendChild(tr);
    });

    wrap.hidden = false;
    if (empty) empty.hidden = true;
    if (state) state.hidden = true;
}

function admDeviceTrafficBytes(device) {
    for (const key of ['traffic_bytes', 'total_bytes', 'used_bytes', 'bytes', 'total_traffic_bytes', 'traffic_total_bytes']) {
        if (Number.isFinite(Number(device[key]))) return Number(device[key]);
    }
    for (const key of ['traffic_gb', 'used_gb', 'total_gb']) {
        if (Number.isFinite(Number(device[key]))) return Number(device[key]) * 1024 * 1024 * 1024;
    }
    const rx = Number(admFirstNumber(device, ['rx_bytes', 'download_bytes', 'downloaded_bytes', 'down_bytes']) || 0);
    const tx = Number(admFirstNumber(device, ['tx_bytes', 'upload_bytes', 'uploaded_bytes', 'up_bytes']) || 0);
    return (rx + tx) > 0 ? rx + tx : null;
}

function admFirstNumber(source, keys) {
    for (const key of keys) {
        if (Number.isFinite(Number(source[key]))) return Number(source[key]);
    }
    return null;
}

function admFmtBytes(bytes) {
    if (bytes === null || bytes === undefined || bytes === '' || !Number.isFinite(Number(bytes))) return '—';
    bytes = Math.max(0, Number(bytes));
    const units = ['Б', 'КБ', 'МБ', 'ГБ', 'ТБ'];
    const power = bytes > 0 ? Math.min(Math.floor(Math.log(bytes) / Math.log(1024)), units.length - 1) : 0;
    const value = power > 0 ? bytes / Math.pow(1024, power) : bytes;
    return value.toFixed(power >= 3 ? 1 : 0).replace('.', '.') + ' ' + units[power];
}

function admEscape(value) {
    return String(value).replace(/[&<>"']/g, function(ch) {
        return {'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#039;'}[ch];
    });
}

function admReloadUserDevices() {
    const state = document.getElementById('admUserDevicesState');
    if (state) { state.hidden = false; state.textContent = 'Загружаем устройства...'; }
    window.admShowLoader?.('Обновляем устройства', 'Запрашиваем свежий список из Core.');

    fetch(admCoreRoutes.devices, { headers: { 'Accept': 'application/json' } })
        .then(r => r.json().then(data => ({ ok: r.ok, data })))
        .then(({ ok, data }) => {
            if (!ok || !data.ok) throw new Error(data.error || 'Core не вернул устройства');
            admRenderDevices(data.devices || []);
        })
        .catch(error => {
            if (state) { state.hidden = false; state.textContent = error.message || 'Не удалось загрузить устройства.'; }
        })
        .finally(() => window.admHideLoader?.());
}

function admToggleUserDevice(deviceId, reactivate) {
    if (!deviceId) return;
    const url = (reactivate ? admCoreRoutes.reactivateTemplate : admCoreRoutes.deactivateTemplate).replace('__DEVICE__', deviceId);
    window.admShowLoader?.(reactivate ? 'Включаем устройство' : 'Отключаем устройство', 'Отправляем команду в Core.');

    fetch(url, {
        method: reactivate ? 'POST' : 'DELETE',
        headers: {
            'X-CSRF-TOKEN': admCsrf(),
            'Accept': 'application/json',
        },
    })
        .then(r => r.json().then(data => ({ ok: r.ok, data })))
        .then(({ ok, data }) => {
            if (!ok || !data.ok) throw new Error(data.error || 'Core не принял действие');
            admReloadUserDevices();
        })
        .catch(error => alert(error.message || 'Не удалось выполнить действие'))
        .finally(() => window.admHideLoader?.());
}

function admReloadUserSessions() {
    const target = document.getElementById('admUserSessions');
    window.admShowLoader?.('Проверяем сессии', 'Запрашиваем активные подключения из Core.');

    fetch(admCoreRoutes.sessions, { headers: { 'Accept': 'application/json' } })
        .then(r => r.json().then(data => ({ ok: r.ok, data })))
        .then(({ ok, data }) => {
            if (!ok || !data.ok) throw new Error(data.error || 'Core не вернул сессии');
    const sessions = data.sessions || {};
            const sessionNodes = sessions.nodes || sessions.items || sessions.sessions || [];
            const nodes = sessionNodes.map(node => admEscape(node.name || node.node || 'node') + ': ' + admEscape(String(node.active_ips || node.active_sessions || node.count || 0))).join(', ') || '—';
            target.innerHTML =
                '<div><span>Устройств отслеживается</span><strong>' + admEscape(String(sessions.tracked_devices ?? sessions.devices_count ?? '—')) + '</strong></div>' +
                '<div><span>Активных сейчас</span><strong>' + admEscape(String(sessions.estimated_active ?? sessions.active_sessions ?? sessions.online ?? '—')) + '</strong></div>' +
                '<div><span>Ноды</span><strong>' + nodes + '</strong></div>';
        })
        .catch(error => {
            target.innerHTML = '<p class="adm-empty-state">' + admEscape(error.message || 'Не удалось проверить сессии.') + '</p>';
        })
        .finally(() => window.admHideLoader?.());
}
</script>
@endpush
@endif
@endsection
