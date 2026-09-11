<!doctype html>
<html lang="ru">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Auralith | Восстановление доступа</title>
    <link rel="icon" type="image/png" sizes="32x32" href="{{ asset('images/favicon-32.png') }}?v=brand4">
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&family=Montserrat:wght@600;700&display=swap" rel="stylesheet">
    <link rel="stylesheet" href="{{ asset('css/auth.css') }}?v=9">
</head>
<body>
<div class="auth-wrap">
    <a href="{{ route('home') }}" class="brand">
        <img src="{{ asset('images/logo-mark.png') }}?v=brand4" alt="Auralith logo">
        <span>Auralith</span>
    </a>

    <div class="card">
        <p class="eyebrow">Восстановление</p>
        <h1>Забыли доступ?</h1>
        <p class="hint">Если к аккаунту привязан Telegram, мы подтвердим личность через бота и дадим задать новый пароль.</p>

        @if ($errors->any())
            <div class="alert">
                @foreach ($errors->all() as $error)
                    <p>{{ $error }}</p>
                @endforeach
            </div>
        @endif

        @if(! empty($supportRequired))
            <div class="auth-note">
                <strong>Нужна помощь поддержки</strong>
                <span>{{ $supportReason }}</span>
            </div>

            <div class="manual-command">
                <span>Сообщение уже подготовлено. Скопируйте его и отправьте в поддержку Telegram:</span>
                <code id="support-message">{{ $supportMessage }}</code>
                <button type="button" onclick="copySupportMessage(this)">Копировать сообщение</button>
            </div>

            <a href="{{ $supportUrl }}" target="_blank" rel="noopener" class="tg-login-btn" onclick="copyAndOpenSupport(event, this.href)">
                <svg viewBox="0 0 24 24" fill="none" width="20" height="20">
                    <path d="M21.8 2.2L1 10.1c-1.3.5-1.3 1.3-.2 1.6l5.2 1.6 2 6.3c.3.8.5 1.1 1.1 1.1.5 0 .7-.2 1-.5l2.5-2.4 5.2 3.8c1 .5 1.6.3 1.9-.9L23 3.3c.4-1.5-.6-2.2-1.2-1.1z" stroke="currentColor" stroke-width="1.6" stroke-linejoin="round"/>
                </svg>
                Скопировать и открыть поддержку
            </a>
            <p class="demo-text">Telegram не позволяет сайту надёжно вставить текст в конкретный чат автоматически. Мы скопируем сообщение, откроем <a href="{{ $supportUrl }}" target="_blank" rel="noopener" style="color:#6b93c0">@auralith_support</a>, дальше останется вставить текст и отправить.</p>
            <p class="demo-text"><a href="{{ route('account-recovery.request') }}" style="color:#6b93c0">Попробовать ещё раз</a> · <a href="{{ route('login') }}" style="color:#6b93c0">Вернуться ко входу</a></p>
        @elseif(! empty($recoveryStarted))
            <div class="auth-note">
                <strong>Подтвердите восстановление в Telegram</strong>
                <span>Откройте бота и подтвердите восстановление. Если Telegram просто открыл чат без команды, отправьте команду ниже вручную. Ссылка активна {{ $expiresIn }} минут.</span>
            </div>

            <a href="{{ $tgDeepLink ?? $deepLink }}" class="tg-login-btn" id="recovery-deep-link">
                <svg viewBox="0 0 24 24" fill="none" width="20" height="20">
                    <path d="M21.8 2.2L1 10.1c-1.3.5-1.3 1.3-.2 1.6l5.2 1.6 2 6.3c.3.8.5 1.1 1.1 1.1.5 0 .7-.2 1-.5l2.5-2.4 5.2 3.8c1 .5 1.6.3 1.9-.9L23 3.3c.4-1.5-.6-2.2-1.2-1.1z" stroke="currentColor" stroke-width="1.6" stroke-linejoin="round"/>
                </svg>
                Открыть Telegram
            </a>

            <div class="manual-command">
                <span>Команда для ручной отправки боту:</span>
                <code id="recovery-manual-command">{{ $manualCommand }}</code>
                <button type="button" onclick="copyRecoveryCommand(this)">Копировать команду</button>
            </div>

            <div id="recovery-status" class="auth-status">Ждём подтверждение в Telegram...</div>
            <p class="demo-text">Telegram не привязан или бот не открывается? <a href="{{ $supportUrl }}" target="_blank" rel="noopener" style="color:#6b93c0">Написать в @auralith_support</a></p>
        @else
            <form method="post" action="{{ route('account-recovery.request.submit') }}">
                @csrf
                <label>
                    Логин или Telegram ID
                    <input type="text" name="identifier" value="{{ old('identifier') }}" placeholder="Например: user123 или 701337001" required autofocus>
                </label>
                <button type="submit">Продолжить через Telegram</button>
            </form>

            <div class="auth-note" style="margin-top:14px">
                <strong>Telegram не привязан?</strong>
                <span>Автоматически восстановить доступ нельзя. Мы перенаправим вас в поддержку, где можно подтвердить личность по заказу.</span>
            </div>

            <p class="demo-text"><a href="{{ route('login') }}" style="color:#6b93c0">Вернуться ко входу</a> · <a href="{{ $supportUrl }}" target="_blank" rel="noopener" style="color:#6b93c0">@auralith_support</a></p>
        @endif
    </div>
