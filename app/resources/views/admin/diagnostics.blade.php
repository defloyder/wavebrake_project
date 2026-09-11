@extends('admin.layout')

@section('title', 'Диагностика')

@section('content')
<div class="adm-diagnostics-page">
    <div style="margin-bottom:20px">
        <p style="margin:0;font-size:.72rem;color:var(--muted);letter-spacing:.1em;text-transform:uppercase">Поддержка клиента</p>
        <h2 style="margin:4px 0 0;font-family:'Montserrat',sans-serif;font-size:1.5rem">Диагностика приложения</h2>
    </div>

    <section class="adm-card adm-support-card adm-diagnostics-card">
        <div class="adm-card-head adm-card-head--row">
            <div>
                <h6>Поиск по support code</h6>
                <p>Найдите приложение, запросите диагностику и проверьте последние данные клиента.</p>
            </div>
        </div>

        <form class="adm-support-search" id="admSupportSearch" data-no-loader="1">
            <label>
                Код поддержки
                <input type="text" class="adm-input" name="support_code" id="admSupportCode" placeholder="Например: AL-EX6H-XDMY-CPUY" autocomplete="off" required autofocus>
            </label>
            <button type="submit" class="adm-btn">Найти клиента</button>
        </form>

        <div class="adm-support-result" id="admSupportResult" hidden></div>
    </section>

    <section class="adm-card adm-app-clients-card">
        <div class="adm-card-head adm-card-head--row">
            <div>
                <h6>app_clients</h6>
                <p>Все зарегистрированные клиенты приложения из Core. Нажмите support code, чтобы открыть карточку выше.</p>
            </div>
            <span class="adm-app-clients-count">{{ count($appClients ?? []) }} записей</span>
        </div>

        @if($appClientsError)
            <p class="adm-empty-state">{{ $appClientsError }}</p>
        @elseif(empty($appClients))
            <p class="adm-empty-state">Клиентов пока нет.</p>
        @else
            @php
                $preferredColumns = ['id', 'user_id', 'telegram_id', 'install_id', 'support_code', 'platform', 'app_version', 'device_name', 'status', 'last_seen_at', 'last_heartbeat_at', 'diagnostics_requested_at', 'diagnostics_uploaded_at'];
                $allColumns = collect($appClients)
                    ->flatMap(fn($client) => array_keys((array) $client))
                    ->unique()
                    ->values()
                    ->all();
                $columns = collect($preferredColumns)
                    ->filter(fn($column) => in_array($column, $allColumns, true))
                    ->merge(collect($allColumns)->reject(fn($column) => in_array($column, $preferredColumns, true)))
                    ->values()
                    ->all();
            @endphp

            <div class="adm-app-clients-table-wrap">
                <table class="adm-table adm-app-clients-table">
                    <thead>
                        <tr>
                            @foreach($columns as $column)
                                <th>{{ $column }}</th>
                            @endforeach
                            <th></th>
                        </tr>
                    </thead>
                    <tbody>
                        @foreach($appClients as $client)
                            @php
                                $client = (array) $client;
                                $supportCode = (string) ($client['support_code'] ?? '');
                            @endphp
                            <tr>
                                @foreach($columns as $column)
                                    @php
                                        $value = $client[$column] ?? null;
                                        $displayValue = is_array($value)
                                            ? json_encode($value, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES)
                                            : ($value ?? '—');
                                    @endphp
                                    <td class="{{ $column === 'support_code' ? 'adm-app-client-code-cell' : '' }}">
                                        @if($column === 'support_code' && $supportCode !== '')
                                            <button type="button" class="adm-app-client-code" data-support-code="{{ $supportCode }}">{{ $supportCode }}</button>
                                        @elseif(is_bool($value))
                                            {{ $value ? 'true' : 'false' }}
                                        @else
                                            {{ $displayValue }}
                                        @endif
                                    </td>
                                @endforeach
                                <td class="adm-app-clients-actions">
                                    @if($supportCode !== '')
                                        <button type="button" class="adm-btn adm-btn-sm adm-btn-ghost" data-support-code="{{ $supportCode }}">Открыть</button>
                                    @endif
                                </td>
                            </tr>
                        @endforeach
                    </tbody>
                </table>
            </div>
        @endif
    </section>
</div>
@endsection

