@php
    /** @var \App\Services\UserAdministration\UserDetails $details */
    $userId = $details->userId();
    $user = $details->user();
    $base = '/users/'.$userId;
    $isSelf = ($viewer['id'] ?? '') === $userId;
    $canDelete = ($viewer['role'] ?? '') === 'superadmin' && ! $isSelf;
@endphp
<div class="adm-uc" data-user-details data-user-id="{{ $userId }}">
    @if($flash)
        <div class="adm-alert adm-uc-flash" data-details-flash role="status">{{ $flash }}</div>
    @endif
    <div class="adm-alert adm-uc-flash" data-card-notice role="status" hidden></div>

    <header class="adm-uc-head">
        <div class="adm-uc-avatar" aria-hidden="true">{{ $details->initial() }}</div>
        <div class="adm-uc-ident">
            <h3>{{ $details->displayName() }}</h3>
            <p>
                @if(!empty($user['username']))<span>{{ $user['username'] }}</span> · @endif
                <span>регистрация {{ $details->registeredAt() }}</span> ·
                <span>вход {{ $details->lastLogin() }}</span>
            </p>
            <div class="adm-uc-badges">
                <x-adm.badge :badge="$details->roleBadge()" />
                <x-adm.badge :badge="$details->statusBadge()" data-user-status />
            </div>
        </div>
    </header>

    <div class="adm-uc-toolbar">
        <button type="button" class="adm-btn adm-btn--sm" data-toggle-panel="profile">Редактировать</button>
        <button type="button" class="adm-btn adm-btn--sm" data-action="{{ $base }}/password-reset" data-confirm="Отправить пользователю ссылку для восстановления пароля?">Сбросить пароль</button>
        @if($details->isBlocked())
            <button type="button" class="adm-btn adm-btn--sm adm-btn--ok" data-action="{{ $base }}/unblock">Разблокировать</button>
        @elseif(! $isSelf)
            <button type="button" class="adm-btn adm-btn--sm adm-btn--warn" data-action="{{ $base }}/block" data-confirm="Заблокировать {{ $details->displayName() }}? Пользователь не сможет войти и подключиться.">Заблокировать</button>
        @endif
        @if($canDelete)
            <button type="button" class="adm-btn adm-btn--sm adm-btn--danger" data-action="{{ $base }}/remove" data-confirm="Удалить {{ $details->displayName() }} и все связанные данные? Это действие нельзя отменить.">Удалить</button>
        @endif
    </div>

    <form class="adm-uc-panel adm-form adm-form--wide" data-panel="profile" data-card-form action="{{ $base }}/profile" method="post" hidden>
        @csrf
        <div class="adm-form-row">
            <label>Email<input name="email" type="email" class="adm-input" value="{{ $user['email'] ?? '' }}" required></label>
            <label>Username <span class="adm-optional">необязательно</span><input name="username" class="adm-input" value="{{ $user['username'] ?? '' }}"></label>
        </div>
        <div class="adm-form-row">
            <label>Роль
                <select name="role" class="adm-input" @disabled($isSelf)>
                    @foreach(\App\View\Admin\StatusBadge::ROLES as $role)
                        <option value="{{ $role }}" @selected(($user['role'] ?? 'user') === $role)>{{ \App\View\Admin\StatusBadge::roleLabel($role) }}</option>
                    @endforeach
                </select>
                @if($isSelf)<input type="hidden" name="role" value="{{ $user['role'] ?? 'user' }}"><small class="adm-hint">Свою роль менять нельзя.</small>@endif
            </label>
            <label>Статус
                <select name="status" class="adm-input" @disabled($isSelf)>
                    <option value="active" @selected(! $details->isBlocked())>Активен</option>
                    <option value="disabled" @selected($details->isBlocked())>Заблокирован</option>
                </select>
                @if($isSelf)<input type="hidden" name="status" value="active">@endif
            </label>
        </div>
        <label>Новый пароль <span class="adm-optional">оставьте пустым, чтобы не менять</span>
            <input name="password" type="password" class="adm-input" minlength="10" autocomplete="new-password">
        </label>
        <div class="adm-form-actions">
            <button type="submit" class="adm-btn adm-btn-primary adm-btn--sm">Сохранить</button>
            <button type="button" class="adm-btn adm-btn--sm" data-toggle-panel="profile">Отмена</button>
        </div>
    </form>

    @include('users.details.subscription')
    @include('users.details.devices')
    @include('users.details.grants')

    <details class="adm-uc-tech">
        <summary>Технические данные</summary>
        <dl class="adm-uc-dl">
            <dt>User ID</dt>
            <dd><code>{{ $userId }}</code> <x-adm.copy :value="$userId" /></dd>
            @if($details->hasSubscription())
                <dt>Subscription ID</dt>
                <dd><code>{{ $details->subscriptionId() }}</code> <x-adm.copy :value="$details->subscriptionId()" /></dd>
            @endif
            @if($details->credentialId() !== '')
                <dt>UUID / credential</dt>
                <dd><code data-credential-id>{{ $details->credentialId() }}</code> <x-adm.copy :value="$details->credentialId()" /></dd>
            @endif
        </dl>
    </details>
</div>
