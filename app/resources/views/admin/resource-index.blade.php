@extends('admin.layout')

@section('title', $config['title'])

@section('content')
<div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:20px;flex-wrap:wrap;gap:10px">
    <div>
        <p style="margin:0;font-size:.72rem;color:var(--muted);letter-spacing:.1em;text-transform:uppercase">Auralith Admin</p>
        <h2 style="margin:4px 0 0;font-family:'Montserrat',sans-serif;font-size:1.5rem">{{ $config['title'] }}</h2>
    </div>
    @if($config['creatable'] ?? true)
        @if($resource === 'plans')
            <button type="button" class="adm-btn adm-btn-sm js-plan-create" data-plan-edit="plan-create">+ Добавить тариф</button>
        @else
            <a class="adm-btn adm-btn-sm" href="{{ route('admin.resource.create', $resource) }}" style="text-decoration:none">+ Добавить запись</a>
        @endif
    @endif
</div>

<div class="adm-card {{ in_array($resource, ['users', 'subscriptions', 'plans'], true) ? 'adm-users-card adm-people-resource-card' : '' }}" style="margin-bottom:16px">
    @php
        $sortable = array_values(array_unique(array_merge(['id'], $config['fields'], $config['sortable'] ?? [])));
        $currentSort = request('sort', 'id');
        $currentDir = request('dir', 'desc') === 'asc' ? 'asc' : 'desc';
        $fieldLabels = [
            'id' => 'Local ID',
            'core_user_id' => 'Core ID',
            'username' => 'Username',
            'name' => 'Имя',
            'telegram_id' => 'Telegram ID',
            'headline' => 'Описание',
            'duration_months' => 'Срок',
            'price_rub' => 'Цена',
            'is_highlighted' => 'Рекомендуемый',
        ];
        $sortUrl = function (string $column) use ($currentSort, $currentDir) {
            $nextDir = ($currentSort === $column && $currentDir === 'asc') ? 'desc' : 'asc';
            return request()->fullUrlWithQuery(['sort' => $column, 'dir' => $nextDir, 'page' => 1]);
        };
        $sortIcon = function (string $column) use ($currentSort, $currentDir) {
            if ($currentSort !== $column) return '↕';
            return $currentDir === 'asc' ? '↑' : '↓';
        };
    @endphp

    {{-- Search & Sort toolbar --}}
    <form id="search-form" method="GET" action="{{ route('admin.resource.index', $resource) }}"
          class="adm-toolbar">

        {{-- Search input --}}
        <input type="text" class="adm-input" name="q" id="search-input"
               value="{{ request('q') }}" placeholder="{{ $resource === 'users' ? 'Имя, username, Telegram или ID' : ($resource === 'subscriptions' ? 'ID пользователя, тарифа или статус' : 'Поиск...') }}"
               style="flex:1;min-width:160px;max-width:280px" autocomplete="off">

        {{-- Search field selector --}}
        @php $searchFields = $config['search_fields'] ?? $config['fields']; @endphp
        @if(count($searchFields) > 1)
        <select name="search_field" class="adm-input" style="width:auto;min-width:120px">
            <option value="all" {{ request('search_field','all') === 'all' ? 'selected' : '' }}>Все поля</option>
            @foreach($searchFields as $sf)
                <option value="{{ $sf }}" {{ request('search_field') === $sf ? 'selected' : '' }}>{{ $fieldLabels[$sf] ?? $sf }}</option>
            @endforeach
        </select>
        @endif

        <button type="submit" class="adm-btn adm-btn-sm">Найти</button>

        @if(request('q') || request('search_field') || request('sort') || request('dir'))
            <a href="{{ route('admin.resource.index', $resource) }}"
               class="adm-btn adm-btn-sm"
               style="background:rgba(138,148,166,.15);color:var(--muted);text-decoration:none">Сбросить</a>
        @endif
    </form>

    <script>
    (function() {
        var t;
        document.getElementById('search-input').addEventListener('input', function() {
            var value = this.value.trim();
            clearTimeout(t);
            if (value.length > 0 && value.length < 3) return;
            t = setTimeout(function() { document.getElementById('search-form').submit(); }, 1200);
        });
    })();
    </script>

    @if(in_array($resource, ['users', 'subscriptions'], true))
        <div class="adm-core-snapshot {{ $coreSnapshotError ? 'is-warning' : '' }}">
            <span class="adm-core-snapshot__dot"></span>
            <span>
                Источник данных: <strong>Core API</strong>.
                @if($coreSnapshotAt)
                    Локальный снимок обновлен {{ \Carbon\Carbon::parse($coreSnapshotAt)->diffForHumans() }}.
                @else
                    Время успешного обновления пока неизвестно.
                @endif
                @if($coreSnapshotError)
                    Последняя синхронизация завершилась с ошибкой.
                @endif
            </span>
        </div>
    @endif

    <div class="{{ in_array($resource, ['users', 'subscriptions', 'plans'], true) ? 'adm-users-table-wrap' : '' }}" style="overflow-x:auto">
        <table class="adm-table">
            @if($resource === 'users')
            <thead>
                <tr>
                    <th>
                        <a class="adm-sort-link {{ $currentSort === 'username' ? 'is-active' : '' }}" href="{{ $sortUrl('username') }}">
                            Пользователь <span>{{ $sortIcon('username') }}</span>
                        </a>
                    </th>
                    <th>
                        <a class="adm-sort-link {{ $currentSort === 'core_user_id' ? 'is-active' : '' }}" href="{{ $sortUrl('core_user_id') }}">
                            Идентификаторы <span>{{ $sortIcon('core_user_id') }}</span>
                        </a>
                    </th>
                    <th>Подписка</th>
                    <th>Связь</th>
                    <th>Trial</th>
                    <th></th>
                </tr>
            </thead>
            <tbody>
            @forelse($rows as $row)
                @php
                    $subscription = $row->latestSubscription;
                    $coreOverview = is_array($row->core_overview ?? null) ? $row->core_overview : null;
                    $hasActiveSubscription = $coreOverview !== null
                        ? (bool) ($coreOverview['is_active'] ?? false)
                        : (bool) ($row->has_active_subscription ?? false);
                    $subscriptionStatus = $coreOverview['status'] ?? $subscription?->status ?? 'none';
                    $subscriptionEndsAt = $coreOverview !== null
                        ? ($coreOverview['expires_at'] ?? null)
                        : $subscription?->ends_at;
                    if ($subscriptionEndsAt && ! $subscriptionEndsAt instanceof \Carbon\CarbonInterface) {
                        try { $subscriptionEndsAt = \Carbon\Carbon::parse($subscriptionEndsAt); } catch (\Throwable) { $subscriptionEndsAt = null; }
                    }
                    $subscriptionPlanName = $coreOverview['plan_name'] ?? $subscription?->plan?->name;
                    $statusLabels = [
                        'active' => 'Активна',
                        'trial' => 'Пробная',
                        'expiring_soon' => 'Истекает',
                        'expired' => 'Истекла',
                        'inactive' => 'Неактивна',
                        'pending' => 'Ожидает',
                        'none' => 'Нет подписки',
                    ];
                    $statusLabel = $hasActiveSubscription
                        ? ($statusLabels[$subscriptionStatus] ?? 'Активна')
                        : ($statusLabels[$subscriptionStatus] ?? 'Нет подписки');
                    $statusClass = $hasActiveSubscription ? 'is-active' : ($subscription ? 'is-expired' : 'is-none');
                    $syncIsStale = $coreOverview
                        ? false
                        : ($subscription?->last_sync_at
                            ? $subscription->last_sync_at->lt(now()->subMinutes(15))
                            : true);
                    $displayName = $row->name ?: ($row->username ?: 'Пользователь');
                    $initial = mb_strtoupper(mb_substr($displayName, 0, 1));
                @endphp
                <tr class="adm-user-row js-user-row" tabindex="0" role="button"
                    aria-label="Открыть карточку пользователя {{ $displayName }}"
                    data-user-template="user-card-{{ $row->id }}">
                    <td data-label="Пользователь">
                        <div class="adm-user-identity">
                            <span class="adm-user-avatar">{{ $initial }}</span>
                            <span>
                                <strong>{{ $displayName }}</strong>
                                <small>{{ $row->username ? '@'.$row->username : 'username не указан' }}</small>
                            </span>
                        </div>
                    </td>
                    <td data-label="Идентификаторы">
                        <div class="adm-user-ids">
                            <span>Core <strong>{{ $row->core_user_id ?: '—' }}</strong></span>
                            <span>Local {{ $row->id }}</span>
                        </div>
                    </td>
                    <td data-label="Подписка">
                        <div class="adm-subscription-summary">
                            <span class="adm-subscription-badge {{ $statusClass }}">{{ $statusLabel }}</span>
                            @if($subscription || $coreOverview)
                                <small>
                                    {{ $subscriptionPlanName ?: 'Тариф не определен' }}
                                    @if($subscriptionEndsAt)
                                        · до {{ $subscriptionEndsAt->format('d.m.Y') }}
                                    @elseif($hasActiveSubscription)
                                        · без срока
                                    @endif
                                </small>
                                <small class="{{ $syncIsStale ? 'is-stale' : '' }}">
                                    {{ $coreOverview ? 'Core проверен сейчас' : 'Core '.($subscription->last_sync_at ? $subscription->last_sync_at->diffForHumans() : 'не синхронизирован') }}
                                </small>
                            @else
                                <small>Доступ не выдавался</small>
                            @endif
                        </div>
                    </td>
                    <td data-label="Связь">
                        <div class="adm-user-contact">
                            <span>{{ $row->telegram_id ? 'Telegram подключен' : 'Telegram не подключен' }}</span>
                            <small>Web push: {{ (int) ($row->browser_push_subscriptions_count ?? 0) }}</small>
                        </div>
                    </td>
                    <td data-label="Trial">
                        <span class="adm-mini-state {{ $row->trial_used ? 'is-used' : 'is-available' }}">
                            {{ $row->trial_used ? 'Использован' : 'Доступен' }}
                        </span>
                    </td>
                    <td data-label="">
                        <button type="button" class="adm-user-open js-user-open" aria-label="Открыть карточку">
                            Открыть
                            <svg viewBox="0 0 24 24" fill="none" aria-hidden="true"><path d="m9 18 6-6-6-6" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/></svg>
                        </button>
                    </td>
                </tr>
            @empty
                <tr>
                    <td colspan="6" class="adm-empty-table">Пользователи не найдены</td>
                </tr>
            @endforelse
            </tbody>
            @elseif($resource === 'plans')
            <thead>
                <tr>
                    <th>
                        <a class="adm-sort-link {{ $currentSort === 'name' ? 'is-active' : '' }}" href="{{ $sortUrl('name') }}">
                            Тариф <span>{{ $sortIcon('name') }}</span>
                        </a>
                    </th>
                    <th>
                        <a class="adm-sort-link {{ $currentSort === 'duration_months' ? 'is-active' : '' }}" href="{{ $sortUrl('duration_months') }}">
                            Срок <span>{{ $sortIcon('duration_months') }}</span>
                        </a>
                    </th>
                    <th>
                        <a class="adm-sort-link {{ $currentSort === 'price_rub' ? 'is-active' : '' }}" href="{{ $sortUrl('price_rub') }}">
                            Цена <span>{{ $sortIcon('price_rub') }}</span>
                        </a>
                    </th>
                    <th>Преимущества</th>
                    <th>Использование</th>
                    <th></th>
                </tr>
            </thead>
            <tbody>
            @forelse($rows as $row)
                @php
                    $features = $row->featureList();
                    $monthsLabel = $row->duration_months === 1 ? 'месяц' : ($row->duration_months < 5 ? 'месяца' : 'месяцев');
                @endphp
                <tr class="adm-user-row adm-plan-row js-plan-row" tabindex="0" role="button"
                    aria-label="Открыть тариф {{ $row->name }}"
                    data-plan-template="plan-card-{{ $row->id }}">
                    <td data-label="Тариф">
                        <div class="adm-user-identity">
                            <span class="adm-user-avatar adm-plan-avatar">{{ mb_strtoupper(mb_substr($row->name, 0, 1)) }}</span>
                            <span>
                                <strong>{{ $row->name }}</strong>
                                <small>{{ $row->headline ?: 'Описание не указано' }}</small>
                            </span>
                        </div>
                    </td>
                    <td data-label="Срок">
                        <div class="adm-plan-value">
                            <strong>{{ $row->duration_months }}</strong>
                            <small>{{ $monthsLabel }}</small>
                        </div>
                    </td>
                    <td data-label="Цена">
                        <div class="adm-plan-price">
                            <strong>{{ number_format($row->price_rub, 0, '.', ' ') }} ₽</strong>
                            <small>{{ number_format($row->price_rub / max(1, $row->duration_months), 0, '.', ' ') }} ₽/мес</small>
                        </div>
                    </td>
                    <td data-label="Преимущества">
                        <div class="adm-plan-features-preview">
                            @forelse(array_slice($features, 0, 2) as $feature)
                                <span>{{ $feature }}</span>
                            @empty
                                <small>Не указаны</small>
                            @endforelse
                            @if(count($features) > 2)
                                <small>Ещё {{ count($features) - 2 }}</small>
                            @endif
                        </div>
                    </td>
                    <td data-label="Использование">
                        <div class="adm-subscription-summary">
                            <strong>{{ $row->subscriptions_count }}</strong>
                            <small>подписок</small>
                        </div>
                    </td>
                    <td data-label="">
                        <div class="adm-row-actions">
                            @if($row->is_highlighted)
                                <span class="adm-subscription-badge is-active">Рекомендуемый</span>
                            @endif
                            <button type="button" class="adm-user-open js-plan-open" aria-label="Открыть тариф">
                                Открыть
                                <svg viewBox="0 0 24 24" fill="none" aria-hidden="true"><path d="m9 18 6-6-6-6" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/></svg>
                            </button>
                            <button type="button" class="adm-icon-btn js-plan-edit"
                                data-plan-edit="plan-edit-{{ $row->id }}"
                                title="Изменить тариф" aria-label="Изменить тариф">
                                <svg viewBox="0 0 24 24" fill="none" width="15" height="15"><path d="M11 4H4a2 2 0 00-2 2v14a2 2 0 002 2h14a2 2 0 002-2v-7" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"/><path d="M18.5 2.5a2.121 2.121 0 013 3L12 15l-4 1 1-4 9.5-9.5z" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"/></svg>
                            </button>
                        </div>
                    </td>
                </tr>
            @empty
                <tr>
                    <td colspan="6" class="adm-empty-table">Тарифы не найдены</td>
                </tr>
            @endforelse
            </tbody>
            @elseif($resource === 'subscriptions')
            <thead>
                <tr>
                    <th>Пользователь</th>
                    <th>Тариф</th>
                    <th>
                        <a class="adm-sort-link {{ $currentSort === 'status' ? 'is-active' : '' }}" href="{{ $sortUrl('status') }}">
                            Статус <span>{{ $sortIcon('status') }}</span>
                        </a>
                    </th>
                    <th>
                        <a class="adm-sort-link {{ $currentSort === 'starts_at' ? 'is-active' : '' }}" href="{{ $sortUrl('starts_at') }}">
                            Период <span>{{ $sortIcon('starts_at') }}</span>
                        </a>
                    </th>
                    <th>Core sync</th>
                    <th></th>
                </tr>
            </thead>
            <tbody>
            @forelse($rows as $row)
                @php
                    $user = $row->user;
                    $coreOverview = is_array($row->core_overview ?? null) ? $row->core_overview : null;
                    $displayName = $user?->name ?: ($user?->username ?: 'Пользователь #'.$row->user_id);
                    $initial = mb_strtoupper(mb_substr($displayName, 0, 1));
                    $displayStatus = $coreOverview['status'] ?? $row->status;
                    $displayEndsAt = $coreOverview !== null ? ($coreOverview['expires_at'] ?? null) : $row->ends_at;
                    $displayStartsAt = $coreOverview !== null ? ($coreOverview['starts_at'] ?? null) : $row->starts_at;
                    if ($displayEndsAt && ! $displayEndsAt instanceof \Carbon\CarbonInterface) {
                        try { $displayEndsAt = \Carbon\Carbon::parse($displayEndsAt); } catch (\Throwable) { $displayEndsAt = null; }
                    }
                    if ($displayStartsAt && ! $displayStartsAt instanceof \Carbon\CarbonInterface) {
                        try { $displayStartsAt = \Carbon\Carbon::parse($displayStartsAt); } catch (\Throwable) { $displayStartsAt = null; }
                    }
                    $isActive = $coreOverview !== null
                        ? (bool) ($coreOverview['is_active'] ?? false)
                        : (in_array($row->status, ['active', 'trial', 'expiring_soon'], true)
                            && (!$row->ends_at || $row->ends_at->isFuture()));
                    $displayPlanName = $coreOverview['plan_name'] ?? $row->plan?->name;
                    $statusLabels = [
                        'active' => 'Активна',
                        'trial' => 'Пробная',
                        'expiring_soon' => 'Истекает',
                        'expired' => 'Истекла',
                        'inactive' => 'Неактивна',
                        'pending' => 'Ожидает',
                        'none' => 'Нет подписки',
                    ];
                    $statusLabel = $statusLabels[$displayStatus] ?? $displayStatus;
                    $statusClass = $isActive ? 'is-active' : 'is-expired';
                @endphp
                <tr class="adm-user-row adm-subscription-row js-subscription-row" tabindex="0" role="button"
                    aria-label="Открыть подписку пользователя {{ $displayName }}"
                    data-subscription-template="subscription-card-{{ $row->id }}">
                    <td data-label="Пользователь">
                        <div class="adm-user-identity">
                            <span class="adm-user-avatar">{{ $initial }}</span>
                            <span>
                                <strong>{{ $displayName }}</strong>
                                <small>{{ $user?->username ? '@'.$user->username : 'User ID '.$row->user_id }}</small>
                            </span>
                        </div>
                    </td>
                    <td data-label="Тариф">
                        <div class="adm-subscription-summary">
                            <strong>{{ $displayPlanName ?: ($isActive ? 'Тариф не определён' : 'Нет активной подписки') }}</strong>
                            <small>{{ $coreOverview ? 'Core overview' : 'Plan ID '.$row->plan_id }}</small>
                        </div>
                    </td>
                    <td data-label="Статус">
                        <span class="adm-subscription-badge {{ $statusClass }}">{{ $statusLabel }}</span>
                    </td>
                    <td data-label="Период">
                        <div class="adm-subscription-summary">
                            <strong>{{ $displayStartsAt?->format('d.m.Y H:i') ?: '—' }}</strong>
                            <small>
                                @if($displayEndsAt)
                                    до {{ $displayEndsAt->format('d.m.Y H:i') }}
                                @elseif($isActive)
                                    без срока
                                @else
                                    нет активного периода
                                @endif
                            </small>
                        </div>
                    </td>
                    <td data-label="Core sync">
                        <div class="adm-subscription-summary">
                            <strong>{{ $coreOverview ? 'проверено сейчас' : ($row->last_sync_at?->diffForHumans() ?: 'Нет данных') }}</strong>
                            <small>{{ $coreOverview ? \Carbon\Carbon::parse($coreOverview['checked_at'])->format('d.m.Y H:i') : ($row->last_sync_at?->format('d.m.Y H:i') ?: 'Не синхронизирована') }}</small>
                        </div>
                    </td>
                    <td data-label="">
                        <div class="adm-row-actions">
                            <button type="button" class="adm-user-open js-subscription-open" aria-label="Открыть карточку подписки">
                                Открыть
                                <svg viewBox="0 0 24 24" fill="none" aria-hidden="true"><path d="m9 18 6-6-6-6" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/></svg>
                            </button>
                            <button type="button" class="adm-icon-btn js-subscription-edit"
                                data-subscription-edit="subscription-edit-{{ $row->id }}"
                                title="Изменить подписку" aria-label="Изменить подписку">
                                <svg viewBox="0 0 24 24" fill="none" width="15" height="15"><path d="M11 4H4a2 2 0 00-2 2v14a2 2 0 002 2h14a2 2 0 002-2v-7" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"/><path d="M18.5 2.5a2.121 2.121 0 013 3L12 15l-4 1 1-4 9.5-9.5z" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"/></svg>
                            </button>
                        </div>
                    </td>
                </tr>
            @empty
                <tr>
                    <td colspan="6" class="adm-empty-table">Подписки не найдены</td>
                </tr>
            @endforelse
            </tbody>
            @else
            <thead>
                <tr>
                    <th>
                        <a class="adm-sort-link {{ $currentSort === 'id' ? 'is-active' : '' }}" href="{{ $sortUrl('id') }}">
                            ID <span>{{ $sortIcon('id') }}</span>
                        </a>
                    </th>
                    @foreach($config['fields'] as $field)
                        <th>
                            @if(in_array($field, $sortable, true))
                                <a class="adm-sort-link {{ $currentSort === $field ? 'is-active' : '' }}" href="{{ $sortUrl($field) }}">
                                    {{ $field }} <span>{{ $sortIcon($field) }}</span>
                                </a>
                            @else
                                {{ $field }}
                            @endif
                        </th>
                    @endforeach
                    <th>Действия</th>
                </tr>
            </thead>
            <tbody>
            @forelse($rows as $row)
                <tr>
                    <td data-label="ID" style="color:var(--muted);font-size:.8rem">
                        {{ $resource === 'subscriptions' ? ($row->user_id ?? $row->id) : $row->id }}
                    </td>
                    @foreach($config['fields'] as $field)
                        @php
                            $displayFields = $config['display_fields'] ?? [];
                            $value = $row->{$field};
                            if (isset($displayFields[$field])) {
                                $df = $displayFields[$field];
                                if (isset($df['relation']) && isset($df['column'])) {
                                    $value = optional($row->{$df['relation']})->{$df['column']} ?? $value;
                                } elseif (isset($df['map'])) {
                                    $value = $df['map'][$value] ?? $value;
                                }
                            }
                            $dateFields = ['starts_at', 'ends_at', 'created_at', 'updated_at', 'last_sync_at', 'paid_at', 'failed_at', 'expires_at'];
                            $booleanFields = ['is_active', 'is_highlighted', 'trial_used', 'hidden_on_dashboard'];
                            $months = ['01'=>'янв','02'=>'фев','03'=>'мар','04'=>'апр','05'=>'май','06'=>'июн','07'=>'июл','08'=>'авг','09'=>'сен','10'=>'окт','11'=>'ноя','12'=>'дек'];
                            $isDate = in_array($field, $dateFields) && $value;
                            if ($isDate) {
                                try {
                                    $dt = \Carbon\Carbon::parse($value);
                                    $value = $dt->format('d') . ' ' . ($months[$dt->format('m')] ?? $dt->format('m')) . ' ' . $dt->format('Y') . ' ' . $dt->format('H:i');
                                } catch (\Throwable $e) {}
                            }
                        @endphp
                        <td data-label="{{ $field }}"
                            class="{{ $isDate ? 'date-cell' : '' }}"
                            style="max-width:200px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap">
                            @if(in_array($field, $booleanFields, true))
                                <span class="pill {{ $value ? 'pill-active' : 'pill-inactive' }}">{{ $value ? 'ДА' : 'НЕТ' }}</span>
                            @elseif($field === 'status' && !is_array($value))
                                <span class="pill pill-{{ $value }}">{{ strtoupper($value) }}</span>
                            @else
                                {{ is_array($value) ? json_encode($value) : $value }}
                            @endif
                        </td>
                    @endforeach
                    <td data-label="Действия">
                        <div style="display:flex;gap:4px;align-items:center">
                            @if($config['editable'] ?? true)
                                {{-- Edit --}}
                                <a href="{{ route('admin.resource.edit', [$resource, $row->id]) }}"
                                   class="adm-icon-btn" title="Изменить">
                                    <svg viewBox="0 0 24 24" fill="none" width="15" height="15"><path d="M11 4H4a2 2 0 00-2 2v14a2 2 0 002 2h14a2 2 0 002-2v-7" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"/><path d="M18.5 2.5a2.121 2.121 0 013 3L12 15l-4 1 1-4 9.5-9.5z" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"/></svg>
                                </a>
                                @if($resource === 'users')
                                    <a href="{{ route('admin.resource.show', [$resource, $row->id]) }}#user-traffic"
                                       class="adm-action-chip"
                                       title="Трафик пользователя и устройств">
                                        Трафик
                                    </a>
                                @endif
                            @else
                                {{-- View --}}
                                <a href="{{ route('admin.resource.show', [$resource, $row->id]) }}"
                                   class="adm-icon-btn" title="Просмотреть">
                                    <svg viewBox="0 0 24 24" fill="none" width="15" height="15"><path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z" stroke="currentColor" stroke-width="1.7"/><circle cx="12" cy="12" r="3" stroke="currentColor" stroke-width="1.7"/></svg>
                                </a>
                            @endif

                            @if($resource === 'users' && ((int) ($row->browser_push_subscriptions_count ?? 0) > 0 || !empty($row->telegram_id)))
                            {{-- Send notification --}}
                            <button type="button" class="adm-icon-btn adm-icon-btn--tg" title="Отправить уведомление"
                                onclick="admSendNotify({{ $row->id }}, '{{ addslashes($row->username ?? $row->name) }}', '{{ $row->telegram_id ?: '' }}', {{ (int) ($row->browser_push_subscriptions_count ?? 0) }})">
                                <svg viewBox="0 0 24 24" fill="none" width="17" height="17"><path d="M18 8A6 6 0 0 0 6 8c0 7-3 9-3 9h18s-3-2-3-9" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"/><path d="M13.73 21a2 2 0 0 1-3.46 0" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"/></svg>
                            </button>
                            @endif

                            @if($resource === 'users' && ! ($row->has_active_subscription ?? false))
                                @if(! empty($row->telegram_id))
                                    <a href="{{ route('admin.resource.create', ['resource' => 'subscriptions', 'user_id' => $row->id]) }}"
                                       class="adm-icon-btn"
                                       title="Выдать подписку">
                                         <svg viewBox="0 0 24 24" fill="none" width="17" height="17"><path d="M12 5v14M5 12h14" stroke="currentColor" stroke-width="1.9" stroke-linecap="round"/><path d="M4 4h16v16H4z" stroke="currentColor" stroke-width="1.5" opacity=".55" rx="3"/></svg>
                                    </a>
                                @else
                                    <span class="adm-icon-btn is-disabled"
                                          title="Нельзя выдать подписку: у пользователя не привязан Telegram">
                                         <svg viewBox="0 0 24 24" fill="none" width="17" height="17"><path d="M12 5v14M5 12h14" stroke="currentColor" stroke-width="1.9" stroke-linecap="round"/><path d="M4 4h16v16H4z" stroke="currentColor" stroke-width="1.5" opacity=".55" rx="3"/></svg>
                                    </span>
                                @endif
                            @endif

                            @if($resource === 'users')
                            <button type="button"
                                class="adm-icon-btn js-recovery-link"
                                title="Создать ссылку восстановления доступа"
                                data-user-id="{{ $row->id }}"
                                data-username="{{ e($row->username ?? $row->name ?? 'Пользователь') }}">
                                <svg viewBox="0 0 24 24" fill="none" width="17" height="17"><path d="M15 7a4 4 0 1 1-3.4 6.1L5 19.7 3 17.7l6.6-6.6A4 4 0 0 1 15 7Z" stroke="currentColor" stroke-width="1.7" stroke-linejoin="round"/><path d="M14 11h.01" stroke="currentColor" stroke-width="2.4" stroke-linecap="round"/></svg>
                            </button>
                            @endif

                            @if($config['deletable'] ?? true)
                            {{-- Delete --}}
                            <form method="post" action="{{ route('admin.resource.destroy', [$resource, $row->id]) }}"
                                  onsubmit="return confirm('Удалить запись #{{ $row->id }}?')" style="margin:0">
                                @csrf
                                @method('DELETE')
                                <input type="hidden" name="return_to" value="{{ request()->fullUrl() }}">
                                <button type="submit" class="adm-icon-btn adm-icon-btn--danger" title="Удалить">
                                    <svg viewBox="0 0 24 24" fill="none" width="15" height="15"><polyline points="3 6 5 6 21 6" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"/><path d="M19 6l-1 14H6L5 6M10 11v6M14 11v6M9 6V4h6v2" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"/></svg>
                                </button>
                            </form>
                            @endif
                        </div>
                    </td>
                </tr>
            @empty
                <tr>
                    <td colspan="{{ count($config['fields']) + 2 }}" style="text-align:center;color:var(--muted);padding:32px">
                        Записей не найдено
                    </td>
                </tr>
            @endforelse
            </tbody>
            @endif
        </table>
    </div>

    @if($resource === 'users')
        @foreach($rows as $row)
            @php
                $subscription = $row->latestSubscription;
                $coreOverview = is_array($row->core_overview ?? null) ? $row->core_overview : null;
                $hasActiveSubscription = $coreOverview !== null
                    ? (bool) ($coreOverview['is_active'] ?? false)
                    : (bool) ($row->has_active_subscription ?? false);
                $subscriptionStatus = $coreOverview['status'] ?? $subscription?->status;
                $subscriptionEndsAt = $coreOverview !== null
                    ? ($coreOverview['expires_at'] ?? null)
                    : $subscription?->ends_at;
                if ($subscriptionEndsAt && ! $subscriptionEndsAt instanceof \Carbon\CarbonInterface) {
                    try { $subscriptionEndsAt = \Carbon\Carbon::parse($subscriptionEndsAt); } catch (\Throwable) { $subscriptionEndsAt = null; }
                }
                $subscriptionStartsAt = $coreOverview['starts_at'] ?? $subscription?->starts_at;
                if ($subscriptionStartsAt && ! $subscriptionStartsAt instanceof \Carbon\CarbonInterface) {
                    try { $subscriptionStartsAt = \Carbon\Carbon::parse($subscriptionStartsAt); } catch (\Throwable) { $subscriptionStartsAt = null; }
                }
                $subscriptionPlanName = $coreOverview['plan_name'] ?? $subscription?->plan?->name;
                $displayName = $row->name ?: ($row->username ?: 'Пользователь');
                $initial = mb_strtoupper(mb_substr($displayName, 0, 1));
                $statusLabel = match ($subscriptionStatus) {
                    'active' => 'Активна',
                    'trial' => 'Пробная',
                    'expiring_soon' => 'Истекает',
                    'expired' => 'Истекла',
                    'inactive' => 'Неактивна',
                    'pending' => 'Ожидает',
                    default => $hasActiveSubscription ? 'Активна' : 'Нет подписки',
                };
            @endphp
            <template id="user-card-{{ $row->id }}">
                <div class="adm-user-card">
                    <div class="adm-user-card__head">
                        <div class="adm-user-identity adm-user-identity--large">
                            <span class="adm-user-avatar">{{ $initial }}</span>
                            <span>
                                <strong>{{ $displayName }}</strong>
                                <small>{{ $row->username ? '@'.$row->username : 'username не указан' }}</small>
                            </span>
                        </div>
                        <button type="button" class="adm-modal-close" onclick="closeUserModal()" aria-label="Закрыть">
                            <svg viewBox="0 0 24 24" fill="none"><path d="M18 6 6 18M6 6l12 12" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/></svg>
                        </button>
                    </div>

                    <div class="adm-user-card__status {{ $hasActiveSubscription ? 'is-active' : 'is-inactive' }}">
                        <span>{{ $statusLabel }}</span>
                        <small>
                            @if($coreOverview)
                                Проверено напрямую через Core API
                            @elseif($subscription?->last_sync_at)
                                Проверено по снимку Core {{ $subscription->last_sync_at->diffForHumans() }}
                            @else
                                Активная подписка в локальном снимке не найдена
                            @endif
                        </small>
                    </div>

                    <div class="adm-user-card__grid">
                        <div><span>Core user ID</span><strong>{{ $row->core_user_id ?: '—' }}</strong></div>
                        <div><span>Local ID</span><strong>{{ $row->id }}</strong></div>
                        <div><span>Telegram ID</span><strong>{{ $row->telegram_id ?: 'Не подключен' }}</strong></div>
                        <div><span>Browser push</span><strong>{{ (int) ($row->browser_push_subscriptions_count ?? 0) }}</strong></div>
                        <div><span>Пробный период</span><strong>{{ $row->trial_used ? 'Использован' : 'Доступен' }}</strong></div>
                        <div><span>Профиль обновлен</span><strong>{{ $row->updated_at?->format('d.m.Y H:i') ?: '—' }}</strong></div>
                    </div>

                    <section class="adm-user-subscription">
                        <div class="adm-user-subscription__head">
                            <div>
                                <span>Подписка</span>
                                <strong>{{ $subscriptionPlanName ?: $statusLabel }}</strong>
                            </div>
                            <span class="adm-subscription-badge {{ $hasActiveSubscription ? 'is-active' : ($subscription ? 'is-expired' : 'is-none') }}">{{ $statusLabel }}</span>
                        </div>
                        @if($subscription || $coreOverview)
                            <div class="adm-user-subscription__details">
                                <span>Начало <strong>{{ $subscriptionStartsAt?->format('d.m.Y H:i') ?: '—' }}</strong></span>
                                <span>Окончание <strong>{{ $subscriptionEndsAt?->format('d.m.Y H:i') ?: ($hasActiveSubscription ? 'Без срока' : '—') }}</strong></span>
                                <span>Нода <strong>{{ $subscription?->node?->name ?: 'Не назначена' }}</strong></span>
                                <span>Трафик <strong>{{ $subscription ? number_format((float) $subscription->traffic_used_gb, 2, '.', ' ').' ГБ' : '—' }}</strong></span>
                            </div>
                        @else
                            <p>В локальном снимке Core нет подписки для этого пользователя.</p>
                        @endif
                    </section>

                    <div class="adm-user-card__actions">
                        <a href="{{ route('admin.resource.show', ['users', $row->id]) }}" class="adm-btn adm-btn-sm">Диагностика и трафик</a>
                        @if((int) ($row->browser_push_subscriptions_count ?? 0) > 0 || $row->telegram_id)
                            <button type="button" class="adm-btn adm-btn-sm adm-btn-ghost js-user-notify"
                                data-user-id="{{ $row->id }}"
                                data-username="{{ $displayName }}"
                                data-telegram-id="{{ $row->telegram_id ?: '' }}"
                                data-push-count="{{ (int) ($row->browser_push_subscriptions_count ?? 0) }}">
                                Уведомить
                            </button>
                        @endif
                        <button type="button" class="adm-btn adm-btn-sm adm-btn-ghost js-user-recovery"
                            data-user-id="{{ $row->id }}"
                            data-username="{{ $displayName }}">
                            Восстановить доступ
                        </button>
                        @if(!$hasActiveSubscription && $row->telegram_id)
                            <a href="{{ route('admin.resource.create', ['resource' => 'subscriptions', 'user_id' => $row->id]) }}" class="adm-btn adm-btn-sm">
                                Выдать подписку
                            </a>
                        @elseif(!$hasActiveSubscription)
                            <span class="adm-action-note">Для выдачи подписки нужен Telegram ID</span>
                        @endif
                    </div>
                </div>
            </template>
        @endforeach
    @endif

    @if($resource === 'plans')
        <template id="plan-create">
            <form method="POST" action="{{ route('admin.resource.store', 'plans') }}" class="adm-plan-edit-form"
                data-loader-title="Создаём тариф" data-loader-detail="Сохраняем параметры нового тарифа.">
                @csrf
                <div class="adm-user-card__head">
                    <div>
                        <p class="adm-modal-eyebrow">Новый тариф</p>
                        <h3>Добавить тарифный план</h3>
                    </div>
                    <button type="button" class="adm-modal-close" data-plan-close aria-label="Закрыть">
                        <svg viewBox="0 0 24 24" fill="none"><path d="M18 6 6 18M6 6l12 12" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/></svg>
                    </button>
                </div>
                <div class="adm-modal-form-grid">
                    <label>
                        Название
                        <input class="adm-input" name="name" required placeholder="Например, Standard">
                    </label>
                    <label>
                        Срок, месяцев
                        <input class="adm-input" type="number" name="duration_months" min="1" required placeholder="3">
                    </label>
                    <label>
                        Цена, ₽
                        <input class="adm-input" type="number" name="price_rub" min="0" required placeholder="449">
                    </label>
                    <label class="adm-modal-field--wide">
                        Короткое описание
                        <input class="adm-input" name="headline" placeholder="Для регулярного использования">
                    </label>
                    <label class="adm-modal-field--wide">
                        Преимущества тарифа
                        <textarea class="adm-input" name="features" rows="5" placeholder="Каждое преимущество с новой строки"></textarea>
                        <small>Это и есть прежнее поле Features — список того, что входит в тариф.</small>
                    </label>
                    <label class="adm-plan-highlight-toggle">
                        <input type="checkbox" name="is_highlighted" value="1">
                        <span>
                            <strong>Рекомендуемый тариф</strong>
                            <small>Выделить тариф на публичной странице.</small>
                        </span>
                    </label>
                </div>
                <div class="adm-modal-actions">
                    <button type="button" class="adm-btn adm-btn-sm adm-btn-ghost" data-plan-close>Отмена</button>
                    <button type="submit" class="adm-btn adm-btn-sm">Создать тариф</button>
                </div>
            </form>
        </template>

        @foreach($rows as $row)
            @php
                $features = $row->featureList();
                $monthsLabel = $row->duration_months === 1 ? 'месяц' : ($row->duration_months < 5 ? 'месяца' : 'месяцев');
            @endphp
            <template id="plan-card-{{ $row->id }}">
                <div class="adm-user-card">
                    <div class="adm-user-card__head">
                        <div class="adm-user-identity adm-user-identity--large">
                            <span class="adm-user-avatar adm-plan-avatar">{{ mb_strtoupper(mb_substr($row->name, 0, 1)) }}</span>
                            <span>
                                <strong>{{ $row->name }}</strong>
                                <small>{{ $row->headline ?: 'Описание не указано' }}</small>
                            </span>
                        </div>
                        <button type="button" class="adm-modal-close" data-plan-close aria-label="Закрыть">
                            <svg viewBox="0 0 24 24" fill="none"><path d="M18 6 6 18M6 6l12 12" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/></svg>
                        </button>
                    </div>

                    <div class="adm-plan-hero {{ $row->is_highlighted ? 'is-highlighted' : '' }}">
                        <div>
                            <span>Стоимость</span>
                            <strong>{{ number_format($row->price_rub, 0, '.', ' ') }} ₽</strong>
                            <small>{{ number_format($row->price_rub / max(1, $row->duration_months), 0, '.', ' ') }} ₽ в месяц</small>
                        </div>
                        <div>
                            <span>Срок</span>
                            <strong>{{ $row->duration_months }}</strong>
                            <small>{{ $monthsLabel }}</small>
                        </div>
                        <div>
                            <span>Использование</span>
                            <strong>{{ $row->subscriptions_count }}</strong>
                            <small>подписок</small>
                        </div>
                    </div>

                    <section class="adm-plan-features-card">
                        <div class="adm-user-subscription__head">
                            <div>
                                <span>Преимущества тарифа</span>
                                <strong>Что входит</strong>
                            </div>
                            @if($row->is_highlighted)
                                <span class="adm-subscription-badge is-active">Рекомендуемый</span>
                            @endif
                        </div>
                        <ul>
                            @forelse($features as $feature)
                                <li>{{ $feature }}</li>
                            @empty
                                <li class="is-empty">Преимущества пока не указаны.</li>
                            @endforelse
                        </ul>
                    </section>

                    <div class="adm-user-card__actions">
                        <button type="button" class="adm-btn adm-btn-sm js-plan-edit" data-plan-edit="plan-edit-{{ $row->id }}">Изменить тариф</button>
                        <form method="POST" action="{{ route('admin.resource.destroy', ['plans', $row->id]) }}"
                            onsubmit="return confirm('Удалить тариф {{ addslashes($row->name) }}? Связанные данные могут быть затронуты.')">
                            @csrf
                            @method('DELETE')
                            <button type="submit" class="adm-btn adm-btn-sm adm-btn-danger">Удалить</button>
                        </form>
                    </div>
                </div>
            </template>

            <template id="plan-edit-{{ $row->id }}">
                <form method="POST" action="{{ route('admin.resource.update', ['plans', $row->id]) }}" class="adm-plan-edit-form"
                    data-loader-title="Обновляем тариф" data-loader-detail="Сохраняем цену, срок и преимущества.">
                    @csrf
                    @method('PUT')
                    <div class="adm-user-card__head">
                        <div>
                            <p class="adm-modal-eyebrow">Тариф #{{ $row->id }}</p>
                            <h3>{{ $row->name }}</h3>
                        </div>
                        <button type="button" class="adm-modal-close" data-plan-close aria-label="Закрыть">
                            <svg viewBox="0 0 24 24" fill="none"><path d="M18 6 6 18M6 6l12 12" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/></svg>
                        </button>
                    </div>
                    <div class="adm-modal-form-grid">
                        <label>
                            Название
                            <input class="adm-input" name="name" value="{{ $row->name }}" required>
                        </label>
                        <label>
                            Срок, месяцев
                            <input class="adm-input" type="number" name="duration_months" min="1" value="{{ $row->duration_months }}" required>
                        </label>
                        <label>
                            Цена, ₽
                            <input class="adm-input" type="number" name="price_rub" min="0" value="{{ $row->price_rub }}" required>
                        </label>
                        <label class="adm-modal-field--wide">
                            Короткое описание
                            <input class="adm-input" name="headline" value="{{ $row->headline }}">
                        </label>
                        <label class="adm-modal-field--wide">
                            Преимущества тарифа
                            <textarea class="adm-input" name="features" rows="5" placeholder="Каждое преимущество с новой строки">{{ implode("\n", $features) }}</textarea>
                            <small>Каждая строка станет отдельным пунктом на странице тарифа.</small>
                        </label>
                        <label class="adm-plan-highlight-toggle">
                            <input type="checkbox" name="is_highlighted" value="1" @checked($row->is_highlighted)>
                            <span>
                                <strong>Рекомендуемый тариф</strong>
                                <small>Выделить тариф на публичной странице.</small>
                            </span>
                        </label>
                    </div>
                    <div class="adm-modal-actions">
                        <button type="button" class="adm-btn adm-btn-sm adm-btn-ghost" data-plan-close>Отмена</button>
                        <button type="submit" class="adm-btn adm-btn-sm">Сохранить</button>
                    </div>
                </form>
            </template>
        @endforeach
    @endif

    @if($resource === 'subscriptions')
        @foreach($rows as $row)
            @php
                $user = $row->user;
                $coreOverview = is_array($row->core_overview ?? null) ? $row->core_overview : null;
                $displayName = $user?->name ?: ($user?->username ?: 'Пользователь #'.$row->user_id);
                $initial = mb_strtoupper(mb_substr($displayName, 0, 1));
                $displayStatus = $coreOverview['status'] ?? $row->status;
                $displayEndsAt = $coreOverview !== null ? ($coreOverview['expires_at'] ?? null) : $row->ends_at;
                $displayStartsAt = $coreOverview !== null ? ($coreOverview['starts_at'] ?? null) : $row->starts_at;
                if ($displayEndsAt && ! $displayEndsAt instanceof \Carbon\CarbonInterface) {
                    try { $displayEndsAt = \Carbon\Carbon::parse($displayEndsAt); } catch (\Throwable) { $displayEndsAt = null; }
                }
                if ($displayStartsAt && ! $displayStartsAt instanceof \Carbon\CarbonInterface) {
                    try { $displayStartsAt = \Carbon\Carbon::parse($displayStartsAt); } catch (\Throwable) { $displayStartsAt = null; }
                }
                $isActive = $coreOverview !== null
                    ? (bool) ($coreOverview['is_active'] ?? false)
                    : (in_array($row->status, ['active', 'trial', 'expiring_soon'], true)
                        && (!$row->ends_at || $row->ends_at->isFuture()));
                $displayPlanName = $coreOverview['plan_name'] ?? $row->plan?->name;
                $statusLabel = match ($displayStatus) {
                    'active' => 'Активна',
                    'trial' => 'Пробная',
                    'expiring_soon' => 'Истекает',
                    'expired' => 'Истекла',
                    'inactive' => 'Неактивна',
                    'pending' => 'Ожидает',
                    default => $displayStatus,
                };
            @endphp
            <template id="subscription-card-{{ $row->id }}">
                <div class="adm-user-card">
                    <div class="adm-user-card__head">
                        <div class="adm-user-identity adm-user-identity--large">
                            <span class="adm-user-avatar">{{ $initial }}</span>
                            <span>
                                <strong>{{ $displayName }}</strong>
                                <small>{{ $user?->username ? '@'.$user->username : 'username не указан' }}</small>
                            </span>
                        </div>
                        <button type="button" class="adm-modal-close" data-subscription-close aria-label="Закрыть">
                            <svg viewBox="0 0 24 24" fill="none"><path d="M18 6 6 18M6 6l12 12" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/></svg>
                        </button>
                    </div>

                    <div class="adm-user-card__status {{ $isActive ? 'is-active' : 'is-inactive' }}">
                        <span>{{ $statusLabel }}</span>
                        <small>{{ $coreOverview ? 'Проверено напрямую через Core API' : 'Снимок Core: '.($row->last_sync_at?->diffForHumans() ?: 'ещё не синхронизирован') }}</small>
                    </div>

                    <div class="adm-user-card__grid">
                        <div><span>Core user ID</span><strong>{{ $user?->core_user_id ?: '—' }}</strong></div>
                        <div><span>Local user ID</span><strong>{{ $row->user_id }}</strong></div>
                        <div><span>Subscription ID</span><strong>{{ $row->id }}</strong></div>
                        <div><span>Telegram ID</span><strong>{{ $user?->telegram_id ?: 'Не подключен' }}</strong></div>
                        <div><span>Browser push</span><strong>{{ (int) ($user?->browser_push_subscriptions_count ?? 0) }}</strong></div>
                        <div><span>Trial</span><strong>{{ $user?->trial_used ? 'Использован' : 'Доступен' }}</strong></div>
                    </div>

                    <section class="adm-user-subscription">
                        <div class="adm-user-subscription__head">
                            <div>
                                <span>Подписка</span>
                                <strong>{{ $displayPlanName ?: ($isActive ? 'Тариф не определён' : 'Нет активной подписки') }}</strong>
                            </div>
                            <span class="adm-subscription-badge {{ $isActive ? 'is-active' : 'is-expired' }}">{{ $statusLabel }}</span>
                        </div>
                        <div class="adm-user-subscription__details">
                            <span>Начало <strong>{{ $displayStartsAt?->format('d.m.Y H:i') ?: '—' }}</strong></span>
                            <span>Окончание <strong>{{ $displayEndsAt?->format('d.m.Y H:i') ?: ($isActive ? 'Без срока' : 'Нет активного периода') }}</strong></span>
                            <span>Нода <strong>{{ $row->node?->name ?: 'Не назначена' }}</strong></span>
                            <span>Трафик <strong>{{ number_format((float) $row->traffic_used_gb, 2, '.', ' ') }} ГБ</strong></span>
                        </div>
                    </section>

                    <div class="adm-user-card__actions">
                        <a href="{{ route('admin.resource.show', ['users', $row->user_id]) }}" class="adm-btn adm-btn-sm">Пользователь и диагностика</a>
                        <button type="button" class="adm-btn adm-btn-sm adm-btn-ghost js-subscription-edit"
                            data-subscription-edit="subscription-edit-{{ $row->id }}">Изменить подписку</button>
                    </div>
                </div>
            </template>

            <template id="subscription-edit-{{ $row->id }}">
                <form method="POST" action="{{ route('admin.resource.update', ['subscriptions', $row->id]) }}" class="adm-subscription-edit-form"
                    data-loader-title="Обновляем подписку" data-loader-detail="Сохраняем изменения и синхронизируем их с Core API.">
                    @csrf
                    @method('PUT')
                    <div class="adm-user-card__head">
                        <div>
                            <p class="adm-modal-eyebrow">Подписка #{{ $row->id }}</p>
                            <h3>{{ $displayName }}</h3>
                        </div>
                        <button type="button" class="adm-modal-close" data-subscription-close aria-label="Закрыть">
                            <svg viewBox="0 0 24 24" fill="none"><path d="M18 6 6 18M6 6l12 12" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/></svg>
                        </button>
                    </div>

                    <input type="hidden" name="user_id" value="{{ $row->user_id }}">
                    <div class="adm-modal-form-grid">
                        <label>
                            Тариф
                            <select name="plan_id" class="adm-input" required>
                                @foreach($subscriptionPlans as $plan)
                                    <option value="{{ $plan->id }}" @selected($row->plan_id === $plan->id)>{{ $plan->name }} · ₽{{ number_format($plan->price_rub, 0, '.', ' ') }}</option>
                                @endforeach
                            </select>
                        </label>
                        <label>
                            Статус
                            <select name="status" class="adm-input" required>
                                @if(!in_array($row->status, ['active', 'trial', 'expiring_soon'], true))
                                    <option value="" selected disabled>Текущий: {{ $statusLabel }} — выберите новый</option>
                                @endif
                                @foreach(['active' => 'Активна', 'trial' => 'Пробная', 'expiring_soon' => 'Истекает'] as $value => $label)
                                    <option value="{{ $value }}" @selected($row->status === $value)>{{ $label }}</option>
                                @endforeach
                            </select>
                        </label>
                        <label>
                            Начало
                            <input type="datetime-local" name="starts_at" class="adm-input" value="{{ $row->starts_at?->format('Y-m-d\TH:i') }}">
                        </label>
                        <label>
                            Окончание
                            <input type="datetime-local" name="ends_at" class="adm-input" value="{{ $row->ends_at?->format('Y-m-d\TH:i') }}">
                        </label>
                    </div>
                    <div class="adm-modal-actions">
                        <button type="button" class="adm-btn adm-btn-sm adm-btn-ghost" data-subscription-close>Отмена</button>
                        <button type="submit" class="adm-btn adm-btn-sm">Сохранить</button>
                    </div>
                </form>
            </template>
        @endforeach
    @endif

    @if($rows->hasPages())
    @php
        $currentPage = $rows->currentPage();
        $lastPage = $rows->lastPage();
        $pageWindow = collect(range(max(1, $currentPage - 2), min($lastPage, $currentPage + 2)));
        $pageWindow = $pageWindow
            ->merge([1, $lastPage])
            ->merge($currentPage <= 4 ? range(1, min(5, $lastPage)) : [])
            ->merge($currentPage >= $lastPage - 3 ? range(max(1, $lastPage - 4), $lastPage) : [])
            ->unique()
            ->sort()
            ->values();
        $previousRenderedPage = null;
    @endphp
    <div class="adm-pagination">
        @if($rows->onFirstPage())
            <span class="adm-page-link is-disabled">‹</span>
        @else
            <a href="{{ $rows->previousPageUrl() }}" class="adm-page-link">‹</a>
        @endif

        @foreach($pageWindow as $page)
            @if($previousRenderedPage !== null && $page > $previousRenderedPage + 1)
                <span class="adm-page-gap">…</span>
            @endif
            @if($page == $rows->currentPage())
                <span class="adm-page-link is-active">{{ $page }}</span>
            @else
                <a href="{{ $rows->url($page) }}" class="adm-page-link">{{ $page }}</a>
            @endif
            @php $previousRenderedPage = $page; @endphp
        @endforeach

        @if($rows->hasMorePages())
            <a href="{{ $rows->nextPageUrl() }}" class="adm-page-link">›</a>
        @else
            <span class="adm-page-link is-disabled">›</span>
        @endif

        <span class="adm-page-total">
            {{ $rows->firstItem() }}–{{ $rows->lastItem() }} из {{ $rows->total() }}
        </span>
    </div>
    @endif
