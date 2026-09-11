<!doctype html>
<html lang="ru">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Auralith | Вход в приложение</title>
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
        <p class="eyebrow">Auralith {{ $client ?? 'App' }}</p>
        <h1>Вход в приложение</h1>

        @if(! empty($invalidLink))
            <div class="alert">
                Некорректная ссылка входа. Откройте вход из приложения Auralith.
            </div>
        @elseif(! empty($confirmed))
            <div class="alert" style="border-color:rgba(84,168,127,.5);background:rgba(63,128,92,.18)">
                Вход подтверждён. Вернитесь в приложение Auralith.
            </div>
        @else
            @if(! empty($coreError))
                <div class="alert">
                    Не удалось подтвердить вход в приложение. Попробуйте ещё раз.
                </div>
            @endif

            @if ($errors->any())
                <div class="alert">
                    @foreach ($errors->all() as $error)
                        <p>{{ $error }}</p>
                    @endforeach
                </div>
            @endif

            <div class="auth-note">
                <strong>Подтверждение входа</strong>
                <span>Войдите в аккаунт Auralith, чтобы приложение получило доступ к вашей подписке.</span>
            </div>

            @auth
                <form method="post" action="{{ route('app-login.submit', ['session_key' => $sessionKey, 'client' => strtolower($client ?? 'app')]) }}">
                    @csrf
                    <input type="hidden" name="session_key" value="{{ $sessionKey }}">
                    <input type="hidden" name="client" value="{{ strtolower($client ?? 'app') }}">
                    <button type="submit">Войти в приложение Auralith</button>
                </form>
                <p class="demo-text">Вы вошли как {{ auth()->user()->username }}.</p>
            @else
                <form method="post" action="{{ route('app-login.submit', ['session_key' => $sessionKey, 'client' => strtolower($client ?? 'app')]) }}">
                    @csrf
                    <input type="hidden" name="session_key" value="{{ $sessionKey }}">
                    <input type="hidden" name="client" value="{{ strtolower($client ?? 'app') }}">
                    <label>
                        Логин
                        <input type="text" name="login" value="{{ old('login') }}" placeholder="Ваш логин" required autofocus>
                    </label>
                    <label>
                        Пароль
                        <input type="password" name="password" placeholder="Ваш пароль" required>
                    </label>
                    <button type="submit">Войти в приложение Auralith</button>
                </form>
                <p class="demo-text">
                    <a href="{{ route('account-recovery.request') }}" style="color:#6b93c0">Забыли логин или пароль?</a>
                </p>
            @endauth
        @endif
    </div>
</div>
</body>
</html>
