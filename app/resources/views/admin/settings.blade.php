@extends('admin.layout')

@section('title', 'Настройки')

@section('content')
<div style="margin-bottom:20px">
    <p style="margin:0;font-size:.72rem;color:var(--muted);letter-spacing:.1em;text-transform:uppercase">Auralith Admin</p>
    <h2 style="margin:4px 0 0;font-family:'Montserrat',sans-serif;font-size:1.5rem">Настройки</h2>
</div>

<div class="adm-settings-grid">
    <section class="adm-card adm-settings-card">
        <div class="adm-card-head adm-card-head--row">
            <div>
                <h6>Уведомления администратора</h6>
                <p>Пуши о заказах и состоянии системы будут приходить на это устройство для аккаунта {{ $admin->username }}.</p>
            </div>
            <label class="adm-switch" for="adminPushSwitch">
                <input id="adminPushSwitch" type="checkbox" @checked($pushSubscribed)>
                <span class="adm-switch__track"><span class="adm-switch__thumb"></span></span>
            </label>
        </div>
        <div class="adm-settings-status" id="adminPushStatus">
            {{ $pushSubscribed ? 'Уведомления включены' : 'Уведомления выключены' }}
        </div>
        <div class="adm-settings-actions adm-settings-actions--start">
            <button type="button" class="adm-btn adm-btn-sm" id="adminTestPush" @disabled(! $pushSubscribed)>Отправить тест</button>
        </div>
        <p class="adm-settings-note">После включения админка сможет отправлять уведомления даже при закрытой вкладке, если это разрешено браузером и системой.</p>
    </section>

    <section class="adm-card adm-settings-card">
        <div class="adm-card-head">
            <div>
                <h6>Отпечаток / Face ID</h6>
                <p>Быстрый вход в админку без пароля на этом устройстве для аккаунта {{ $admin->username }}.</p>
            </div>
        </div>
        <div class="adm-settings-status" id="adminWebAuthnStatus">
            @if($webauthnCredential)
                Включено: {{ $webauthnCredential->device_name ?: 'Устройство' }}
            @else
                Отпечаток или Face ID не добавлены
            @endif
        </div>
        <div class="adm-settings-actions adm-settings-actions--start">
            @if($webauthnCredential)
                <button type="button" class="adm-btn adm-btn-sm" id="adminWebAuthnReplace">Удалить и добавить заново</button>
                <button type="button" class="adm-btn adm-btn-sm adm-btn-ghost" id="adminWebAuthnDelete">Удалить</button>
            @else
                <button type="button" class="adm-btn adm-btn-sm" id="adminWebAuthnRegister">Добавить отпечаток / Face ID</button>
            @endif
        </div>
        <p class="adm-settings-note">Если браузер уже не показывает предложение настроить вход, добавьте или пересоздайте привязку здесь.</p>
    </section>

    <section class="adm-card adm-settings-card">
        <div class="adm-card-head">
            <div>
                <h6>Расписание системных уведомлений</h6>
                <p>Дайджест состояния отправляется автоматически каждый день. Можно задать до 5 времён.</p>
            </div>
        </div>
        <form method="POST" action="{{ route('admin.settings.digest-schedule.update') }}" class="adm-schedule-form">
            @csrf
            @method('PUT')
            @php
                $scheduleSlots = $digestSchedules->values();
            @endphp
            <div class="adm-schedule-row adm-schedule-row--editable">
                @for($i = 0; $i < 5; $i++)
                    @php
                        $schedule = $scheduleSlots->get($i);
                    @endphp
                    <label class="adm-schedule-slot {{ $schedule?->sentToday() ? 'is-sent' : '' }}">
                        <span>
                            {{ $schedule ? ($schedule->sentToday() ? 'Сегодня отправлено' : 'Ожидает отправки') : 'Не используется' }}
                        </span>
                        <input type="time" name="times[]" value="{{ $schedule?->send_time }}">
                    </label>
                @endfor
            </div>
            <div class="adm-settings-actions">
                <button type="button" class="adm-btn adm-btn-sm adm-btn-ghost" id="adminSendDigestNow">Отправить сейчас</button>
                <button type="submit" class="adm-btn adm-btn-sm">Сохранить расписание</button>
            </div>
        </form>
    </section>
</div>
@endsection

@push('scripts')
<script>
window.ADMIN_SETTINGS = {
    vapidPublicKey: @json($vapidPublicKey),
    pushStatusUrl: @json(route('admin.settings.push.status')),
    pushSubscribeUrl: @json(route('admin.settings.push.subscribe')),
    pushUnsubscribeUrl: @json(route('admin.settings.push.unsubscribe')),
    pushTestUrl: @json(route('admin.settings.push.test')),
    digestSendNowUrl: @json(route('admin.settings.digest.send-now')),
    webauthnRegisterChallengeUrl: @json(route('admin.webauthn.register.challenge')),
    webauthnRegisterVerifyUrl: @json(route('admin.webauthn.register.verify')),
    webauthnDeleteUrl: @json($webauthnCredential ? route('admin.webauthn.delete', $webauthnCredential) : null),
    webauthnRegistered: @json((bool) $webauthnCredential),
    adminId: @json($admin->id),
    csrfToken: @json(csrf_token()),
    startUrl: @json($adminStartUrl),
};
</script>
<script src="{{ asset('js/admin-settings.js') }}?v={{ filemtime(public_path('js/admin-settings.js')) }}"></script>
@endpush