</div>

<script>
function copySupportMessage(btn) {
    var el = document.getElementById('support-message');
    var text = el ? el.textContent.trim() : '';
    var done = function() {
        if (!btn) return;
        var old = btn.textContent;
        btn.textContent = 'Скопировано';
        setTimeout(function() { btn.textContent = old; }, 1800);
    };
    if (navigator.clipboard && window.isSecureContext) {
        navigator.clipboard.writeText(text).then(done).catch(function() {});
        return;
    }
    var ta = document.createElement('textarea');
    ta.value = text;
    ta.style.position = 'fixed';
    ta.style.left = '-9999px';
    document.body.appendChild(ta);
    ta.select();
    try { document.execCommand('copy'); done(); } catch (e) {}
    document.body.removeChild(ta);
}

function copyAndOpenSupport(event, url) {
    event.preventDefault();
    var el = document.getElementById('support-message');
    var text = el ? el.textContent.trim() : '';
    var openSupport = function() {
        window.open(url, '_blank', 'noopener');
    };

    if (navigator.clipboard && window.isSecureContext) {
        navigator.clipboard.writeText(text).finally(openSupport);
        return;
    }

    var ta = document.createElement('textarea');
    ta.value = text;
    ta.style.position = 'fixed';
    ta.style.left = '-9999px';
    document.body.appendChild(ta);
    ta.select();
    try { document.execCommand('copy'); } catch (e) {}
    document.body.removeChild(ta);
    openSupport();
}
</script>

@if(! empty($recoveryStarted))
<script>
(function () {
    var statusUrl = @json($statusUrl);
    var telegramUrl = @json($tgDeepLink ?? $deepLink);
    var statusEl = document.getElementById('recovery-status');
    var deepLinkEl = document.getElementById('recovery-deep-link');
    var timer = null;
    var timeout = null;

    function setStatus(text) {
        if (statusEl) statusEl.textContent = text;
    }

    window.copyRecoveryCommand = function(btn) {
        var el = document.getElementById('recovery-manual-command');
        var text = el ? el.textContent.trim() : '';
        var done = function() {
            var old = btn.textContent;
            btn.textContent = 'Скопировано';
            setTimeout(function() { btn.textContent = old; }, 1800);
        };
        if (navigator.clipboard && window.isSecureContext) {
            navigator.clipboard.writeText(text).then(done).catch(function() {});
            return;
        }
        var ta = document.createElement('textarea');
        ta.value = text;
        ta.style.position = 'fixed';
        ta.style.left = '-9999px';
        document.body.appendChild(ta);
        ta.select();
        try { document.execCommand('copy'); done(); } catch (e) {}
        document.body.removeChild(ta);
    };

    function poll() {
        fetch(statusUrl, {
            headers: { 'Accept': 'application/json' },
            credentials: 'same-origin'
        })
        .then(function (response) { return response.json().then(function (data) { return { ok: response.ok, data: data }; }); })
        .then(function (result) {
            if (result.ok && result.data.confirmed && result.data.redirect) {
                clearInterval(timer);
                clearTimeout(timeout);
                setStatus('Подтверждено. Открываем страницу смены пароля...');
                window.location.href = result.data.redirect;
                return;
            }

            if (result.data && result.data.expired) {
                clearInterval(timer);
                clearTimeout(timeout);
                setStatus(result.data.message || 'Ссылка устарела. Запросите восстановление ещё раз или напишите в поддержку.');
            }
        })
        .catch(function () {
            setStatus('Не удалось проверить подтверждение. Страница продолжит ожидание, но если бот уже подтвердил запрос — обновите страницу.');
        });
    }

    timer = setInterval(poll, 1500);
    timeout = setTimeout(function () {
        clearInterval(timer);
        setStatus('Время ожидания истекло. Запросите восстановление ещё раз или напишите в поддержку.');
    }, 15 * 60 * 1000);
    poll();

    setTimeout(function () {
        setStatus('Открываем Telegram для подтверждения восстановления...');
        if (deepLinkEl) deepLinkEl.dataset.autoOpened = '1';
        window.location.href = telegramUrl;
    }, 250);
})();
</script>
@endif
</body>
</html>
