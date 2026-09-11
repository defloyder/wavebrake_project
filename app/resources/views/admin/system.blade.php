@extends('admin.layout')

@section('title', 'System')

@section('content')
<div style="margin-bottom:20px">
    <p style="margin:0;font-size:.72rem;color:var(--muted);letter-spacing:.1em;text-transform:uppercase">Auralith Admin</p>
    <h2 style="margin:4px 0 0;font-family:'Montserrat',sans-serif;font-size:1.5rem">Система</h2>
</div>

<div class="adm-system-grid">
    <section class="adm-card">
        <div class="adm-card-head adm-card-head--row">
            <div>
                <h6>Проверка состояния</h6>
                <p>Быстрые live-проверки базы, SEO-файлов, Web Push и файловой системы.</p>
                <p class="adm-live-meta">Обновлено: <span id="systemChecksUpdated">сейчас</span></p>
            </div>
            <form method="POST" action="{{ route('admin.system.tests') }}" data-loader-title="Запускаем тесты" data-loader-detail="PHPUnit выполняется на сервере, это может занять несколько секунд.">
                @csrf
                <button type="submit" class="adm-btn adm-btn-sm">Запустить тесты</button>
            </form>
        </div>

        <div class="adm-check-list" id="systemChecksList">
            @foreach($checks as $check)
                <article class="adm-check-row {{ $check['ok'] ? 'is-ok' : 'is-fail' }}">
                    <span class="adm-check-row__dot"></span>
                    <div>
                        <strong>{{ $check['label'] }}</strong>
                        <p>{{ $check['message'] }}</p>
                    </div>
                </article>
            @endforeach
        </div>
    </section>

    <section class="adm-card">
        <div class="adm-card-head">
            <div>
                <h6>Тесты</h6>
                <p>{{ $testRunnerLabel }}</p>
            </div>
        </div>
        @if($testResult)
            <div class="adm-test-result {{ $testResult['ok'] ? 'is-ok' : 'is-fail' }}">
                <strong>{{ $testResult['ok'] ? 'Тесты прошли' : 'Тесты упали' }}</strong>
                <span>Exit code: {{ $testResult['exit_code'] ?? 'n/a' }}</span>
            </div>
            <pre class="adm-test-output">{{ $testResult['output'] }}</pre>
        @else
            <p class="adm-empty-state">Тесты ещё не запускались из админки.</p>
        @endif
    </section>
</div>
@endsection

@push('scripts')
<script>
(function () {
    const list = document.getElementById('systemChecksList');
    const updated = document.getElementById('systemChecksUpdated');
    if (!list || !updated) return;

    function escapeHtml(value) {
        return String(value)
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;')
            .replace(/'/g, '&#039;');
    }

    function render(checks) {
        list.innerHTML = checks.map((check) => `
            <article class="adm-check-row ${check.ok ? 'is-ok' : 'is-fail'}">
                <span class="adm-check-row__dot"></span>
                <div>
                    <strong>${escapeHtml(check.label)}</strong>
                    <p>${escapeHtml(check.message)}</p>
                </div>
            </article>
        `).join('');
    }

    function updateTime(value) {
        const date = value ? new Date(value) : new Date();
        updated.textContent = date.toLocaleTimeString('ru-RU', {
            hour: '2-digit',
            minute: '2-digit',
            second: '2-digit',
        });
    }

    async function refreshChecks() {
        try {
            const response = await fetch('{{ route('admin.system.checks') }}', {
                headers: { 'Accept': 'application/json' },
                credentials: 'same-origin',
            });
            if (!response.ok) return;

            const data = await response.json();
            render(data.checks || []);
            updateTime(data.checked_at);
        } catch (e) {}
    }

    updateTime(@json($checkedAt));
    setInterval(refreshChecks, 15000);
})();
</script>
@endpush