</div>

@if($resource === 'users')
{{-- User Details Modal --}}
<div id="user-modal" class="adm-modal" hidden>
    <div class="adm-modal-dialog adm-modal-dialog--user" role="dialog" aria-modal="true" aria-label="Карточка пользователя">
        <div id="user-modal-content"></div>
    </div>
</div>

{{-- Recovery Link Modal --}}
<div id="recovery-modal" class="adm-modal" hidden>
    <div class="adm-modal-dialog">
        <h3 style="margin:0 0 4px;font-size:1rem">Восстановление доступа</h3>
        <p id="recovery-username" style="margin:0 0 16px;color:var(--muted);font-size:.85rem"></p>
        <textarea id="recovery-message" rows="6" readonly
            style="width:100%;background:rgba(255,255,255,.05);border:1px solid var(--line);border-radius:10px;padding:10px 12px;color:var(--text);font-family:inherit;font-size:.88rem;resize:vertical;box-sizing:border-box"></textarea>
        <div id="recovery-error" style="display:none;color:#f87171;font-size:.82rem;margin-top:8px"></div>
        <div style="display:flex;gap:8px;margin-top:14px;justify-content:flex-end;flex-wrap:wrap">
            <button onclick="copyRecoveryMessage(this)" class="adm-btn adm-btn-sm" style="background:rgba(79,126,181,.18);color:#c6dcf5">Копировать</button>
            <button onclick="closeRecoveryModal()" class="adm-btn adm-btn-sm" style="background:rgba(138,148,166,.15);color:var(--muted)">Закрыть</button>
        </div>
    </div>