@push('scripts')
<script>
const admSupportRoutes = {
    lookup: @json(route('admin.support.app-client')),
    diagnosticsTemplate: @json(route('admin.support.app-client.diagnostics', ['supportCode' => '__CODE__'])),
    requestDiagnosticsTemplate: @json(route('admin.support.app-client.request-diagnostics', ['supportCode' => '__CODE__'])),
};

function admDashboardCsrf() {
    return document.querySelector('meta[name="csrf-token"]')?.content || '';
}

function admHtml(value) {
    return String(value ?? '').replace(/[&<>"']/g, function(ch) {
        return {'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#039;'}[ch];
    });
}

function admSupportUrl(template, code) {
    return template.replace('__CODE__', encodeURIComponent(code));
}

function admRenderSupportClient(client, supportCode) {
    const result = document.getElementById('admSupportResult');
    if (!result) return;

    const rows = [
        ['Support code', supportCode],
        ['Платформа', client.platform || client.os || '—'],
        ['Версия', client.version || client.app_version || '—'],
        ['Пользователь', client.user_id ? ('User #' + client.user_id) : '—'],
        ['Последний heartbeat', client.last_heartbeat_at || client.last_seen || '—'],
        ['Диагностика запрошена', client.diagnostics_requested ? 'Да' : 'Нет'],
    ];

    result.hidden = false;
    result.innerHTML =
        '<div class="adm-support-result__head">' +
            '<div class="adm-support-title">' +
                '<span class="adm-support-status">Клиент найден</span>' +
                '<strong>' + admHtml(client.device_name || client.display_name || 'Auralith Client') + '</strong>' +
                '<small>' + admHtml(client.status || 'active') + '</small>' +
            '</div>' +
            '<div class="adm-support-actions">' +
                '<button type="button" class="adm-support-action adm-support-action--request" data-support-action="request" data-support-code="' + admHtml(supportCode) + '">' +
                    '<svg viewBox="0 0 24 24" fill="none" aria-hidden="true"><path d="M12 3v10M8 9l4 4 4-4" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"/><path d="M5 15v3a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2v-3" stroke="currentColor" stroke-width="1.9" stroke-linecap="round"/></svg>' +
                    '<span><strong>Запросить</strong><small>при следующем heartbeat</small></span>' +
                '</button>' +
                '<button type="button" class="adm-support-action adm-support-action--view" data-support-action="diagnostics" data-support-code="' + admHtml(supportCode) + '">' +
                    '<svg viewBox="0 0 24 24" fill="none" aria-hidden="true"><path d="M4 5h16v14H4V5Z" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"/><path d="M8 9h8M8 13h5M8 17h7" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/></svg>' +
                    '<span><strong>Показать</strong><small>последний отчёт</small></span>' +
                '</button>' +
            '</div>' +
        '</div>' +
        '<div class="adm-support-facts">' +
            rows.map(function(row) {
                return '<div><span>' + admHtml(row[0]) + '</span><strong>' + admHtml(row[1]) + '</strong></div>';
            }).join('') +
        '</div>' +
        admRenderDiagnosticsPayload(client);
}

function admNormalizeDiagnosticText(value) {
    if (!value) return '';

    return String(value)
        .replace(/\\r\\n/g, '\n')
        .replace(/\\n/g, '\n')
        .replace(/\\t/g, '    ')
        .replace(/\r\n/g, '\n')
        .trim();
}

function admRenderDiagnosticsPayload(payload) {
    const text = admNormalizeDiagnosticText(payload?.diagnostics_text || payload?.diagnostics || payload?.text || '');
    const metaRows = [
        ['diagnostics_requested_at', payload?.diagnostics_requested_at],
        ['diagnostics_uploaded_at', payload?.diagnostics_uploaded_at],
        ['created_at', payload?.created_at],
    ].filter(function(row) { return row[1] !== undefined && row[1] !== null && row[1] !== ''; });

    return '<section class="adm-diagnostics-output">' +
        (metaRows.length ? '<div class="adm-diagnostics-meta">' + metaRows.map(function(row) {
            return '<div><span>' + admHtml(row[0]) + '</span><strong>' + admHtml(row[1]) + '</strong></div>';
        }).join('') + '</div>' : '') +
        (text
            ? '<div class="adm-diagnostics-text"><div class="adm-diagnostics-text__head"><span>Отчёт диагностики</span><button type="button" onclick="admCopyDiagnosticsText()">Копировать</button></div><pre id="admDiagnosticsText">' + admHtml(text) + '</pre></div>'
            : '<p class="adm-empty-state">Текст диагностики пока не загружен.</p>') +
        '<details class="adm-diagnostics-raw"><summary>Сырой JSON</summary><pre class="adm-support-json" id="admSupportJson">' + admHtml(JSON.stringify(payload, null, 2)) + '</pre></details>' +
    '</section>';
}

