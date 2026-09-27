@php
    /** @var \App\Services\UserAdministration\UserDetails $details */
    $user = $details->user();
    $sub = $details->subscription();
    $plan = $details->plan();
    $access = $details->access();
    $devices = $details->devices();
    $fmt = fn ($value) => $value ? \Illuminate\Support\Carbon::parse($value)->format('Y-m-d H:i') : '—';
    $pct = $details->usedPercent();
@endphp
<div class="adm-user-details" data-user-details data-user-id="{{ $user['id'] ?? '' }}">
    @if($flash)
        <div class="adm-alert" data-details-flash>{{ $flash }}</div>
    @endif

    <section class="adm-ud-section">
        <h6 class="adm-ud-title">Пользователь</h6>
        <dl class="adm-ud-grid">
            <dt>User ID</dt>
            <dd><code>{{ $user['id'] ?? '' }}</code>
                <button type="button" class="adm-ud-copy" data-copy="{{ $user['id'] ?? '' }}" title="Копировать">⧉</button></dd>
            <dt>Email</dt><dd>{{ ($user['email'] ?? '') ?: '—' }}</dd>
            @if(!empty($user['username']))<dt>Username</dt><dd>{{ $user['username'] }}</dd>@endif
            <dt>Роль</dt><dd>{{ $user['role'] ?? 'user' }}</dd>
            <dt>Статус</dt>
            <dd><span class="node-chip {{ ($user['status'] ?? '') === 'active' && empty($user['disabled_at']) ? 'alive' : 'dead' }}"><span class="node-chip__dot"></span>{{ $user['status'] ?? '—' }}</span></dd>
        </dl>
    </section>

    <section class="adm-ud-section">
        <h6 class="adm-ud-title">Подписка</h6>
        @if($sub)
            <dl class="adm-ud-grid">
                <dt>Тариф</dt><dd data-plan-name>{{ $plan['name'] ?? '—' }}@if(!empty($plan['code'])) <span class="adm-muted">({{ $plan['code'] }})</span>@endif</dd>
                <dt>Статус</dt>
                <dd><span class="node-chip {{ ($sub['status'] ?? '') === 'active' ? 'alive' : 'dead' }}"><span class="node-chip__dot"></span><span data-subscription-status>{{ $sub['status'] ?? '—' }}</span></span></dd>
                <dt>Начало</dt><dd>{{ $fmt($sub['started_at'] ?? null) }}</dd>
                <dt>Окончание</dt><dd>{{ $fmt($sub['expires_at'] ?? null) }}</dd>
                <dt>Subscription URL</dt>
                <dd>
                    @if(!empty($access['subscription_url']))
                        <code data-subscription-url-masked>{{ $details->maskedSubscriptionUrl() }}</code>
                        <button type="button" class="adm-ud-copy" data-copy="{{ $access['subscription_url'] }}" title="Копировать ссылку">⧉</button>
                    @else
                        <span class="adm-muted">Не выдана — нет активного доступа</span>
                    @endif
                </dd>
                <dt>UUID / credential</dt>
                <dd>
                    @if(!empty($access['credential_id']))
                        <code data-credential-id>{{ $access['credential_id'] }}</code>
                        <button type="button" class="adm-ud-copy" data-copy="{{ $access['credential_id'] }}" title="Копировать">⧉</button>
                    @else
                        —
                    @endif
                </dd>
            </dl>
        @else
            <p class="adm-muted" data-no-subscription>No active subscription — активной подписки нет.</p>
            <form class="adm-form adm-ud-issue" data-issue-subscription action="/users/{{ $user['id'] ?? '' }}/subscription" method="post">
                @csrf
                <label class="adm-ud-label" for="adm-ud-plan">Тариф</label>
                <select id="adm-ud-plan" name="plan_id" class="adm-input" required>
                    <option value="">— выберите тариф —</option>
                    @foreach($plans as $option)
                        <option value="{{ $option['id'] }}" @disabled(!$option['is_active'])>{{ $option['label'] }}</option>
                    @endforeach
                </select>
                <button type="submit" class="adm-btn adm-btn-primary" data-issue-button>Выдать подписку</button>
            </form>
        @endif
    </section>

    @if($sub)
        <section class="adm-ud-section">
            <h6 class="adm-ud-title">Трафик</h6>
            <dl class="adm-ud-grid">
                <dt>Использовано</dt><dd data-traffic-used>{{ $details->trafficUsed() }}</dd>
                <dt>Лимит</dt><dd data-traffic-limit>{{ $details->trafficLimit() }}</dd>
                <dt>Остаток</dt><dd data-traffic-remaining>{{ $details->trafficRemaining() }}</dd>
            </dl>
            @if($pct !== null)
                <div class="adm-ud-progress" role="progressbar" aria-valuenow="{{ $pct }}" aria-valuemin="0" aria-valuemax="100">
                    <span style="width: {{ min(100, max(0, $pct)) }}%"></span>
                </div>
                <small class="adm-muted">{{ rtrim(rtrim(number_format($pct, 1, '.', ''), '0'), '.') }}% использовано</small>
            @endif
        </section>
    @endif

    <section class="adm-ud-section">
        <h6 class="adm-ud-title">Устройства</h6>
        <p><strong data-devices-count>Devices: {{ $details->devicesLabel() }}</strong></p>
        @if(!empty($devices['items']))
            <ul class="adm-ud-list">
                @foreach($devices['items'] as $device)
                    <li class="{{ ($device['status'] ?? '') === 'revoked' ? 'adm-muted' : '' }}">
                        {{ $device['name'] ?? 'Device' }} — {{ $device['platform'] ?? '—' }} — last seen {{ $fmt($device['last_seen_at'] ?? null) }}
                        @if(($device['status'] ?? '') === 'revoked') <small>(revoked)</small>@endif
                    </li>
                @endforeach
            </ul>
        @endif
    </section>

    <section class="adm-ud-section">
        <h6 class="adm-ud-title">Доступ</h6>
        <p>Активных grant: <strong data-active-grants>{{ $access['active_grants'] ?? 0 }}</strong>
            · Активных подключений: {{ $details->activeConnections() ?? 'нет данных от нод' }}</p>
        @if(!empty($access['grants']))
            <ul class="adm-ud-list">
                @foreach($access['grants'] as $grant)
                    <li>
                        <code>{{ substr($grant['id'] ?? '', 0, 8) }}…</code>
                        {{ $grant['node_code'] ?? '' }} · {{ $grant['protocol'] ?? '' }}
                        · <span class="node-chip {{ ($grant['status'] ?? '') === 'active' ? 'alive' : 'dead' }}"><span class="node-chip__dot"></span>{{ $grant['status'] ?? '' }}</span>
                        @if(!empty($grant['device_id']))<small class="adm-muted">(устройство)</small>@endif
                    </li>
                @endforeach
            </ul>
        @endif
    </section>

    <section class="adm-ud-section">
        <h6 class="adm-ud-title">Безопасность</h6>
        <button type="button" class="adm-btn" data-password-reset="/users/{{ $user['id'] ?? '' }}/password-reset">Отправить ссылку для восстановления пароля</button>
        <p class="adm-muted adm-ud-note" data-password-reset-result></p>
    </section>

    @if($sub)
        <section class="adm-ud-section">
            <h6 class="adm-ud-title">Действия</h6>
            <a class="adm-link" href="/subscriptions">Управление подпиской →</a>
        </section>
    @endif
</div>