</div>

{{-- Notification Modal --}}
<div id="notify-modal" class="adm-modal" hidden>
    <div class="adm-modal-dialog adm-modal-dialog--compact">
        <h3 style="margin:0 0 4px;font-size:1rem">Уведомление пользователю</h3>
        <p id="notify-username" style="margin:0 0 16px;color:var(--muted);font-size:.85rem"></p>
        <input id="notify-title" type="text" placeholder="Заголовок (необязательно)"
            style="width:100%;background:rgba(255,255,255,.05);border:1px solid var(--line);border-radius:10px;padding:8px 12px;color:var(--text);font-family:inherit;font-size:.88rem;box-sizing:border-box;margin-bottom:10px">
        <textarea id="notify-text" rows="5" placeholder="Текст сообщения"
            style="width:100%;background:rgba(255,255,255,.05);border:1px solid var(--line);border-radius:10px;padding:10px 12px;color:var(--text);font-family:inherit;font-size:.88rem;resize:vertical;box-sizing:border-box"></textarea>
        <div id="notify-error" style="display:none;color:#f87171;font-size:.82rem;margin-top:8px"></div>
        <div style="display:flex;gap:8px;margin-top:14px;justify-content:flex-end">
            <button onclick="closeNotifyModal()" style="padding:8px 16px;background:transparent;border:1px solid var(--line);border-radius:8px;color:var(--muted);cursor:pointer;font-family:inherit">Отмена</button>
            <button onclick="submitNotify()" id="notify-submit" style="padding:8px 18px;background:linear-gradient(135deg,#4f7eb5,#6b93c0);border:0;border-radius:8px;color:#fff;font-weight:600;cursor:pointer;font-family:inherit">Отправить</button>
        </div>
    </div>
