@extends('layout')

@php
    $isRegister = ($mode ?? 'login') === 'register';
@endphp

@section('title', $isRegister ? 'WAVEBREAK - регистрация' : 'WAVEBREAK - вход')
@section('body_class', 'wb-shell')

@section('content')
<main class="wb-auth-page">
    <section class="wb-auth-story">
        <a href="/" class="wb-auth-brand" aria-label="WAVEBREAK">
            <img src="{{ asset('images/wavebreak-logo.png') }}" class="wb-logo" alt="">
            <span class="wb-brand-word"><span>WAVEBREAK</span><small>Access Platform</small></span>
        </a>
        <div>
            <p class="wb-kicker">{{ $isRegister ? 'Новый аккаунт' : 'С возвращением' }}</p>
            <h1>{{ $isRegister ? 'Создайте аккаунт и перейдите к подключению' : 'Войдите в кабинет WAVEBREAK' }}</h1>
            <p class="wb-lead">
                Здесь выбирается тариф, создается доступ к ноде и проверяется статус применения. Кабинет показывает данные из Core,
                поэтому действия пользователя связаны с реальным состоянием платформы.
            </p>
        </div>
        <div class="wb-proof-row">
            <div class="wb-proof"><strong>{{ $health['status'] ?? 'offline' }}</strong><span>Core API</span></div>
            <div class="wb-proof"><strong>{{ count($plans) }}</strong><span>доступных тарифа</span></div>
            <div class="wb-proof"><strong>JWT</strong><span>сессия через Core</span></div>
        </div>
    </section>

    <section class="wb-auth-panel">
        <div class="wb-form-card">
            <h2>{{ $isRegister ? 'Регистрация' : 'Вход' }}</h2>
            <p>{{ $isRegister ? 'Укажите email и пароль. После регистрации откроется личный кабинет.' : 'Введите email и пароль, чтобы продолжить работу с доступом.' }}</p>

            @if($errors->any())
                <div class="wb-alert">
                    @foreach($errors->all() as $error)<p>{{ $error }}</p>@endforeach
                </div>
            @endif

            <form method="post" action="{{ $isRegister ? '/register' : '/login' }}" class="wb-form">
                @csrf
                <label>Email
                    <input name="email" type="email" value="{{ old('email') }}" autocomplete="email" required>
                </label>
                <label>Password
                    <input name="password" type="password" minlength="{{ $isRegister ? '10' : '1' }}" autocomplete="{{ $isRegister ? 'new-password' : 'current-password' }}" required>
                </label>
                <button type="submit" class="wb-btn wb-btn--primary">{{ $isRegister ? 'Создать аккаунт' : 'Войти' }}</button>
            </form>

            <p class="wb-form-footer">
                @if($isRegister)
                    Уже есть аккаунт? <a href="/login">Войти</a>
                @else
                    Нет аккаунта? <a href="/register">Создать</a>
                @endif
            </p>
        </div>
    </section>
</main>
@endsection

