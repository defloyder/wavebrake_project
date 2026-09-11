@extends('layout')

@section('title', 'Admin sign in')
@section('body_class', 'adm-login-page')

@section('auth_content')
<div class="auth-wrap">
    <a href="/" class="brand" aria-label="WAVEBREAK Admin">
        <img src="{{ asset('images/wavebreak-logo.png') }}" class="wavebreak-logo" alt="">
        <span>Admin</span>
    </a>

    <section class="card">
        <p class="eyebrow">Operations</p>
        <h1>Admin Sign In</h1>
        <p class="hint">Core status: {{ $health['status'] ?? 'unavailable' }}</p>

        @if($errors->any())
            <div class="alert">
                @foreach($errors->all() as $error)<p>{{ $error }}</p>@endforeach
            </div>
        @endif

        <form method="post" action="/login">
            @csrf
            <label>Email<input name="email" type="email" autocomplete="email" required></label>
            <label>Password<input name="password" type="password" autocomplete="current-password" required></label>
            <button type="submit">Sign In</button>
        </form>
    </section>
</div>
@endsection