</div>

<script>
var _notifyUserId = null;
var _recoveryEndpointTemplate = @json(route('admin.users.recovery-link', ['user' => '__USER_ID__'], false));

function openUserModal(templateId) {
    var modal = document.getElementById('user-modal');
    var content = document.getElementById('user-modal-content');
    var template = document.getElementById(templateId);
    if (!modal || !content || !template) return;
    content.replaceChildren(template.content.cloneNode(true));
    modal.hidden = false;
    document.body.classList.add('adm-modal-open');
    content.querySelector('.js-user-notify')?.addEventListener('click', function() {
        var button = this;
        closeUserModal();
        admSendNotify(
            Number(button.dataset.userId),
            button.dataset.username || 'Пользователь',
            button.dataset.telegramId || '',
            Number(button.dataset.pushCount || 0)
        );
    });
    content.querySelector('.js-user-recovery')?.addEventListener('click', function() {
        var button = this;
        closeUserModal();
        admCreateRecoveryLink(Number(button.dataset.userId), button.dataset.username || 'Пользователь');
    });
    modal.querySelector('.adm-modal-close')?.focus();
}

function closeUserModal() {
    var modal = document.getElementById('user-modal');
    if (!modal) return;
    modal.hidden = true;
    document.body.classList.remove('adm-modal-open');
}

