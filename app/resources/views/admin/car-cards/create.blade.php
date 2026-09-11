@extends('admin.layout')

@section('title', 'Создание авто QR')

@section('content')
<div style="margin-bottom:20px">
    <p style="margin:0;font-size:.72rem;color:var(--muted);letter-spacing:.1em;text-transform:uppercase">Auralith Auto</p>
    <h2 style="margin:4px 0 0;font-family:'Montserrat',sans-serif;font-size:1.5rem">Создать QR-карточку для авто</h2>
</div>

@if ($errors->any())
    <div style="border-radius:12px;padding:12px 16px;margin-bottom:16px;font-size:.88rem;border:1px solid rgba(248,113,113,.35);background:rgba(248,113,113,.08);color:#fecaca">
        {{ $errors->first() }}
    </div>
@endif

<div class="adm-card">
    <form method="post" action="{{ route('admin.car-cards.store') }}">
        @csrf

        <div style="display:grid;grid-template-columns:repeat(auto-fit,minmax(260px,1fr));gap:16px">
            <div>
                <label class="car-admin-label">Номер для звонка</label>
                <input class="adm-input" name="phone" value="{{ old('phone') }}" placeholder="+7 999 123 45 67" required>
            </div>
            <div>
                <label class="car-admin-label">WhatsApp</label>
                <input class="adm-input" name="whatsapp_phone" value="{{ old('whatsapp_phone') }}" placeholder="Оставить пустым, если тот же номер">
            </div>
            <div>
                <label class="car-admin-label">Telegram</label>
                <input class="adm-input" name="telegram" value="{{ old('telegram') }}" placeholder="username без @">
            </div>
            <div>
                <label class="car-admin-label">Почта</label>
                <input class="adm-input" type="email" name="email" value="{{ old('email') }}" placeholder="client@example.com">
            </div>
            <div>
                <label class="car-admin-label">Сообщение для WhatsApp и почты</label>
                <input class="adm-input" name="message" value="{{ old('message', 'Здравствуйте! Я по поводу вашей машины.') }}" maxlength="180">
                <p style="margin:6px 0 0;color:var(--muted);font-size:.78rem">Этот текст подставится человеку после нажатия WhatsApp или почты.</p>
            </div>
        </div>

        <div style="margin-top:22px;display:flex;gap:10px;flex-wrap:wrap">
            <button class="adm-btn" type="submit">Сгенерировать страницу и макет</button>
            <a class="adm-btn" href="{{ route('admin.car-cards.index') }}" style="text-decoration:none;background:rgba(138,148,166,.15);color:var(--text)">Назад</a>
        </div>
    </form>
</div>

<style>
    .car-admin-label {
        display:block;
        margin-bottom:6px;
        color:var(--muted);
        font-size:.78rem;
        font-weight:700;
        letter-spacing:.05em;
        text-transform:uppercase;
    }
</style>
@endsection
