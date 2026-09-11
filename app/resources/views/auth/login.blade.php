<!doctype html>
<html lang="ru">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Auralith | Вход</title>
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
        <p class="eyebrow">Личный кабинет</p>
        <h1>Вход в профиль</h1>

        @if ($errors->any())
            <div class="alert">
                @foreach ($errors->all() as $error)
                    <p>{{ $error }}</p>
                @endforeach
            </div>
        @endif

        @if(session('success'))
            <div class="alert" style="border-color:rgba(84,168,127,.5);background:rgba(63,128,92,.18)">
                {{ session('success') }}
            </div>
        @endif

        @if(request('telegram_error') === 'expired')
            <div class="alert">
                Ссылка входа через Telegram устарела или уже использована. Нажмите «Войти через Telegram» ещё раз и подтвердите вход в боте.
            </div>
        @endif

        <form method="post" action="{{ route('login.submit') }}">
            @csrf
            <label>
                Имя пользователя
                <input type="text" name="username" value="{{ old('username') }}" placeholder="Ваш логин" required autofocus>
            </label>
            <label>
                Пароль
                <input type="password" name="password" placeholder="Ваш пароль" required>
            </label>
            <button type="submit">Войти</button>
        </form>

        <p class="demo-text" style="margin-top:10px">
            <a href="{{ route('account-recovery.request') }}" style="color:#6b93c0">Забыли логин или пароль?</a>
        </p>

        <div id="webauthn-login-block" style="display:none">
            <div class="divider"><span>или</span></div>
            <div id="webauthn-section">
                <a href="#" class="tg-login-btn" id="webauthn-btn" onclick="startWebAuthn(event)">
                    <svg viewBox="0 0 24 24" fill="none" width="20" height="20">
                        <path d="M12 11v2.5M7.5 10.5v2A4.5 4.5 0 0 0 12 17a4.5 4.5 0 0 0 4.5-4.5v-2A4.5 4.5 0 0 0 12 6a4.5 4.5 0 0 0-4.5 4.5Z" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"/>
                        <path d="M5 12.5v-2a7 7 0 0 1 14 0v2M9 20.2A8.8 8.8 0 0 0 12 20a8.8 8.8 0 0 0 3-.5" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"/>
                    </svg>
                    Войти по отпечатку / Face ID
                </a>
                <div id="webauthn-error" style="display:none;text-align:center;color:#f87171;font-size:.82rem;margin-top:8px"></div>
            </div>
        </div>

        <div class="divider"><span>или</span></div>

        <div class="auth-note">
            <strong>Вход через Telegram</strong>
            <span>Старые ссылки из бота одноразовые. Если открываете бота впервые, сначала нажмите Start. Потом вернитесь сюда, нажмите кнопку ниже и подтвердите вход.</span>
        </div>

        <a href="#" class="tg-login-btn" id="tg-login-btn" onclick="startTgLogin(event)">
            <svg viewBox="0 0 24 24" fill="none" width="20" height="20">
                <path d="M21.8 2.2L1 10.1c-1.3.5-1.3 1.3-.2 1.6l5.2 1.6 2 6.3c.3.8.5 1.1 1.1 1.1.5 0 .7-.2 1-.5l2.5-2.4 5.2 3.8c1 .5 1.6.3 1.9-.9L23 3.3c.4-1.5-.6-2.2-1.2-1.1z" stroke="currentColor" stroke-width="1.6" stroke-linejoin="round"/>
            </svg>
            Войти через Telegram
        </a>
        <div id="tg-polling-hint" style="display:none;text-align:center;color:#8a94a6;font-size:.82rem;margin-top:8px">
            Откройте Telegram и подтвердите вход. Если бот только открылся, нажмите Start.
        </div>
        <div id="tg-manual-command" class="manual-command" style="display:none">
            <span>Если Telegram открыл чат без команды, нажмите Start или отправьте боту вручную:</span>
            <code id="tg-manual-command-text"></code>
            <button type="button" onclick="copyAuthCommand('tg-manual-command-text', this)">Копировать команду</button>
        </div>

        <p class="demo-text">Нет аккаунта? <a href="{{ route('register') }}" style="color:#6b93c0">Зарегистрироваться</a></p>

<script>
var _tgPollTimer = null;
var _tgTimeoutTimer = null;
var _sessionKey = null;

(async function() {
    if (!window.PublicKeyCredential) return;
    try {
        var available = await PublicKeyCredential.isUserVerifyingPlatformAuthenticatorAvailable().catch(function() { return false; });
        if (!available) return;
        var response = await fetch('{{ route("webauthn.has") }}', { headers: { 'Accept': 'application/json' } });
        var data = await response.json();
        if (data.has_credentials) {
            document.getElementById('webauthn-login-block').style.display = 'block';
        }
    } catch (e) {}
})();

function generateSessionKey() {
    return 's' + Math.random().toString(36).replace(/[^a-z0-9]/g, '').slice(2, 18) + Date.now().toString(36);
}