function admCreateRecoveryLink(userId, username) {
    var modal = document.getElementById('recovery-modal');
    var errEl = document.getElementById('recovery-error');
    var messageEl = document.getElementById('recovery-message');
    var usernameEl = document.getElementById('recovery-username');

    if (!modal || !errEl || !messageEl || !usernameEl) {
        alert('Не удалось открыть окно восстановления. Обновите страницу и попробуйте ещё раз.');
        return;
    }

    errEl.style.display = 'none';
    errEl.textContent = '';
    messageEl.value = '';
    usernameEl.textContent = (username || 'Пользователь') + ' · создаём ссылку...';
    modal.hidden = false;
    document.body.classList.add('adm-modal-open');

    if (window.admShowLoader) {
        window.admShowLoader('Создаём ссылку восстановления', 'Генерируем одноразовую ссылку смены пароля.');
    }

    fetch(_recoveryEndpointTemplate.replace('__USER_ID__', encodeURIComponent(userId)), {
        method: 'POST',
        headers: {
            'X-CSRF-TOKEN': document.querySelector('meta[name="csrf-token"]') ? document.querySelector('meta[name="csrf-token"]').content : '{{ csrf_token() }}',
            'Accept': 'application/json',
        },
    })
    .then(function(r) {
        return r.text().then(function(text) {
            var data = {};
            try {
                data = text ? JSON.parse(text) : {};
            } catch (e) {
                data = { error: text || 'Сервер вернул не JSON-ответ' };
            }
            return { ok: r.ok, status: r.status, data: data };
        });
    })
    .then(function(result) {
        if (!result.ok || !result.data.ok) {
            throw new Error(result.data.error || result.data.message || ('Не удалось создать ссылку. HTTP ' + result.status));
        }
        usernameEl.textContent = (username || 'Пользователь') + ' · ссылка действует ' + result.data.expires_in_minutes + ' минут';
        messageEl.value = result.data.message;
    })
    .catch(function(e) {
        errEl.textContent = e.message || 'Ошибка создания ссылки';
        errEl.style.display = 'block';
    })
    .finally(function() {
        if (window.admHideLoader) {
            window.admHideLoader();
        }
    });
}

