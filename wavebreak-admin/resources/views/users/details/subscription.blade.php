@php
    /** @var \App\Services\UserAdministration\UserDetails $details */
    $subBase = $base.'/subscriptions/'.$details->subscriptionId();
@endphp
<section class="adm-uc-section">
    <h4 class="adm-uc-title">Подписка</h4>

    @if($details->hasSubscription())
        <div class="adm-uc-sub-head">
            <div class="adm-uc-plan">
                <strong data-plan-name>{{ $details->planName() }}</strong>
                <x-adm.badge :badge="$details->subscriptionBadge()" data-subscription-status />
            </div>
            <div class="adm-uc-period">
                {{ $details->startedAt() }} — {{ $details->expiresAt() }}
                @if($details->daysLeftLabel())<span class="adm-muted">· {{ $details->daysLeftLabel() }}</span>@endif
            </div>
        </div>

        <div class="adm-uc-stats">
            <div class="adm-uc-stat adm-uc-stat--wide">
                <span>Трафик</span>
                <strong><span data-traffic-used>{{ $details->trafficUsed() }}</span> <small>из <span data-traffic-limit>{{ $details->trafficLimit() }}</span></small></strong>
                <x-adm.progress :percent="$details->usedPercent()" />
                <small>↓ {{ $details->trafficDown() }} · ↑ {{ $details->trafficUp() }} · осталось <span data-traffic-remaining>{{ $details->trafficRemaining() }}</span></small>
            </div>
            <div class="adm-uc-stat">
                <span>Устройства</span>
                <strong data-devices-count>{{ $details->devicesLabel() }}</strong>
            </div>
            <div class="adm-uc-stat">
                <span>Подключения</span>
                <strong>{{ $details->activeConnections() ?? '—' }}</strong>
                @if($details->activeConnections() === null)<small>ноды не сообщают</small>@endif
            </div>
        </div>

        <div class="adm-uc-access">
            @if($details->needsAccess())
                <div class="adm-uc-warning" data-needs-access>
                    <div>
                        <strong>Ключ доступа не выдан</strong>
                        <p>Подписка есть, но ссылки подписки нет — подключиться по ней нельзя.</p>
                    </div>
                    @if($details->isSubscriptionActive())
                        <button type="button" class="adm-btn adm-btn-primary adm-btn--sm" data-action="{{ $base }}/access">Выдать доступ</button>
                    @else
                        <small class="adm-muted">Доступ выдаётся только для активной подписки.</small>
                    @endif
                </div>
            @else
                <span class="adm-uc-label">Ссылка подписки</span>
                <div class="adm-uc-url">
                    <code data-subscription-url-masked>{{ $details->maskedSubscriptionUrl() }}</code>
                    <x-adm.copy :value="$details->subscriptionUrl()" label="Копировать ссылку" />
                    <button type="button" class="adm-btn adm-btn--sm adm-btn--ghost" data-qr="{{ $details->subscriptionUrl() }}">QR-код</button>
                </div>
                <div class="adm-uc-qr" data-qr-target hidden></div>
            @endif
        </div>

        <div class="adm-uc-toolbar">
            <button type="button" class="adm-btn adm-btn--sm" data-toggle-panel="subscription">Изменить</button>
            <button type="button" class="adm-btn adm-btn--sm" data-action="{{ $subBase }}/reset-traffic" data-confirm="Сбросить счётчик трафика за текущий период?">Сбросить трафик</button>
            @unless($details->needsAccess())
                <button type="button" class="adm-btn adm-btn--sm" data-action="{{ $subBase }}/reissue" data-confirm="Перевыпустить ссылку? Старая ссылка сразу перестанет работать — пользователю нужно будет обновить подписку.">Перевыпустить ссылку</button>
            @endunless
            <button type="button" class="adm-btn adm-btn--sm adm-btn--danger" data-action="{{ $subBase }}/cancel" data-confirm="Отменить подписку? Доступ будет отозван немедленно.">Отменить подписку</button>
        </div>

        <form class="adm-uc-panel adm-form adm-form--wide" data-panel="subscription" data-card-form action="{{ $subBase }}/edit" method="post" hidden>
            @csrf
            <p class="adm-hint">Заполните только то, что нужно изменить.</p>
            <div class="adm-form-row">
                <label>Тариф
                    <select name="plan_id" class="adm-input">
                        <option value="">Не менять ({{ $details->planName() }})</option>
                        @foreach($plans as $option)
                            @if($option['id'] !== $details->planId())
                                <option value="{{ $option['id'] }}" @disabled(! $option['is_active'])>{{ $option['label'] }}</option>
                            @endif
                        @endforeach
                    </select>
                    <small class="adm-hint">Смена тарифа переносит его лимиты.</small>
                </label>
                <label>Статус
                    <select name="status" class="adm-input">
                        <option value="">Не менять ({{ $details->subscriptionBadge()->label }})</option>
                        @foreach(\App\View\Admin\StatusBadge::SUBSCRIPTION_STATUSES as $status)
                            <option value="{{ $status }}">{{ \App\View\Admin\StatusBadge::subscriptionLabel($status) }}</option>
                        @endforeach
                    </select>
                </label>
            </div>
            <div class="adm-form-row">
                <label>Действует до
                    <input name="expires_on" type="date" class="adm-input">
                    <small class="adm-hint">Сейчас: {{ $details->expiresAt() }}</small>
                </label>
                <label>Устройств
                    <input name="device_limit" type="number" min="1" max="100" class="adm-input" placeholder="{{ $details->deviceLimitInput() }}">
                    <small class="adm-hint">Сейчас: {{ $details->deviceLimitInput() ?: '—' }}</small>
                </label>
            </div>
            <div class="adm-form-row">
                <label>Лимит трафика, ГБ
                    <input name="traffic_limit_gb" type="number" step="0.01" min="0.01" class="adm-input" placeholder="{{ $details->trafficLimitInput() }}">
                    <small class="adm-hint">Сейчас: {{ $details->trafficLimit() }}</small>
                </label>
                <label class="adm-form-check adm-form-check--end"><input type="checkbox" name="traffic_reset_to_plan" value="1"> Вернуть лимит тарифа</label>
            </div>
            <div class="adm-form-actions">
                <button type="submit" class="adm-btn adm-btn-primary adm-btn--sm">Сохранить</button>
                <button type="button" class="adm-btn adm-btn--sm" data-toggle-panel="subscription">Отмена</button>
            </div>
        </form>
    @else
        <div class="adm-uc-empty" data-no-subscription>
            <strong>Нет активной подписки</strong>
            <p>Выберите тариф — подписка активируется сразу и получит ключ доступа.</p>
        </div>
        <form class="adm-form adm-form--wide adm-uc-issue" data-card-form data-confirm="Выдать выбранный тариф этому пользователю?" action="{{ $base }}/subscription" method="post">
            @csrf
            <label>Тариф
                <select name="plan_id" class="adm-input" required>
                    <option value="">— выберите тариф —</option>
                    @foreach($plans as $option)
                        <option value="{{ $option['id'] }}" @disabled(! $option['is_active'])>{{ $option['label'] }}</option>
                    @endforeach
                </select>
            </label>
            <div class="adm-form-actions">
                <button type="submit" class="adm-btn adm-btn-primary adm-btn--sm">Выдать подписку</button>
            </div>
        </form>
    @endif
</section>
