<!doctype html>
<html lang="ru">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Auralith | Новый пароль</title>
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
        <p class="eyebrow">Доступ подтверждён</p>
        <h1>Новый пароль</h1>

        @if($username)
            <p class="hint">Ваш логин: <strong>{{ $username }}</strong></p>
        @else
            <p class="hint">Задайте новый пароль для аккаунта.</p>
        @endif

        @if ($errors->any())
            <div class="alert">
                @foreach ($errors->all() as $error)
                    <p>{{ $error }}</p>
                @endforeach
            </div>
        @endif

        <form method="post" action="{{ route('account-recovery.reset.submit', ['token' => $token]) }}">
            @csrf
            <label>
                Новый пароль
                <input type="password" name="password" placeholder="Минимум 8 символов" required autocomplete="new-password">
            </label>
            <label>
                Повторите пароль
                <input type="password" name="password_confirmation" placeholder="Ещё раз новый пароль" required autocomplete="new-password">
            </label>
            <button type="submit">Сохранить пароль</button>
        </form>

        <p class="demo-text">Не получается восстановить? <a href="{{ $supportUrl }}" target="_blank" rel="noopener" style="color:#6b93c0">Написать в @auralith_support</a></p>
    </div>
</div>
</body>
</html>
