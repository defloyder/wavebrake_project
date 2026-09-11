<!doctype html>
<html lang="ru">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Auralith | Регистрация</title>
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
        <p class="eyebrow">Создать аккаунт</p>
        <h1>Регистрация</h1>
        <p class="hint">Заполните данные для создания профиля.</p>

        <div class="auth-note">
            <strong>Telegram-вход подключается после регистрации</strong>
            <span>Сначала создайте аккаунт, затем запустите бота и привяжите Telegram в профиле. Без запуска бота Telegram-вход не сработает.</span>
        </div>

        @if ($errors->any())
            <div class="alert">
                @foreach ($errors->all() as $error)
                    <p>{{ $error }}</p>
                @endforeach
            </div>
        @endif

        <form method="post" action="{{ route('register.submit') }}">
            @csrf
            <label>
                Имя пользователя
                <input type="text" name="username" value="{{ old('username') }}" placeholder="Только буквы, цифры и _" required autofocus>
            </label>
            <label>
                Пароль
                <input type="password" name="password" placeholder="Минимум 8 символов" required>
            </label>
            <label>
                Повторите пароль
                <input type="password" name="password_confirmation" placeholder="Повторите пароль" required>
            </label>
            <button type="submit">Создать аккаунт</button>
        </form>

        <p class="demo-text">Уже есть аккаунт? <a href="{{ route('login') }}" style="color:#6b93c0">Войти</a></p>
    </div>
</div>
</body>
</html>