function closeRecoveryModal() {
    document.getElementById('recovery-modal').hidden = true;
    document.body.classList.remove('adm-modal-open');
}

function copyRecoveryMessage(btn) {
    var text = document.getElementById('recovery-message').value.trim();
    var done = function() {
        var old = btn.textContent;
        btn.textContent = 'Скопировано';
        setTimeout(function() { btn.textContent = old; }, 1800);
    };
    if (navigator.clipboard && window.isSecureContext) {
        navigator.clipboard.writeText(text).then(done).catch(function() {});
        return;
    }
    var ta = document.createElement('textarea');
    ta.value = text;
    ta.style.position = 'fixed';
    ta.style.left = '-9999px';
    document.body.appendChild(ta);
    ta.select();
    try { document.execCommand('copy'); done(); } catch (e) {}
    document.body.removeChild(ta);
}

document.querySelectorAll('.js-recovery-link').forEach(function(button) {
    button.addEventListener('click', function() {
        admCreateRecoveryLink(this.dataset.userId, this.dataset.username || 'Пользователь');
    });
});

function admSendNotify(userId, username, telegramId, pushCount) {
    _notifyUserId = userId;
    var parts = [username];
    if (telegramId) parts.push('TG: ' + telegramId);
    if (pushCount) parts.push('браузерных устройств: ' + pushCount);
    document.getElementById('notify-username').textContent = parts.join(' · ');
    document.getElementById('notify-title').value = '';
    document.getElementById('notify-text').value = '';
    document.getElementById('notify-error').style.display = 'none';
    document.getElementById('notify-modal').hidden = false;
    document.body.classList.add('adm-modal-open');
}

