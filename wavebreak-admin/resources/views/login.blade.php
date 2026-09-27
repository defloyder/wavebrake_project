@extends('layout')

@section('title', 'Вход')
@section('body_class', 'adm-login-page')

@section('auth_content')
<div class="auth-wrap">
    <a href="/" class="brand" aria-label="WAVEBREAK Admin">
        <img src="{{ asset('images/wavebreak-logo.png') }}" class="wavebreak-logo" alt="">
        <span>Admin</span>
    </a>

    <section class="card">
        <p class="eyebrow">Панель управления</p>
        <h1>Вход в админку</h1>
        <p class="hint">Core: {{ ($health['status'] ?? '') === 'ok' ? 'работает' : 'недоступен' }}</p>

        @if($errors->any())
            <div class="alert">
                @foreach($errors->all() as $error)<p>{{ $error }}</p>@endforeach
            </div>
        @endif

        <form method="post" action="/login">
            @csrf
            <label>Email<input name="email" type="email" autocomplete="email" required></label>
            <label>Пароль<input name="password" type="password" autocomplete="current-password" required></label>
            <button type="submit">Войти</button>
        </form>
    </section>
</div>
@endsection

