@extends('layout')

@php
    $isRegister = ($mode ?? 'login') === 'register';
@endphp

@section('title', $isRegister ? 'WAVEBREAK - создать аккаунт' : 'WAVEBREAK - вход в кабинет')
@section('description', $isRegister ? 'Создайте аккаунт WAVEBREAK, чтобы выбрать тариф и подготовить персональное подключение.' : 'Войдите в кабинет WAVEBREAK для управления тарифом, устройствами и подключениями.')
@section('body_class', 'wb-shell')

@section('content')
<main class="wb-auth-page">
    <section class="wb-auth-story">
        <a href="/" class="wb-auth-brand" aria-label="WAVEBREAK">
            <img src="{{ asset('images/wavebreak-logo.png') }}" class="wb-logo" alt="">
            <span class="wb-brand-word"><span>WAVEBREAK</span><small>Secure Infrastructure</small></span>
        </a>
        <div>
            <p class="wb-kicker">{{ $isRegister ? 'Новый аккаунт' : 'Кабинет клиента' }}</p>
            <h1>{{ $isRegister ? 'Создайте аккаунт и перейдите к настройке доступа' : 'Войдите в кабинет WAVEBREAK' }}</h1>
            <p class="wb-lead">
                Здесь выбирают тариф, добавляют устройство и получают персональное подключение.
                Кабинет показывает актуальное состояние сервиса без лишних инструкций и ручной переписки.
            </p>
        </div>
        <div class="wb-proof-row">
            <div class="wb-proof"><strong>{{ $health['status'] ?? 'online' }}</strong><span>платформа</span></div>
            <div class="wb-proof"><strong>{{ count($plans) ?: 3 }}</strong><span>тарифа</span></div>
            <div class="wb-proof"><strong>24/7</strong><span>доступность</span></div>
        </div>
    </section>

    <section class="wb-auth-panel">
        <div class="wb-form-card">
            <h2>{{ $isRegister ? 'Регистрация' : 'Вход' }}</h2>
            <p>{{ $isRegister ? 'Укажите email и пароль. После регистрации откроется личный кабинет.' : 'Введите email и пароль, чтобы продолжить работу с сервисом.' }}</p>

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
                <label>Пароль
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