function admReplaceDiagnosticsPayload(payload) {
    const output = document.querySelector('.adm-diagnostics-output');
    if (output) {
        output.outerHTML = admRenderDiagnosticsPayload(payload || {});
        return;
    }

    const result = document.getElementById('admSupportResult');
    if (result) {
        result.insertAdjacentHTML('beforeend', admRenderDiagnosticsPayload(payload || {}));
    }
}

function admCopyDiagnosticsText() {
    const text = document.getElementById('admDiagnosticsText')?.textContent || '';
    if (!text) return;
    navigator.clipboard?.writeText(text);
}

function admSupportError(message) {
    const result = document.getElementById('admSupportResult');
    if (!result) return;
    result.hidden = false;
    result.innerHTML = '<p class="adm-empty-state">' + admHtml(message || 'Клиент не найден.') + '</p>';
}

document.getElementById('admSupportSearch')?.addEventListener('submit', function(event) {
    event.preventDefault();
    const code = (document.getElementById('admSupportCode')?.value || '').trim();
    if (!code) return;

    window.admShowLoader?.('Ищем клиента', 'Запрашиваем карточку приложения в Core.');
    fetch(admSupportRoutes.lookup + '?support_code=' + encodeURIComponent(code), {
        headers: { 'Accept': 'application/json' },
    })
        .then(r => r.json().then(data => ({ ok: r.ok, data })))
        .then(({ ok, data }) => {
            if (!ok || !data.ok) throw new Error(data.error || 'Клиент с таким кодом не найден');
            admRenderSupportClient(data.client || {}, code);
        })
        .catch(error => admSupportError(error.message))
        .finally(() => window.admHideLoader?.());
});

document.querySelectorAll('[data-support-code]').forEach(function(button) {
    button.addEventListener('click', function() {
        const code = button.dataset.supportCode || '';
        const input = document.getElementById('admSupportCode');
        const form = document.getElementById('admSupportSearch');
        if (!code || !input || !form) return;

        input.value = code;
        form.dispatchEvent(new Event('submit', { cancelable: true }));
        window.scrollTo({ top: 0, behavior: 'smooth' });
    });
});

function admRequestDiagnostics(code) {
    window.admShowLoader?.('Запрашиваем диагностику', 'Core отметит клиента, приложение отправит файл после heartbeat.');
    fetch(admSupportUrl(admSupportRoutes.requestDiagnosticsTemplate, code), {
        method: 'POST',
        headers: {
            'X-CSRF-TOKEN': admDashboardCsrf(),
            'Accept': 'application/json',
        },
    })
        .then(r => r.json().then(data => ({ ok: r.ok, data })))
        .then(({ ok, data }) => {
            if (!ok || !data.ok) throw new Error(data.error || 'Не удалось запросить диагностику');
            admReplaceDiagnosticsPayload(data.result || data);
        })
        .catch(error => admSupportError(error.message))
        .finally(() => window.admHideLoader?.());
}

function admLoadDiagnostics(code) {
    window.admShowLoader?.('Получаем диагностику', 'Запрашиваем список диагностических файлов.');
    fetch(admSupportUrl(admSupportRoutes.diagnosticsTemplate, code), {
        headers: { 'Accept': 'application/json' },
    })
        .then(r => r.json().then(data => ({ ok: r.ok, data })))
        .then(({ ok, data }) => {
            if (!ok || !data.ok) throw new Error(data.error || 'Диагностики пока нет');
            admReplaceDiagnosticsPayload(data.diagnostics || data);
        })
        .catch(error => admSupportError(error.message))
        .finally(() => window.admHideLoader?.());
}

document.getElementById('admSupportResult')?.addEventListener('click', function(event) {
    const button = event.target.closest('[data-support-action]');
    if (!button) return;

    const code = button.dataset.supportCode || '';
    if (button.dataset.supportAction === 'request') {
        admRequestDiagnostics(code);
    } else {
        admLoadDiagnostics(code);
    }
});
</script>
@endpush