function startTgLogin(e) {
    e.preventDefault();

    if (_tgPollTimer) clearInterval(_tgPollTimer);
    if (_tgTimeoutTimer) clearTimeout(_tgTimeoutTimer);

    _sessionKey = generateSessionKey();
    var botUrl = 'https://t.me/auralithaccessbot?start=login_' + _sessionKey;
    var manual = document.getElementById('tg-manual-command');
    var manualText = document.getElementById('tg-manual-command-text');
    if (manual && manualText) {
        manualText.textContent = '/start login_' + _sessionKey;
        manual.style.display = 'grid';
    }

    var hint = document.getElementById('tg-polling-hint');
    if (hint) {
        hint.style.display = 'block';
        hint.textContent = 'Откройте Telegram и подтвердите вход. Если бот открылся впервые, нажмите Start. Если команда не подставилась, отправьте её вручную ниже.';
    }

    _tgPollTimer = setInterval(checkTgLoginStatus, 1000);
    checkTgLoginStatus();

    _tgTimeoutTimer = setTimeout(function() {
        if (_tgPollTimer) {
            clearInterval(_tgPollTimer);
            var hint = document.getElementById('tg-polling-hint');
            if (hint) hint.textContent = 'Время ожидания истекло. Нажмите «Войти через Telegram» ещё раз. Если бот не запускался раньше, сначала нажмите Start.';
        }
    }, 120000);

    var isMobile = /Android|iPhone|iPad|iPod/i.test(navigator.userAgent);
    if (isMobile) {
        window.location.href = botUrl;
    } else {
        window.open(botUrl, '_blank', 'noopener');
    }
}

function checkTgLoginStatus() {
    if (!_sessionKey) return;

    fetch('{{ route("auth.telegram-login.status.alias") }}?session_key=' + encodeURIComponent(_sessionKey), {
        headers: { 'Accept': 'application/json' },
        credentials: 'same-origin'
    })
    .then(r => r.json())
    .then(data => {
        if (data.authenticated && data.redirect) {
            clearInterval(_tgPollTimer);
            if (_tgTimeoutTimer) clearTimeout(_tgTimeoutTimer);
            window.location.href = data.redirect;
        }
    })
    .catch(function() {});
}

function copyAuthCommand(elementId, btn) {
    var el = document.getElementById(elementId);
    var text = el ? el.textContent.trim() : '';
    var done = function() {
        if (!btn) return;
        var old = btn.textContent;
        btn.textContent = 'Скопировано';
        setTimeout(function() { btn.textContent = old; }, 1800);
    };
    if (navigator.clipboard && window.isSecureContext) {
        navigator.clipboard.writeText(text).then(done).catch(function() {});
    } else {
        var ta = document.createElement('textarea');
        ta.value = text;
        ta.style.position = 'fixed';
        ta.style.left = '-9999px';
        document.body.appendChild(ta);
        ta.select();
        try { document.execCommand('copy'); done(); } catch (e) {}
        document.body.removeChild(ta);
    }
}

async function startWebAuthn(e) {
    e.preventDefault();
    var btn = document.getElementById('webauthn-btn');
    var errEl = document.getElementById('webauthn-error');
    errEl.style.display = 'none';
    btn.style.opacity = '.6';
    btn.style.pointerEvents = 'none';

    try {
        var challengeResponse = await fetch('{{ route("webauthn.auth.challenge") }}', {
            method: 'POST',
            headers: {'X-CSRF-TOKEN': '{{ csrf_token() }}', 'Accept': 'application/json'}
        });
        var challengeData = await challengeResponse.json();
        var options = {
            challenge: base64ToBuffer(challengeData.challenge),
            rpId: challengeData.rpId,
            timeout: challengeData.timeout,
            userVerification: challengeData.userVerification,
            allowCredentials: challengeData.allowCredentials.map(function(c) {
                return { type: c.type, id: base64ToBuffer(c.id) };
            }),
        };

        var assertion = await navigator.credentials.get({ publicKey: options });
        var verifyResponse = await fetch('{{ route("webauthn.auth.verify") }}', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'X-CSRF-TOKEN': '{{ csrf_token() }}',
                'Accept': 'application/json',
            },
            body: JSON.stringify({
                credential_id: bufferToBase64(assertion.rawId),
                authenticator_data: bufferToBase64(assertion.response.authenticatorData),
                client_data_json: bufferToBase64(assertion.response.clientDataJSON),
                signature: bufferToBase64(assertion.response.signature),
            }),
        });
        var result = await verifyResponse.json();
        if (result.ok && result.redirect) {
            window.location.href = result.redirect;
            return;
        }
        throw new Error(result.error || 'Не удалось войти по биометрии');
    } catch (error) {
        errEl.textContent = error.name === 'NotAllowedError'
            ? 'Вход отменён или биометрия недоступна'
            : (error.message || 'Ошибка входа по биометрии');
        errEl.style.display = 'block';
        btn.style.opacity = '1';
        btn.style.pointerEvents = '';
    }
}

function base64ToBuffer(base64) {
    var b = base64.replace(/-/g, '+').replace(/_/g, '/');
    var bin = atob(b);
    var buf = new Uint8Array(bin.length);
    for (var i = 0; i < bin.length; i++) buf[i] = bin.charCodeAt(i);
    return buf.buffer;
}

function bufferToBase64(buffer) {
    var bytes = new Uint8Array(buffer);
    var str = '';
    for (var i = 0; i < bytes.length; i++) str += String.fromCharCode(bytes[i]);
    return btoa(str).replace(/\+/g, '-').replace(/\//g, '_').replace(/=/g, '');
}
</script>
    </div>
</div>
</body>
</html>
