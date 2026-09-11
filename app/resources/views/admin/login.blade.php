<!doctype html>
<html lang="ru">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Admin Login | Auralith</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/css/bootstrap.min.css" rel="stylesheet">
    <style>
        body {
            min-height: 100vh;
            background:
                radial-gradient(circle at 92% 4%, rgba(79, 126, 181, 0.32) 0%, transparent 32%),
                #0a0f18;
            color: #e6ebf3;
        }
        .login-wrap {
            width: min(460px, 92vw);
        }
        .card {
            background: linear-gradient(180deg, rgba(17, 26, 42, 0.95), rgba(11, 16, 27, 0.95));
            border: 1px solid rgba(138,148,166,.28);
            border-radius: 14px;
            box-shadow: 0 22px 50px rgba(2, 7, 16, 0.55);
        }
        h4 {
            color: #f2f6ff;
            font-weight: 700;
        }
        .form-label {
            color: #aeb8c8;
            margin-bottom: 0.45rem;
            font-weight: 500;
        }
        .form-control {
            background: #0d1421;
            color: #e6ebf3;
            border-color: rgba(138,148,166,.36);
            padding: 0.72rem 0.85rem;
        }
        .form-control:focus {
            background: #0d1421;
            color: #ffffff;
            border-color: #6b93c0;
            box-shadow: 0 0 0 .2rem rgba(79,126,181,.18);
        }
        .btn-primary {
            background: linear-gradient(135deg, #2d6fe6 0%, #1f5fd1 100%);
            border: 0;
            padding: 0.72rem 0.85rem;
            font-weight: 600;
        }
        .btn-primary:hover {
            filter: brightness(1.05);
        }
        .alert-danger {
            background: rgba(186, 93, 93, 0.2);
            border-color: rgba(186, 93, 93, 0.5);
            color: #ffd3d3;
        }
    </style>
</head>
<body class="d-flex align-items-center justify-content-center">
<div class="login-wrap">
    <div class="card p-4">
        <h4 class="mb-3">Вход в админ-панель</h4>
        @if ($errors->any())
            <div class="alert alert-danger">{{ $errors->first() }}</div>
        @endif
        <form method="post" action="{{ route('admin.login.submit') }}">
            @csrf
            <div class="mb-3">
                <label class="form-label">Username</label>
                <input class="form-control" name="username" value="{{ old('username') }}" required>
            </div>
            <div class="mb-3">
                <label class="form-label">Password</label>
                <input class="form-control" type="password" name="password" required>
            </div>
            <button class="btn btn-primary w-100">Войти в /admin</button>
        </form>

        <div id="webauthn-section" style="display:none;margin-top:16px">
            <div style="display:flex;align-items:center;gap:10px;margin-bottom:12px">
                <div style="flex:1;height:1px;background:rgba(138,148,166,.2)"></div>
                <span style="color:#6b7a8d;font-size:.8rem">или</span>
                <div style="flex:1;height:1px;background:rgba(138,148,166,.2)"></div>
            </div>
            <button type="button" id="webauthn-btn" onclick="startWebAuthn()" disabled style="width:100%;padding:.72rem;background:rgba(79,126,181,.12);border:1px solid rgba(79,126,181,.3);border-radius:8px;color:#6b93c0;font-size:.95rem;font-weight:600;cursor:pointer;display:flex;align-items:center;justify-content:center;gap:10px;transition:background .15s;opacity:.65">
                <svg viewBox="0 0 24 24" fill="none" width="20" height="20">
                    <path d="M12 2C9.24 2 7 4.24 7 7v1H5a2 2 0 00-2 2v10a2 2 0 002 2h14a2 2 0 002-2V10a2 2 0 00-2-2h-2V7c0-2.76-2.24-5-5-5zm0 2c1.66 0 3 1.34 3 5H9V7c0-1.66 1.34-3 3-3zm0 9a2 2 0 110 4 2 2 0 010-4z" fill="currentColor"/>
                </svg>
                Проверяем биометрию...
            </button>
            <div id="webauthn-error" style="display:none;margin-top:8px;color:#f87171;font-size:.82rem;text-align:center"></div>
        </div>
    </div>
</div>

<script>
// Check if WebAuthn is supported and credentials exist
(async function() {
    if (!window.PublicKeyCredential) return;
    const section = document.getElementById('webauthn-section');
    const btn = document.getElementById('webauthn-btn');
    section.style.display = 'block';
    try {
        const available = await PublicKeyCredential.isUserVerifyingPlatformAuthenticatorAvailable().catch(() => false);
        if (!available) {
            btn.textContent = 'Биометрия недоступна на этом устройстве';
            return;
        }
        const r = await fetch('{{ route("admin.webauthn.has.public") }}');
        const d = await r.json();
        if (d.has_credentials) {
            btn.disabled = false;
            btn.style.opacity = '1';
            btn.textContent = 'Войти по отпечатку / Face ID';
        } else {
            btn.textContent = 'Биометрия не настроена';
        }
    } catch(e) {
        btn.textContent = 'Биометрия временно недоступна';
    }
})();

async function startWebAuthn() {
    const btn = document.getElementById('webauthn-btn');
    const errEl = document.getElementById('webauthn-error');
    errEl.style.display = 'none';
    btn.disabled = true;
    btn.style.opacity = '.6';

    try {
        // Get challenge
        const cr = await fetch('{{ route("admin.webauthn.auth.challenge") }}', {
            method: 'POST',
            headers: {'X-CSRF-TOKEN': '{{ csrf_token() }}', 'Accept': 'application/json'}
        });
        const challengeData = await cr.json();

        // Build PublicKeyCredentialRequestOptions
        const options = {
            challenge: base64ToBuffer(challengeData.challenge),
            rpId: challengeData.rpId,
            timeout: challengeData.timeout,
            userVerification: challengeData.userVerification,
            allowCredentials: challengeData.allowCredentials.map(c => ({
                type: c.type,
                id: base64ToBuffer(c.id),
            })),
        };

        const assertion = await navigator.credentials.get({ publicKey: options });

        // Send to server
        const vr = await fetch('{{ route("admin.webauthn.auth.verify") }}', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'X-CSRF-TOKEN': '{{ csrf_token() }}',
                'Accept': 'application/json',
            },
            body: JSON.stringify({
                credential_id:      bufferToBase64(assertion.rawId),
                authenticator_data: bufferToBase64(assertion.response.authenticatorData),
                client_data_json:   bufferToBase64(assertion.response.clientDataJSON),
                signature:          bufferToBase64(assertion.response.signature),
            }),
        });

        const result = await vr.json();
        if (result.ok) {
            window.location.href = result.redirect;
        } else {
            throw new Error(result.error || 'Ошибка верификации');
        }
    } catch(e) {
        if (e.name === 'NotAllowedError') {
            errEl.textContent = 'Биометрия отменена или недоступна';
        } else {
            errEl.textContent = e.message || 'Ошибка биометрии';
        }
        errEl.style.display = 'block';
        btn.disabled = false;
        btn.style.opacity = '1';
    }
}

function base64ToBuffer(base64) {
    const b = base64.replace(/-/g,'+').replace(/_/g,'/');
    const bin = atob(b);
    const buf = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) buf[i] = bin.charCodeAt(i);
    return buf.buffer;
}
function bufferToBase64(buffer) {
    const bytes = new Uint8Array(buffer);
    let str = '';
    for (const b of bytes) str += String.fromCharCode(b);
    return btoa(str).replace(/\+/g,'-').replace(/\//g,'_').replace(/=/g,'');
}
</script>