function closeNotifyModal() {
    document.getElementById('notify-modal').hidden = true;
    document.body.classList.remove('adm-modal-open');
}

function submitNotify() {
    var text = document.getElementById('notify-text').value.trim();
    var errEl = document.getElementById('notify-error');
    var btn = document.getElementById('notify-submit');
    if (!text) { errEl.textContent = 'Введите текст сообщения'; errEl.style.display = 'block'; return; }

    btn.disabled = true;
    btn.textContent = 'Отправка...';
    errEl.style.display = 'none';
    window.admShowLoader?.('Отправляем уведомление', 'Доставляем персональное сообщение пользователю.');

    fetch('/{{ config("app.admin_path") }}/users/' + _notifyUserId + '/notify', {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json',
            'X-CSRF-TOKEN': document.querySelector('meta[name="csrf-token"]') ? document.querySelector('meta[name="csrf-token"]').content : '{{ csrf_token() }}',
            'Accept': 'application/json',
        },
        body: JSON.stringify({ message: text, title: document.getElementById('notify-title').value.trim() || null }),
    })
    .then(r => r.json())
    .then(data => {
        if (data.ok) {
            closeNotifyModal();
            // Show success toast
            var toast = document.createElement('div');
            toast.style.cssText = 'position:fixed;bottom:24px;right:24px;z-index:9999;background:rgba(74,222,128,.15);border:1px solid rgba(74,222,128,.4);border-radius:12px;padding:14px 20px;color:#4ade80;font-size:.88rem;font-weight:500;display:flex;align-items:center;gap:10px;box-shadow:0 8px 24px rgba(0,0,0,.3)';
            toast.innerHTML = '<svg viewBox="0 0 24 24" fill="none" width="18" height="18"><path d="M20 6L9 17l-5-5" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg> Уведомление отправлено';
            document.body.appendChild(toast);
            setTimeout(function() { toast.style.opacity='0'; toast.style.transition='opacity .4s'; setTimeout(function(){ toast.remove(); }, 400); }, 3000);
        } else {
            errEl.textContent = data.error || 'Ошибка отправки';
            errEl.style.display = 'block';
        }
    })
    .catch(() => { errEl.textContent = 'Ошибка сети'; errEl.style.display = 'block'; })
    .finally(() => { btn.disabled = false; btn.textContent = 'Отправить'; window.admHideLoader?.(); });
}

document.getElementById('notify-modal').addEventListener('click', function(e) {
    if (e.target === this) closeNotifyModal();
});
document.getElementById('recovery-modal').addEventListener('click', function(e) {
    if (e.target === this) closeRecoveryModal();
});
document.getElementById('user-modal').addEventListener('click', function(e) {
    if (e.target === this) closeUserModal();
});
document.querySelectorAll('.js-user-row').forEach(function(row) {
    row.addEventListener('click', function(e) {
        if (e.target.closest('a, button, form')) return;
        openUserModal(this.dataset.userTemplate);
    });
    row.addEventListener('keydown', function(e) {
        if (e.key === 'Enter' || e.key === ' ') {
            e.preventDefault();
            openUserModal(this.dataset.userTemplate);
        }
    });
    row.querySelector('.js-user-open')?.addEventListener('click', function() {
        openUserModal(row.dataset.userTemplate);
    });
});
document.addEventListener('keydown', function(e) {
    if (e.key !== 'Escape') return;
    if (!document.getElementById('user-modal').hidden) closeUserModal();
    if (!document.getElementById('notify-modal').hidden) closeNotifyModal();
    if (!document.getElementById('recovery-modal').hidden) closeRecoveryModal();
});
</script>
@endif

@if($resource === 'plans')
<div id="plan-modal" class="adm-modal" hidden>
    <div class="adm-modal-dialog adm-modal-dialog--user" role="dialog" aria-modal="true" aria-label="Карточка тарифа">
        <div id="plan-modal-content"></div>
    </div>
</div>

<div id="plan-edit-modal" class="adm-modal" hidden>
    <div class="adm-modal-dialog" role="dialog" aria-modal="true" aria-label="Изменение тарифа">
        <div id="plan-edit-modal-content"></div>
    </div>
</div>

<script>
(function () {
    const detailsModal = document.getElementById('plan-modal');
    const detailsContent = document.getElementById('plan-modal-content');
    const editModal = document.getElementById('plan-edit-modal');
    const editContent = document.getElementById('plan-edit-modal-content');

    function setModalOpen(modal, isOpen) {
        modal.hidden = !isOpen;
        document.body.classList.toggle('adm-modal-open', isOpen);
        if (!isOpen) modal.querySelector('[id$="-content"]')?.replaceChildren();
    }

    function bindModal(modal) {
        modal.querySelectorAll('[data-plan-close]').forEach(function (button) {
            button.addEventListener('click', function () {
                setModalOpen(modal, false);
            });
        });
        modal.querySelectorAll('.js-plan-edit').forEach(function (button) {
            button.addEventListener('click', function () {
                setModalOpen(detailsModal, false);
                openTemplate(this.dataset.planEdit, editModal, editContent);
            });
        });
    }

    function openTemplate(templateId, modal, content) {
        const template = document.getElementById(templateId);
        if (!template) return;
        content.replaceChildren(template.content.cloneNode(true));
        setModalOpen(modal, true);
        bindModal(modal);
        modal.querySelector('.adm-modal-close')?.focus();
    }

    document.querySelector('.js-plan-create')?.addEventListener('click', function () {
        openTemplate(this.dataset.planEdit, editModal, editContent);
    });

    document.querySelectorAll('.js-plan-row').forEach(function (row) {
        function openDetails() {
            openTemplate(row.dataset.planTemplate, detailsModal, detailsContent);
        }

        row.addEventListener('click', function (event) {
            if (event.target.closest('a, button, form')) return;
            openDetails();
        });
        row.addEventListener('keydown', function (event) {
            if (event.key === 'Enter' || event.key === ' ') {
                event.preventDefault();
                openDetails();
            }
        });
        row.querySelector('.js-plan-open')?.addEventListener('click', openDetails);
        row.querySelector('.js-plan-edit')?.addEventListener('click', function () {
            openTemplate(this.dataset.planEdit, editModal, editContent);
        });
    });

    [detailsModal, editModal].forEach(function (modal) {
        modal.addEventListener('click', function (event) {
            if (event.target === modal) setModalOpen(modal, false);
        });
    });

    document.addEventListener('keydown', function (event) {
        if (event.key !== 'Escape') return;
        if (!editModal.hidden) setModalOpen(editModal, false);
        else if (!detailsModal.hidden) setModalOpen(detailsModal, false);
    });
})();
</script>
@endif

@if($resource === 'subscriptions')
<div id="subscription-modal" class="adm-modal" hidden>
    <div class="adm-modal-dialog adm-modal-dialog--user" role="dialog" aria-modal="true" aria-label="Карточка подписки">
        <div id="subscription-modal-content"></div>
    </div>
</div>

<div id="subscription-edit-modal" class="adm-modal" hidden>
    <div class="adm-modal-dialog" role="dialog" aria-modal="true" aria-label="Изменение подписки">
        <div id="subscription-edit-modal-content"></div>
    </div>
</div>

<script>
(function () {
    const detailsModal = document.getElementById('subscription-modal');
    const detailsContent = document.getElementById('subscription-modal-content');
    const editModal = document.getElementById('subscription-edit-modal');
    const editContent = document.getElementById('subscription-edit-modal-content');

    function setModalOpen(modal, isOpen) {
        modal.hidden = !isOpen;
        document.body.classList.toggle('adm-modal-open', isOpen);
        if (!isOpen) modal.querySelector('[id$="-content"]')?.replaceChildren();
    }

    function bindCloseButtons(modal) {
        modal.querySelectorAll('[data-subscription-close]').forEach(function (button) {
            button.addEventListener('click', function () {
                setModalOpen(modal, false);
            });
        });
    }

    function openTemplate(templateId, modal, content) {
        const template = document.getElementById(templateId);
        if (!template) return;
        content.replaceChildren(template.content.cloneNode(true));
        setModalOpen(modal, true);
        bindCloseButtons(modal);
        modal.querySelector('.adm-modal-close')?.focus();
        modal.querySelectorAll('.js-subscription-edit').forEach(function (button) {
            button.addEventListener('click', function () {
                setModalOpen(detailsModal, false);
                openTemplate(this.dataset.subscriptionEdit, editModal, editContent);
            });
        });
    }

    document.querySelectorAll('.js-subscription-row').forEach(function (row) {
        function openDetails() {
            openTemplate(row.dataset.subscriptionTemplate, detailsModal, detailsContent);
        }

        row.addEventListener('click', function (event) {
            if (event.target.closest('a, button, form')) return;
            openDetails();
        });
        row.addEventListener('keydown', function (event) {
            if (event.key === 'Enter' || event.key === ' ') {
                event.preventDefault();
                openDetails();
            }
        });
        row.querySelector('.js-subscription-open')?.addEventListener('click', openDetails);
        row.querySelector('.js-subscription-edit')?.addEventListener('click', function () {
            openTemplate(this.dataset.subscriptionEdit, editModal, editContent);
        });
    });

    [detailsModal, editModal].forEach(function (modal) {
        modal.addEventListener('click', function (event) {
            if (event.target === modal) setModalOpen(modal, false);
        });
    });

    document.addEventListener('keydown', function (event) {
        if (event.key !== 'Escape') return;
        if (!editModal.hidden) setModalOpen(editModal, false);
        else if (!detailsModal.hidden) setModalOpen(detailsModal, false);
    });
})();
</script>
@endif

@endsection
