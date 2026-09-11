<!doctype html>
<html lang="ru">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Auralith | Профиль</title>
    <link rel="icon" type="image/png" sizes="32x32" href="{{ asset('images/favicon-32.png') }}?v=brand4">
    <link rel="manifest" href="{{ asset('manifest.webmanifest') }}">
    <link rel="apple-touch-icon" sizes="180x180" href="{{ asset('images/apple-touch-icon.png') }}?v=brand4">
    <meta name="theme-color" content="#08111f">
    <script>
        try {
            if (localStorage.getItem('auralith.notifyHubExpanded') !== '1') {
                document.documentElement.classList.add('notify-hub-pref-collapsed');
            }
        } catch (e) {}
    </script>
    <link rel="stylesheet" href="{{ asset('css/cabinet.css') }}?v=78">
</head>
<body class="is-loading profile-sidebar-collapsed">
<div class="profile-loader-modal" id="profile-loader-modal" aria-live="polite" aria-busy="true">
    <div class="profile-loader-card" role="status">
        <div class="profile-loader-orbit" aria-hidden="true"><span></span></div>
        <strong id="profile-loader-title">Загружаем кабинет</strong>
        <p id="profile-loader-detail">Подготавливаем данные профиля.</p>
        <div class="profile-loader-bar" aria-hidden="true"><span></span></div>
    </div>
</div>
<div class="glow glow-top"></div>
<div class="glow glow-bottom"></div>

<aside class="profile-sidebar" aria-label="Навигация профиля">
    <button type="button" class="profile-sidebar__mobile-toggle" onclick="closeProfileSidebar()" aria-label="Закрыть меню" aria-expanded="true">
        <svg viewBox="0 0 24 24" fill="none" width="16" height="16">
            <path d="M18 6L6 18M6 6l12 12" stroke="currentColor" stroke-width="2" stroke-linecap="round"/>
        </svg>
    </button>
    <a href="{{ route('home') }}" class="profile-sidebar__brand" aria-label="Auralith">
        <img src="{{ asset('images/logo-mark.png') }}?v=brand4" alt="Auralith" width="44" height="44">
        <span>Auralith Access</span>
    </a>

    <div class="profile-sidebar__user">
        <div class="profile-sidebar__avatar" aria-hidden="true">{{ mb_strtoupper(mb_substr($user->name, 0, 1)) }}</div>
        <div>
            <strong>{{ $user->name }}</strong>
            <span>{{ $user->username ? '@'.$user->username : 'Личный кабинет' }}</span>
        </div>
    </div>

    <nav class="profile-sidebar__nav">
        <a href="#overview" class="is-active" data-profile-nav="overview">
            <svg viewBox="0 0 24 24" fill="none"><path d="M3 9.5L12 3l9 6.5V20a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V9.5z" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"/><path d="M9 21v-8h6v8" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"/></svg>
            <span>Обзор</span>
        </a>
        <a href="#access" data-profile-nav="access">
            <svg viewBox="0 0 24 24" fill="none"><path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10Z" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"/><path d="M9 12l2 2 4-4" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/></svg>
            <span>Доступ</span>
        </a>
        <a href="#notifications" data-profile-nav="notifications">
            <svg viewBox="0 0 24 24" fill="none"><path d="M18 8A6 6 0 0 0 6 8c0 7-3 9-3 9h18s-3-2-3-9" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/><path d="M13.7 21a2 2 0 0 1-3.4 0" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/></svg>
            <span>Уведомления</span>
        </a>
        <a href="#security" data-profile-nav="security">
            <svg viewBox="0 0 24 24" fill="none"><path d="M7 11V8a5 5 0 0 1 10 0v3" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/><rect x="5" y="11" width="14" height="10" rx="2" stroke="currentColor" stroke-width="1.8"/><path d="M12 15v2" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/></svg>
            <span>Безопасность</span>
        </a>
        <a href="#rewards" data-profile-nav="rewards">
            <svg viewBox="0 0 24 24" fill="none"><path d="M20 12v8a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2v-8M2 7h20v5H2V7Z" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"/><path d="M12 22V7M12 7H8.5a2.5 2.5 0 1 1 0-5C12 2 12 7 12 7Zm0 0h3.5a2.5 2.5 0 1 0 0-5C12 2 12 7 12 7Z" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"/></svg>
            <span>Бонусы</span>
        </a>
        <a href="#support" data-profile-nav="support">
            <svg viewBox="0 0 24 24" fill="none"><path d="M21 11.5a8.4 8.4 0 0 1-.9 3.8 8.5 8.5 0 0 1-7.6 4.7 8.4 8.4 0 0 1-3.8-.9L3 21l1.9-5.7a8.4 8.4 0 0 1-.9-3.8 8.5 8.5 0 0 1 4.7-7.6 8.4 8.4 0 0 1 3.8-.9h.5a8.5 8.5 0 0 1 8 8v.5Z" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"/></svg>
            <span>Поддержка</span>
        </a>
    </nav>

    <div class="notif-bell profile-sidebar__notifications" id="notifBell">
        <button type="button" class="profile-sidebar__notice-btn" onclick="toggleNotifPanel()" aria-label="Центр уведомлений">
            <svg viewBox="0 0 24 24" fill="none"><path d="M18 8a6 6 0 0 0-12 0c0 7-3 7-3 7h18s-3 0-3-7Z" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"/><path d="M13.7 19a2 2 0 0 1-3.4 0" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/></svg>
            <span>Центр уведомлений</span>
            <span class="notif-bell__badge" id="notifBadge" style="display:none">0</span>
        </button>
    </div>

    <form action="{{ route('logout') }}" method="post" class="profile-sidebar__logout"
          data-loader-title="Выходим из кабинета"
          data-loader-detail="Завершаем текущую сессию.">
        @csrf
        <button type="submit">
            <svg viewBox="0 0 24 24" fill="none"><path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4M16 17l5-5-5-5M21 12H9" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/></svg>
            <span>Выйти</span>
        </button>
    </form>
</aside>

<div class="profile-sidebar-overlay" id="profileSidebarOverlay" onclick="closeProfileSidebar()" aria-hidden="true"></div>

<div class="notif-panel" id="notifPanel" style="display:none">
    <div class="notif-panel__head">
        <span>Центр уведомлений</span>
        <div class="notif-panel__actions">
            <button type="button" class="notif-panel__read-all" onclick="markAllRead()">Прочитать все</button>
            <button type="button" class="notif-panel__close" onclick="closeNotifPanel()" aria-label="Закрыть уведомления">
                <svg viewBox="0 0 24 24" fill="none" width="18" height="18">
                    <path d="M18 6L6 18M6 6l12 12" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/>
                </svg>
            </button>
        </div>
    </div>
    <div class="notif-panel__list" id="notifList">
        <p class="notif-panel__empty">Загрузка...</p>
    </div>
</div>

<main class="profile-main" id="profileMain" data-profile-page="overview">
    <button type="button" class="profile-menu-open" onclick="toggleProfileSidebar()" aria-label="Открыть меню" aria-expanded="false">
        <svg viewBox="0 0 24 24" fill="none" width="16" height="16">
            <path d="M4 6h16M4 12h16M4 18h16" stroke="currentColor" stroke-width="2" stroke-linecap="round"/>
        </svg>
    </button>

    {{-- Alerts --}}
    @if(session('success'))
        <div class="alert success">{{ session('success') }}</div>
    @endif
    @if(session('error'))
        <div class="alert error">{{ session('error') }}</div>
    @endif
    @if($errors->any())
        <div class="alert error">
            @foreach($errors->all() as $e)<p style="margin:0 0 4px">{{ $e }}</p>@endforeach
        </div>
    @endif

    {{-- Hero --}}
    <section class="hero profile-identity profile-page is-active skeleton-block" id="profile-overview" data-profile-page="overview">
        <div class="profile-overview__head">
            <p class="eyebrow">Личный кабинет</p>
            <h1>{{ $user->name }}</h1>
        </div>

        <div class="profile-overview-dashboard">
            <article class="profile-overview-access expiry-card expiry-{{ $expiryState }}">
                <div class="profile-overview-access__top">
                    <div>
                        <p class="profile-section-kicker">Ваш доступ</p>
                        <h2>{{ $isActive ? 'Подписка активна' : 'Подписка не активна' }}</h2>
                        <span>{{ $isActive ? 'Можно подключать устройства и пользоваться клиентом.' : 'Оформите подписку, чтобы получить ссылку подключения.' }}</span>
                    </div>
                    <span class="sub-badge {{ $isActive ? 'sub-badge-active' : 'sub-badge-expired' }}">{{ $isActive ? 'Активна' : 'Нет доступа' }}</span>
                </div>

                <div class="profile-overview-metrics">
                    <div>
                        <span>Тариф</span>
                        <strong>{{ $planName ?? 'Не выбран' }}</strong>
                    </div>
                    <div>
                        <span>Действует до</span>
                        <strong>{{ $isUnlimited ? 'Безлимитная' : ($expiresAt ? \Carbon\Carbon::parse($expiresAt)->translatedFormat('d M Y') : 'Не задано') }}</strong>
                    </div>
                    <div>
                        <span>Осталось</span>
                        <strong>{{ $isUnlimited ? 'Без ограничений' : ($daysLeft !== null ? ($daysLeft >= 1 ? $daysLeft.' дн.' : 'Менее суток') : '—') }}</strong>
                    </div>
                </div>

                <div class="profile-overview-cta">
                    @if($isActive)
                        <button type="button" class="connect-action connect-action--primary profile-connect-main" onclick="switchProfilePage('access')">
                            <svg viewBox="0 0 24 24" fill="none" aria-hidden="true"><path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10Z" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"/><path d="M9 12l2 2 4-4" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/></svg>
                            <span>Подключить устройство</span>
                        </button>
                        @if($windowsRelease['enabled'] ?? false)
                            <a href="{{ $windowsRelease['download_path'] }}" class="windows-download-panel__btn" download>
                                <svg viewBox="0 0 24 24" fill="none" aria-hidden="true"><path d="M4 5.5l7-1v7.2H4V5.5ZM13 4.2l7-1v8.5h-7V4.2ZM4 13h7v6.8l-7-1V13ZM13 13h7v8l-7-1.1V13Z" stroke="currentColor" stroke-width="1.55" stroke-linejoin="round"/></svg>
                                <span>Скачать Windows</span>
                            </a>
                        @endif
                    @else
                        <button type="button" class="subscribe-open-btn" onclick="openSubscribeModal()">Оформить подписку</button>
                    @endif
                </div>
            </article>

            <aside class="profile-overview-side" aria-label="Короткий статус профиля">
                <button type="button" class="profile-overview-side__item" id="overview-install-app-btn">
                    <svg viewBox="0 0 24 24" fill="none" aria-hidden="true"><rect x="7" y="2.8" width="10" height="18.4" rx="2.4" stroke="currentColor" stroke-width="1.8"/><path d="M10.5 18h3" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/></svg>
                    <span>Приложение</span>
                    <strong>Установить на телефон</strong>
                    <small id="overview-pwa-install-note">Быстрый вход с экрана Домой</small>
                </button>
                <button type="button" class="profile-overview-side__item" @if(! $user->telegram_id) id="overview-tg-link-btn" onclick="tgStartLink()" @else onclick="switchProfilePage('notifications')" @endif>
                    <svg viewBox="0 0 24 24" fill="none" aria-hidden="true"><path d="M21.8 2.2 1 10.1c-1.3.5-1.3 1.3-.2 1.6l5.2 1.6 2 6.3c.3.8.5 1.1 1.1 1.1.5 0 .7-.2 1-.5l2.5-2.4 5.2 3.8c1 .5 1.6.3 1.9-.9L23 3.3c.4-1.5-.6-2.2-1.2-1.1Z" stroke="currentColor" stroke-width="1.75" stroke-linejoin="round"/></svg>
                    <span>Telegram</span>
                    @if(! $user->telegram_id)
                        <strong>Подключить канал</strong>
                        <small id="overview-tg-link-hint">Уведомления и бонусы заработают стабильнее</small>
                    @else
                        <strong>Telegram подключён</strong>
                        <small>ID: {{ $user->telegram_id }}</small>
                    @endif
                </button>
                <button type="button" class="profile-overview-side__item" onclick="switchProfilePage('security')">
                    <svg viewBox="0 0 24 24" fill="none" aria-hidden="true"><path d="M7 10V8a5 5 0 0 1 10 0v2M6 10h12v10H6V10Z" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"/><path d="M10 15l1.5 1.5L15 13" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/></svg>
                    <span>Безопасность</span>
                    <strong>{{ $hasPassword ? 'Резервный вход настроен' : 'Нужен резервный вход' }}</strong>
                    <small>{{ $hasPassword ? 'Пароль установлен' : 'Добавьте пароль для входа без Telegram' }}</small>
                </button>
            </aside>
        </div>
    </section>

    {{-- Active subscription --}}
    @if($isActive)

        <section class="profile-primary profile-page skeleton-block expiry-card expiry-{{ $expiryState }}" id="profile-access" data-profile-page="access">
            <div class="profile-primary__head">
                <div>
                    <p class="profile-section-kicker">Ваш доступ</p>
                    <h2>Подписка активна</h2>
                    <span>Всё готово: подключите устройство или скопируйте ссылку для ручной настройки.</span>
                </div>
                <div class="profile-primary__status">
                    @if($isTrial)
                        <span class="sub-badge sub-badge-trial">Пробная</span>
                    @else
                        <span class="sub-badge sub-badge-active">Активна</span>
                    @endif
                </div>
            </div>

            <div class="profile-primary__metrics">
                <div><span>Тариф</span><strong>{{ $planName ?? '—' }}</strong></div>
                <div>
                    <span>Действует до</span>
                    <strong>{{ $isUnlimited ? '♾️ Безлимитная' : ($expiresAt ? \Carbon\Carbon::parse($expiresAt)->translatedFormat('d M Y') : '—') }}</strong>
                </div>
                <div>
                    <span>Осталось</span>
                    <strong>
                        @if($isUnlimited)
                            Без ограничений
                        @elseif($daysLeft !== null && $daysLeft >= 1)
                            {{ $daysLeft }} дн.
                        @elseif($daysLeft !== null && $daysLeft >= 0)
                            Менее суток
                        @else
                            Истекла
                        @endif
                    </strong>
                </div>
            </div>

            <div class="access-console">
                <section class="access-connect-card">
                    <div class="access-connect-card__main">
                        <p class="profile-section-kicker">Подключение</p>
                        <h3>Новое устройство</h3>
                        <p>Откройте мастер, он подберёт способ импорта для текущей платформы. QR-код и ссылка остаются рядом для ручной настройки.</p>

                        <div class="access-platform" id="connectDeviceHint">
                            <span class="access-platform__icon" aria-hidden="true">
                                <svg viewBox="0 0 24 24" fill="none"><rect x="7" y="3" width="10" height="18" rx="2.4" stroke="currentColor" stroke-width="1.8"/><path d="M10.5 18h3" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/></svg>
                            </span>
                            <div>
                                <span>Текущее устройство</span>
                                <strong id="connectDeviceTitle">Определяем платформу...</strong>
                                <small id="connectDeviceText">Подберём самый короткий путь подключения.</small>
                            </div>
                        </div>

                        <div class="access-actions connect-panel__actions">
                            <button type="button" class="connect-action connect-action--primary" id="connectDeviceAction" onclick="window.open('{{ route('sub.connect', ['token' => $user->token]) }}', '_blank', 'noopener')">Открыть мастер</button>
                            <button type="button" class="connect-action" onclick="showQRCode('{{ route('sub.content', ['token' => $user->token]) }}')">QR-код</button>
                            <button type="button" class="connect-action" data-copy="{{ route('sub.content', ['token' => $user->token]) }}" onclick="admCopy(this, this.dataset.copy)">Копировать</button>
                        </div>
                    </div>

                    <aside class="access-guide" aria-label="Как подключиться">
                        <ol>
                            <li><span>1</span><p>Откройте мастер подключения.</p></li>
                            <li><span>2</span><p>Импортируйте профиль в приложение.</p></li>
                            <li><span>3</span><p>Включите подключение и проверьте статус.</p></li>
                        </ol>
                    </aside>
                </section>

                <section class="access-manual" aria-label="Ручная настройка">
                    <div class="access-manual__head">
                        <div>
                            <p class="profile-section-kicker">Ручная настройка</p>
                            <h3>Ссылка конфигурации</h3>
                        </div>
                        <button type="button" class="access-manual__copy" data-copy="{{ route('sub.content', ['token' => $user->token]) }}" onclick="admCopy(this, this.dataset.copy)">Копировать</button>
                    </div>
                    <code class="conn-val copy-field access-manual__url" role="button" tabindex="0" title="Нажмите, чтобы скопировать" onclick="admCopy(null, this.textContent.trim(), this)" onkeydown="copyFieldKey(event, this.textContent.trim(), this)">{{ route('sub.content', ['token' => $user->token]) }}</code>
                    <p class="access-manual__note">
                        Используйте ссылку только для собственной, корпоративной или иной разрешённой инфраструктуры.
                        <a href="{{ route('offer') }}" target="_blank" rel="noopener">Оферта</a>
                    </p>
                </section>

                @if($windowsRelease['enabled'] ?? false)
                    <section class="access-download windows-download-panel" aria-label="Загрузка Auralith для Windows">
                        <div class="windows-download-panel__main">
                            <span class="windows-download-panel__icon" aria-hidden="true">
                                <svg viewBox="0 0 24 24" fill="none">
                                    <path d="M4 5.5l7-1v7.2H4V5.5ZM13 4.2l7-1v8.5h-7V4.2ZM4 13h7v6.8l-7-1V13ZM13 13h7v8l-7-1.1V13Z" stroke="currentColor" stroke-width="1.55" stroke-linejoin="round"/>
                                </svg>
                            </span>
                            <div>
                                <strong>Auralith для Windows</strong>
                                <span>
                                    Скачайте клиент и войдите через сайт.
                                    @if(! empty($windowsRelease['version']))
                                        Версия {{ $windowsRelease['version'] }}.
                                    @endif
                                </span>
                            </div>
                        </div>
                        <a href="{{ $windowsRelease['download_path'] }}" class="windows-download-panel__btn" download>
                            Скачать
                        </a>
                    </section>
                @endif

                <section class="access-devices profile-devices" id="profileDevices" data-devices-url="{{ route('profile.devices') }}">
                    <div class="profile-devices__head">
                        <div>
                            <p class="profile-section-kicker">Устройства</p>
                            <h3>Активность подключений</h3>
                        </div>
                        <button type="button" class="profile-devices__refresh" onclick="loadProfileDevices(true)">Обновить</button>
                    </div>
                    <div class="profile-devices__summary" id="profileDevicesSummary">Загружаем список из Core...</div>
                    <div class="profile-devices__list" id="profileDevicesList" aria-live="polite"></div>
                    <button type="button" class="profile-devices__more" id="profileDevicesMore" onclick="toggleProfileDevicesList()" hidden>Показать все</button>
                </section>
            </div>
            @if($hasRecurringSubscription)
                <div class="subscription-manage">
                    <span>Автопродление можно отключить без потери доступа до оплаченной даты.</span>
                    <button type="button" class="cancel-subscription-btn" onclick="openCancelSubscriptionModal()">Отменить подписку</button>
                </div>
            @endif
        </section>

    @else

        <section class="usage-card profile-page skeleton-block" id="profile-access" data-profile-page="access" style="text-align:center;padding:32px">
            <p style="color:var(--muted);margin:0 0 8px">У вас нет активной подписки</p>
            <p style="color:var(--muted);font-size:.88rem;margin:0 0 20px">Оформите подписку ниже</p>
            <button type="button" class="subscribe-open-btn" onclick="openSubscribeModal()">Оформить подписку →</button>
        </section>

    @endif

    @php
        $bonusTransactions = array_slice($bonusData['transactions'] ?? [], 0, 10);
        $referralLink = $referralData['referral_link'] ?? '';
        $passwordChangeReady = $hasPassword && $passwordChangeRequest?->status === 'confirmed';
        $passwordChangePending = $hasPassword && $passwordChangeRequest?->status === 'pending';
    @endphp

    <section class="profile-suite" id="profile-settings">
        <div class="profile-suite__head">
            <div>
                <p class="profile-section-kicker">Профиль</p>
                <h2>Настройки профиля</h2>
            </div>
            <span>Здесь можно настроить уведомления, резервный вход и быстрый вход по биометрии.</span>
        </div>

        <div class="profile-suite__layout">
            <div class="profile-suite__stack">

    {{-- Notifications hub --}}
    <span class="profile-anchor" id="profile-notifications"></span>
    <section class="notify-hub notify-hub--collapsed profile-page skeleton-block" id="notificationsHub" data-profile-page="notifications">
        <div class="notify-hub__head">
            <div class="notify-hub__title-row">
                <div class="notify-hub__icon">
                    <svg viewBox="0 0 24 24" fill="none" aria-hidden="true">
                        <path d="M18 8A6 6 0 0 0 6 8c0 7-3 9-3 9h18s-3-2-3-9" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"/>
                        <path d="M13.73 21a2 2 0 0 1-3.46 0" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"/>
                    </svg>
                </div>
                <div>
                    <h2>Уведомления</h2>
                    <p>Важные сообщения о подписке и входе в аккаунт.</p>
                </div>
            </div>
            <div class="notify-hub__actions">
                <div class="notify-hub__state" id="push-summary-state">
                    <span class="notify-hub__state-dot" id="push-status-dot"></span>
                    <span id="push-status-text">Проверяем браузер</span>
                </div>
            </div>
        </div>

        <div class="notify-hub__body" id="notifyHubBody">
            <div class="notify-hub__grid">
                <article class="notify-channel">
                    <div class="notify-channel__main">
                        <span class="notify-channel__mark notify-channel__mark--browser">
                            <svg viewBox="0 0 24 24" fill="none" aria-hidden="true">
                                <rect x="3.5" y="4.5" width="17" height="13" rx="2" stroke="currentColor" stroke-width="1.9"/>
                                <path d="M8.5 20.5h7M12 17.5v3" stroke="currentColor" stroke-width="1.9" stroke-linecap="round"/>
                            </svg>
                        </span>
                        <div>
                            <strong>Браузерные на этом устройстве</strong>
                            <span id="push-status-note">После включения уведомления будут приходить даже при закрытой вкладке.</span>
                        </div>
                    </div>
                    <button type="button" id="push-toggle-btn" class="push-toggle-btn" onclick="togglePushNotifications()">Включить</button>
                </article>

                <article class="notify-channel notify-channel--secondary">
                    <div class="notify-channel__main">
                        <span class="notify-channel__mark notify-channel__mark--app">
                            <svg viewBox="0 0 24 24" fill="none" aria-hidden="true">
                                <rect x="7.5" y="2.75" width="9" height="18.5" rx="2.4" stroke="currentColor" stroke-width="1.9"/>
                                <path d="M10.5 18h3" stroke="currentColor" stroke-width="1.9" stroke-linecap="round"/>
                            </svg>
                        </span>
                        <div>
                            <strong>На телефоне как приложение</strong>
                            <span id="pwa-install-note">Для iPhone добавьте Auralith на экран Домой, затем откройте и включите уведомления.</span>
                        </div>
                    </div>
                    <button type="button" id="install-app-btn" class="notify-secondary-btn" hidden>Установить</button>
                </article>

                <article class="notify-channel notify-channel--secondary">
                    <div class="notify-channel__main">
                        <span class="notify-channel__mark notify-channel__mark--telegram">
                            <svg viewBox="0 0 24 24" fill="none" aria-hidden="true">
                                <path d="M21.8 2.2L1 10.1c-1.3.5-1.3 1.3-.2 1.6l5.2 1.6 2 6.3c.3.8.5 1.1 1.1 1.1.5 0 .7-.2 1-.5l2.5-2.4 5.2 3.8c1 .5 1.6.3 1.9-.9L23 3.3c.4-1.5-.6-2.2-1.2-1.1z" stroke="currentColor" stroke-width="1.85" stroke-linejoin="round"/>
                            </svg>
                        </span>
                        <div>
                            @if(! $user->telegram_id)
                                <strong>Telegram не подключён</strong>
                                <span id="tg-link-hint">Можно подключить как запасной канал для важных уведомлений.</span>
                            @else
                                <strong class="notify-channel__ok">Telegram подключён</strong>
                                <span>ID: {{ $user->telegram_id }} · запасной канал активен</span>
                            @endif
                        </div>
                    </div>
                    @if(! $user->telegram_id)
                        <button type="button" class="notify-secondary-btn" id="tg-link-btn" onclick="tgStartLink()">Подключить</button>
                    @else
                        <button type="button" class="notify-secondary-btn notify-secondary-btn--muted" onclick="tgUnlink()">Отвязать</button>
                    @endif
                </article>
            </div>

            <div class="notify-hub__steps">
                <div><span>1</span><p>Нажмите «Включить» и разрешите уведомления в окне браузера.</p></div>
                <div><span>2</span><p>На iPhone сначала добавьте сайт на экран Домой и открывайте профиль через иконку.</p></div>
                <div><span>3</span><p>Если сменили браузер или телефон, включите уведомления заново на новом устройстве.</p></div>
            </div>
        </div>
    </section>

    <section class="account-card profile-page skeleton-block" id="profile-fast-login" data-profile-page="security">
        <div class="account-card__row">
            <div class="account-card__main">
                <span class="account-card__icon" aria-hidden="true">
                    <svg viewBox="0 0 24 24" fill="none">
                        <path d="M12 11v2.5M7.5 10.5v2A4.5 4.5 0 0 0 12 17a4.5 4.5 0 0 0 4.5-4.5v-2A4.5 4.5 0 0 0 12 6a4.5 4.5 0 0 0-4.5 4.5Z" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"/>
                        <path d="M5 12.5v-2a7 7 0 0 1 14 0v2M9 20.2A8.8 8.8 0 0 0 12 20a8.8 8.8 0 0 0 3-.5" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"/>
                    </svg>
                </span>
                <div>
                    <div class="account-card__title">
                        <span>Безопасность</span>
                        <strong>Быстрый вход</strong>
                    </div>
                    <p class="account-card__meta">
                        <span id="webauthn-status-text">Проверяем, можно ли входить по отпечатку или Face ID на этом устройстве...</span>
                    </p>
                </div>
            </div>
            <button type="button" class="copy-btn" id="webauthn-register-btn" onclick="registerUserWebAuthn()" disabled>
                Включить
            </button>
        </div>
        <div class="account-action-status" id="webauthn-profile-status" hidden></div>
    </section>

    {{-- Account settings --}}
    <section class="account-card profile-page skeleton-block" id="profile-security" data-profile-page="security">
        <div class="account-card__row">
            <div class="account-card__main">
                <span class="account-card__icon" aria-hidden="true">
                    <svg viewBox="0 0 24 24" fill="none">
                        <circle cx="12" cy="12" r="3" stroke="currentColor" stroke-width="1.8"/>
                        <path d="M19.4 15a1.7 1.7 0 0 0 .34 1.87l.05.05a2 2 0 0 1-2.83 2.83l-.05-.05a1.7 1.7 0 0 0-1.87-.34 1.7 1.7 0 0 0-1 1.56V21a2 2 0 0 1-4 0v-.08a1.7 1.7 0 0 0-1-1.56 1.7 1.7 0 0 0-1.87.34l-.05.05a2 2 0 0 1-2.83-2.83l.05-.05A1.7 1.7 0 0 0 4.6 15a1.7 1.7 0 0 0-1.56-1H3a2 2 0 0 1 0-4h.04A1.7 1.7 0 0 0 4.6 9a1.7 1.7 0 0 0-.34-1.87l-.05-.05a2 2 0 0 1 2.83-2.83l.05.05A1.7 1.7 0 0 0 9 4.6a1.7 1.7 0 0 0 1-1.56V3a2 2 0 0 1 4 0v.04a1.7 1.7 0 0 0 1 1.56 1.7 1.7 0 0 0 1.87-.34l.05-.05a2 2 0 0 1 2.83 2.83l-.05.05A1.7 1.7 0 0 0 19.4 9a1.7 1.7 0 0 0 1.56 1H21a2 2 0 0 1 0 4h-.04A1.7 1.7 0 0 0 19.4 15Z" stroke="currentColor" stroke-width="1.55" stroke-linecap="round" stroke-linejoin="round"/>
                    </svg>
                </span>
                <div>
                    <div class="account-card__title">
                        <span>Настройки аккаунта</span>
                        <strong>Резервный вход</strong>
                    </div>
                    <p class="account-card__meta">
                        <span class="account-card__login">Логин: <code>{{ $user->username }}</code></span>
                        @if($hasPassword)
                            <span class="account-card__ok">Пароль установлен</span>
                        @else
                            <span>Установите пароль, чтобы войти по логину, если Telegram временно недоступен.</span>
                        @endif
                    </p>
                </div>
            </div>
            @if($hasPassword)
                <button type="button" class="copy-btn" id="sp_change_btn" onclick="startPasswordChange()">
                    Сменить пароль
                </button>
            @endif
        </div>
        @if(! $hasPassword)
            <div class="account-warning">
                <strong>Запасной вход не настроен</strong>
                <span>Установите пароль, чтобы войти по логину, если Telegram временно недоступен.</span>
            </div>
        @endif
        <form method="post" action="{{ route('profile.set-password') }}" id="sp_form"
              class="account-password-form"
              data-loader-title="{{ $hasPassword ? 'Сохраняем пароль' : 'Настраиваем вход' }}"
              data-loader-detail="Обновляем данные аккаунта."
              style="display:{{ $hasPassword && ! $passwordChangeReady ? 'none' : 'flex' }}"
              onsubmit="return checkPasswords(this)">
            @csrf
            @if($hasPassword)
                <input type="hidden" name="password_change_token" id="password_change_token" value="{{ $passwordChangeRequest?->pwd_token }}">
            @endif
            <input type="password" name="password" id="sp_password" placeholder="{{ $hasPassword ? 'Новый пароль' : 'Новый пароль (мин. 8 символов)' }}" oninput="validateConfirm()">
            <input type="password" name="password_confirmation" id="sp_confirm" placeholder="Повторите пароль" oninput="validateConfirm()">
            <button type="submit" class="copy-btn">{{ $hasPassword ? 'Сохранить' : 'Установить пароль' }}</button>
            <p id="sp_hint"></p>
        </form>
        @if($hasPassword)
            <div class="account-action-status" id="password-change-status" @if(! $passwordChangeReady && ! $passwordChangePending) hidden @endif>
                @if($passwordChangeReady)
                    Смена пароля подтверждена в Telegram. Установите новый пароль.
                @elseif($passwordChangePending)
                    Ждём подтверждение смены пароля в Telegram...
                @endif
            </div>
        @endif
        <script>
        var passwordChangePollTimer = null;
        var initialPasswordChangeToken = @json($passwordChangeRequest?->pwd_token);
        var initialPasswordChangeStatus = @json($passwordChangeRequest?->status);

        (async function initUserWebAuthn() {
            var btn = document.getElementById('webauthn-register-btn');
            var text = document.getElementById('webauthn-status-text');
            if (!btn || !text) return;
            if (!window.PublicKeyCredential) {
                text.textContent = 'Устройство не поддерживает вход по отпечатку или Face ID.';
                return;
            }
            var available = await PublicKeyCredential.isUserVerifyingPlatformAuthenticatorAvailable().catch(function() { return false; });
            if (!available) {
                text.textContent = 'Биометрия недоступна в этом браузере или на этом устройстве.';
                return;
            }
            btn.disabled = false;
            try {
                var response = await fetch('{{ route("profile.webauthn.status") }}', { headers: { 'Accept': 'application/json' } });
                var data = await response.json();
                if (data.enabled) {
                    text.textContent = 'Вход по отпечатку или Face ID уже включён на одном из устройств.';
                    btn.textContent = 'Отключить';
                    btn.dataset.mode = 'delete';
                } else {
                    text.textContent = 'Можно включить быстрый вход на этом устройстве.';
                    btn.textContent = 'Включить';
                    btn.dataset.mode = 'register';
                }
            } catch (e) {
                text.textContent = 'Можно включить быстрый вход на этом устройстве.';
            }
        })();

        function setWebAuthnProfileStatus(text, kind) {
            var status = document.getElementById('webauthn-profile-status');
            if (!status) return;
            status.hidden = !text;
            status.textContent = text || '';
            status.classList.toggle('account-action-status--error', kind === 'error');
            status.classList.toggle('account-action-status--ok', kind === 'ok');
        }

        async function registerUserWebAuthn() {
            var btn = document.getElementById('webauthn-register-btn');
            var text = document.getElementById('webauthn-status-text');
            if (btn && btn.dataset.mode === 'delete') {
                await deleteUserWebAuthn();
                return;
            }
            if (btn) { btn.disabled = true; btn.textContent = 'Ожидание...'; }
            setWebAuthnProfileStatus('Подтвердите действие отпечатком или Face ID.', '');

            try {
                var challengeResponse = await fetch('{{ route("profile.webauthn.register.challenge") }}', {
                    method: 'POST',
                    headers: {'X-CSRF-TOKEN': '{{ csrf_token() }}', 'Accept': 'application/json'}
                });
                var opts = await challengeResponse.json();
                var credential = await navigator.credentials.create({
                    publicKey: {
                        challenge: base64ToBuffer(opts.challenge),
                        rp: opts.rp,
                        user: {
                            id: base64ToBuffer(opts.user.id),
                            name: opts.user.name,
                            displayName: opts.user.displayName,
                        },
                        pubKeyCredParams: opts.pubKeyCredParams,
                        timeout: opts.timeout,
                        authenticatorSelection: opts.authenticatorSelection,
                        attestation: opts.attestation,
                    }
                });
                var deviceName = /iPhone|iPad/.test(navigator.userAgent) ? 'iPhone/iPad'
                    : /Android/.test(navigator.userAgent) ? 'Android'
                    : 'Desktop';
                var verifyResponse = await fetch('{{ route("profile.webauthn.register.verify") }}', {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json',
                        'X-CSRF-TOKEN': '{{ csrf_token() }}',
                        'Accept': 'application/json',
                    },
                    body: JSON.stringify({
                        credential_id: bufferToBase64(credential.rawId),
                        public_key: bufferToBase64(credential.response.attestationObject),
                        device_name: deviceName,
                    }),
                });
                var result = await verifyResponse.json();
                if (!result.ok) throw new Error(result.error || 'Не удалось сохранить ключ');
                if (text) text.textContent = 'Вход по отпечатку или Face ID включён.';
                setWebAuthnProfileStatus('Готово. Теперь на странице входа появится кнопка биометрии.', 'ok');
                if (btn) {
                    btn.disabled = false;
                    btn.textContent = 'Отключить';
                    btn.dataset.mode = 'delete';
                }
            } catch (error) {
                setWebAuthnProfileStatus(error.name === 'NotAllowedError'
                    ? 'Настройка отменена или биометрия недоступна.'
                    : (error.message || 'Не удалось включить биометрию.'), 'error');
                if (btn) { btn.disabled = false; btn.textContent = 'Включить'; }
            }
        }

        async function deleteUserWebAuthn() {
            var btn = document.getElementById('webauthn-register-btn');
            var text = document.getElementById('webauthn-status-text');
            if (btn) { btn.disabled = true; btn.textContent = 'Удаляем...'; }
            setWebAuthnProfileStatus('', '');

            try {
                var response = await fetch('{{ route("profile.webauthn.delete") }}', {
                    method: 'DELETE',
                    headers: {'X-CSRF-TOKEN': '{{ csrf_token() }}', 'Accept': 'application/json'}
                });
                var result = await response.json();
                if (!result.ok) throw new Error(result.error || 'Не удалось удалить отпечаток');
                if (text) text.textContent = 'Быстрый вход отключён. Можно включить его снова на этом устройстве.';
                setWebAuthnProfileStatus('Быстрый вход отключён. Биометрия остаётся только на вашем устройстве.', 'ok');
                if (btn) {
                    btn.disabled = false;
                    btn.textContent = 'Включить';
                    btn.dataset.mode = 'register';
                }
            } catch (error) {
                setWebAuthnProfileStatus(error.message || 'Не удалось удалить отпечаток.', 'error');
                if (btn) { btn.disabled = false; btn.textContent = 'Отключить'; }
            }
        }

        function base64ToBuffer(base64) {
            var b = base64.replace(/-/g, '+').replace(/_/g, '/');
            var bin = atob(b);
            var buf = new Uint8Array(bin.length);
            for (var i = 0; i < bin.length; i++) buf[i] = bin.charCodeAt(i);
            return buf.buffer;
        }

        function bufferToBase64(buffer) {
            var bytes = new Uint8Array(buffer);
            var str = '';
            for (var i = 0; i < bytes.length; i++) str += String.fromCharCode(bytes[i]);
            return btoa(str).replace(/\+/g, '-').replace(/\//g, '_').replace(/=/g, '');
        }

        function setPasswordChangeStatus(text, kind) {
            var status = document.getElementById('password-change-status');
            if (!status) return;
            status.hidden = !text;
            status.textContent = text || '';
            status.classList.toggle('account-action-status--error', kind === 'error');
            status.classList.toggle('account-action-status--ok', kind === 'ok');
        }

        function startPasswordChange() {
            var btn = document.getElementById('sp_change_btn');
            var form = document.getElementById('sp_form');
            if (form) form.style.display = 'none';
            if (btn) { btn.disabled = true; btn.textContent = 'Ждём Telegram...'; }
            setPasswordChangeStatus('Отправляем подтверждение в Telegram...', '');
            profileShowLoader('Подтвердите смену пароля', 'Сейчас отправим запрос в Telegram-бот.');

            fetch('{{ route("profile.password-change.request") }}', {
                method: 'POST',
                headers: {
                    'X-CSRF-TOKEN': '{{ csrf_token() }}',
                    'Accept': 'application/json',
                }
            })
            .then(function(r) {
                return r.json().then(function(data) {
                    if (!r.ok || !data.ok) throw data;
                    return data;
                });
            })
            .then(function(data) {
                profileHideLoader();
                setPasswordChangeStatus('Подтвердите смену пароля в Telegram. После подтверждения форма откроется здесь.', '');
                if (passwordChangePollTimer) clearInterval(passwordChangePollTimer);
                passwordChangePollTimer = setInterval(function() {
                    pollPasswordChange(data.pwd_token);
                }, 3000);
                pollPasswordChange(data.pwd_token);
            })
            .catch(function(error) {
                profileHideLoader();
                if (btn) { btn.disabled = false; btn.textContent = 'Сменить пароль'; }
                setPasswordChangeStatus(error && error.message ? error.message : 'Не удалось отправить подтверждение в Telegram.', 'error');
            });
        }

        function pollPasswordChange(pwdToken) {
            fetch('{{ url("/profile/password-change/status") }}/' + encodeURIComponent(pwdToken), {
                headers: { 'Accept': 'application/json' }
            })
            .then(function(r) { return r.json(); })
            .then(function(data) {
                var btn = document.getElementById('sp_change_btn');
                var form = document.getElementById('sp_form');
                var tokenInput = document.getElementById('password_change_token');

                if (data.confirmed) {
                    clearInterval(passwordChangePollTimer);
                    if (tokenInput) tokenInput.value = pwdToken;
                    if (form) form.style.display = 'flex';
                    if (btn) { btn.disabled = false; btn.textContent = 'Сменить пароль'; }
                    setPasswordChangeStatus('Смена пароля подтверждена в Telegram. Установите новый пароль.', 'ok');
                } else if (data.cancelled || data.status === 'cancelled') {
                    clearInterval(passwordChangePollTimer);
                    if (btn) { btn.disabled = false; btn.textContent = 'Сменить пароль'; }
                    setPasswordChangeStatus('Смена пароля отменена в Telegram.', 'error');
                }
            })
                .catch(function() {
                    clearInterval(passwordChangePollTimer);
                    var btn = document.getElementById('sp_change_btn');
                    if (btn) { btn.disabled = false; btn.textContent = 'Сменить пароль'; }
                    setPasswordChangeStatus('Подтверждение устарело. Запросите смену пароля заново.', 'error');
                });
        }

        if (initialPasswordChangeToken && initialPasswordChangeStatus === 'pending') {
            var btn = document.getElementById('sp_change_btn');
            if (btn) { btn.disabled = true; btn.textContent = 'Ждём Telegram...'; }
            passwordChangePollTimer = setInterval(function() {
                pollPasswordChange(initialPasswordChangeToken);
            }, 3000);
            pollPasswordChange(initialPasswordChangeToken);
        }

        function validateConfirm() {
            var p = document.getElementById('sp_password').value;
            var c = document.getElementById('sp_confirm').value;
            var hint = document.getElementById('sp_hint');
            var confirmInput = document.getElementById('sp_confirm');
            if (!c) { hint.style.display='none'; confirmInput.style.borderColor=''; return; }
            if (p !== c) {
                hint.textContent = 'Пароли не совпадают';
                hint.style.color = '#f87171';
                hint.style.display = 'block';
                confirmInput.style.borderColor = 'rgba(248,113,113,.6)';
            } else if (p.length < 8) {
                hint.textContent = 'Минимум 8 символов';
                hint.style.color = '#fbbf24';
                hint.style.display = 'block';
                confirmInput.style.borderColor = 'rgba(251,191,36,.5)';
            } else {
                hint.textContent = 'Пароли совпадают';
                hint.style.color = '#4ade80';
                hint.style.display = 'block';
                confirmInput.style.borderColor = 'rgba(74,222,128,.5)';
            }
        }
        function checkPasswords(form) {
            var p = document.getElementById('sp_password').value;
            var c = document.getElementById('sp_confirm').value;
            if (p !== c || p.length < 8) { validateConfirm(); return false; }
            return true;
        }
        </script>
    </section>

            </div>
            <div class="profile-suite__stack profile-suite__stack--rewards">

    {{-- Referral and bonus program --}}
    <section class="rewards-grid profile-page skeleton-block" id="profile-rewards" data-profile-page="rewards">
        <article class="reward-card @if(! $user->telegram_id) reward-card--locked @endif">
            <div class="reward-card__head">
                <div>
                    <h2>Бонусный баланс</h2>
                    <p>1 балл = 1 ₽. Баллы действуют 12 месяцев с момента начисления.</p>
                </div>
                @if($bonusData)
                    <strong class="bonus-balance">{{ (int) ($bonusData['balance'] ?? 0) }} <span>баллов</span></strong>
                @endif
            </div>

            @if(! $user->telegram_id)
                <div class="reward-empty">Бонусный баланс появится после подключения Telegram.</div>
                <div class="reward-lock">
                    <strong>Подключите Telegram</strong>
                    <span>Через блок уведомлений выше, чтобы открыть бонусы и историю начислений.</span>
                </div>
            @elseif(! $bonusData)
                <div class="reward-empty">Не удалось загрузить бонусный баланс. Попробуйте обновить страницу позже.</div>
            @elseif(empty($bonusTransactions))
                <div class="reward-empty">Начислений пока нет. Приглашайте друзей, и история появится здесь.</div>
            @else
                <div class="bonus-table" role="table" aria-label="История бонусов">
                    <div class="bonus-table__row bonus-table__row--head" role="row">
                        <span role="columnheader">Дата</span>
                        <span role="columnheader">Описание</span>
                        <span role="columnheader">Сумма</span>
                    </div>
                    @foreach($bonusTransactions as $transaction)
                        @php
                            $amount = (int) ($transaction['amount'] ?? 0);
                            $createdAt = $transaction['created_at'] ?? null;
                            $createdLabel = $createdAt ? \Carbon\Carbon::parse($createdAt)->format('d.m.Y') : '—';
                        @endphp
                        <div class="bonus-table__row" role="row">
                            <span role="cell">{{ $createdLabel }}</span>
                            <span role="cell">{{ $transaction['description'] ?? 'Операция по бонусам' }}</span>
                            <strong role="cell" class="{{ $amount >= 0 ? 'bonus-amount bonus-amount--plus' : 'bonus-amount bonus-amount--minus' }}">
                                {{ $amount >= 0 ? '+' : '−' }}{{ abs($amount) }}
                            </strong>
                        </div>
                    @endforeach
                </div>
            @endif
        </article>

        <article class="reward-card @if(! $user->telegram_id) reward-card--locked @endif">
            <div class="reward-card__head">
                <div>
                    <h2>Реферальная программа</h2>
                    <p>Приглашайте друзей — получайте 10% от их первой оплаты бонусными баллами.</p>
                </div>
            </div>

            @if(! $user->telegram_id)
                <div class="reward-empty">Реферальная ссылка появится после подключения Telegram.</div>
                <div class="reward-lock">
                    <strong>Подключите Telegram</strong>
                    <span>Сделайте это в блоке уведомлений выше, и реферальная программа станет доступна.</span>
                </div>
            @elseif(! $referralData)
                <div class="reward-empty">Не удалось загрузить реферальную ссылку. Попробуйте обновить страницу позже.</div>
            @else
                <div class="referral-copy">
                    <input type="text" value="{{ $referralLink }}" readonly aria-label="Реферальная ссылка" class="copy-field" title="Нажмите, чтобы скопировать" onclick="admCopy(null, this.value, this)" onkeydown="copyFieldKey(event, this.value, this)">
                    <button type="button" class="copy-btn" data-copy="{{ $referralLink }}" onclick="admCopy(this, this.dataset.copy)">Копировать</button>
                </div>

                <div class="reward-stats">
                    <div>
                        <span>Друзей приглашено</span>
                        <strong>{{ (int) ($referralData['referred_count'] ?? 0) }}</strong>
                    </div>
                    <div>
                        <span>Всего начислено</span>
                        <strong>{{ (int) ($referralData['total_earned'] ?? 0) }} баллов</strong>
                    </div>
                </div>
            @endif
        </article>
    </section>

            </div>
        </div>
    </section>

    <section class="profile-support-card profile-page skeleton-block" id="profile-support" data-profile-page="support">
        <div>
            <p class="profile-section-kicker">Поддержка</p>
            <h2>Поможем с подключением и оплатой</h2>
            <span>Если устройство не подключается, не пришло уведомление или нужна помощь с подпиской, напишите в Telegram.</span>
        </div>
        <div class="profile-support-card__actions">
            <a href="https://t.me/{{ config('services.telegram.bot_username', 'auralithaccessbot') }}" target="_blank" rel="noopener" class="profile-support-card__primary">
                Открыть Telegram
            </a>
            <a href="{{ route('faq') }}" class="profile-support-card__secondary">
                FAQ
            </a>
        </div>
    </section>

</main>

{{-- QR Code Modal --}}
<div class="modal-overlay" id="qrModal" onclick="closeQRModal(event)" style="display:none">
    <div class="modal-box" style="max-width:400px;text-align:center">
        <div class="modal-header">
            <h3>QR-код подписки</h3>
            <button type="button" class="modal-close" onclick="closeQRModal()">✕</button>
        </div>
        <div id="qrCodeContainer" style="padding:20px;background:#fff;border-radius:8px;margin:20px 0;display:flex;justify-content:center;align-items:center"></div>
        <p style="color:var(--muted);font-size:.88rem;margin:0">Отсканируйте QR-код в приложении клиента</p>
    </div>
</div>

{{-- Cancel Subscription Modal --}}
@if($hasRecurringSubscription)
<div class="modal-overlay" id="cancelSubscriptionModal" onclick="closeCancelSubscriptionModal(event)">
    <div class="modal-box cancel-subscription-modal">
        <div class="modal-header">
            <h3>Отменить подписку?</h3>
            <button type="button" class="modal-close" onclick="closeCancelSubscriptionModal()">×</button>
        </div>
        <p class="modal-sub">
            Списания остановятся, но доступ сохранится до конца оплаченного периода
            @if($isUnlimited)
                — <strong>без ограничения срока</strong>.
            @elseif($expiresAt)
                — до <strong>{{ \Carbon\Carbon::parse($expiresAt)->translatedFormat('d M Y') }}</strong>.
            @else
                .
            @endif
            Отменить?
        </p>
        <div class="cancel-subscription-result" id="cancelSubscriptionResult" hidden></div>
        <div class="cancel-subscription-actions">
            <button type="button" class="cancel-confirm-btn" id="cancelSubscriptionConfirmBtn" onclick="confirmCancelSubscription()">Да, отменить</button>
            <button type="button" class="cancel-keep-btn" onclick="closeCancelSubscriptionModal()">Нет, оставить</button>
        </div>
    </div>
</div>
@endif

{{-- Subscribe Modal --}}
<div class="modal-overlay" id="subscribeModal" onclick="closeSubscribeModal(event)">
    <div class="modal-box">

        {{-- Step 1: Choose plan --}}
        <div class="modal-step" id="modalStep1">
            <div class="modal-header">
                <h3>Оформить подписку</h3>
                <button type="button" class="modal-close" onclick="closeSubscribeModal()">✕</button>
            </div>
            <div class="modal-progress" aria-label="Шаг оформления">
                <span class="is-active">Тариф</span>
                <span>Оплата</span>
            </div>
            <p class="modal-sub">Выберите срок доступа <span class="modal-trial-note">1 день бесплатно</span></p>

            <div class="modal-plans">
                @foreach($dbPlans as $plan)
                <label class="modal-plan-card {{ $plan->is_highlighted ? 'modal-plan-popular' : '' }}"
                       data-price="{{ $plan->price_rub }}"
                       data-months="{{ $plan->duration_months }}"
                       data-name="{{ $plan->name }}">
                    <input type="radio" name="modal_plan" value="{{ $plan->id }}" {{ $loop->first ? 'checked' : '' }}>
                    <div class="modal-plan-inner">
                        @if($plan->is_highlighted)
                        <span class="modal-plan-badge">Популярный</span>
                        @endif
                        <div class="modal-plan-name">{{ $plan->name }}</div>
                        <div class="modal-plan-price">{{ number_format($plan->price_rub, 0, '.', ' ') }} ₽<span>/ {{ $plan->duration_months }} {{ $plan->duration_months === 1 ? 'мес' : ($plan->duration_months < 5 ? 'мес' : 'мес') }}</span></div>
                        <div class="modal-plan-monthly">{{ number_format($plan->price_rub / max(1, $plan->duration_months), 0, '.', ' ') }} ₽ в месяц</div>
                        @if($plan->features)
                        <ul>
                            @foreach(is_array($plan->features) ? $plan->features : json_decode($plan->features, true) ?? [] as $feature)
                            <li>{{ $feature }}</li>
                            @endforeach
                        </ul>
                        @endif
                    </div>
                </label>
                @endforeach
            </div>

            <button type="button" class="modal-next-btn" onclick="goToStep2()">Продолжить к оплате</button>
        </div>

        {{-- Step 2: Payment --}}
        <div class="modal-step hidden" id="modalStep2">
            <div class="modal-header">
                <button type="button" class="modal-back" onclick="goToStep1()">
                <svg viewBox="0 0 16 16" fill="none" width="14" height="14" style="flex-shrink:0"><path d="M10 3L5 8l5 5" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/></svg>
                Назад
            </button>
                <h3>Оплата</h3>
                <button type="button" class="modal-close" onclick="closeSubscribeModal()">✕</button>
            </div>
            <div class="modal-progress" aria-label="Шаг оформления">
                <span>Тариф</span>
                <span class="is-active">Оплата</span>
            </div>
            <p class="modal-sub">Проверьте заказ перед переходом к оплате</p>

            <div class="modal-order-summary" id="modalOrderSummary">
                <div><span>Тариф</span><strong id="summaryPlan">—</strong></div>
                <div><span>Сумма</span><strong id="summaryPrice">—</strong></div>
                <div><span>Период</span><strong id="summaryDays">—</strong></div>
            </div>

            <div id="cp-error" style="display:none;color:#f87171;font-size:.85rem;text-align:center;margin-bottom:12px"></div>
            <input
                type="text"
                id="cp-promocode"
                class="adm-input"
                placeholder="Промокод, если есть"
                style="width:100%;margin-bottom:12px;background:rgba(255,255,255,.06);border:1px solid var(--line);border-radius:8px;padding:10px 12px;color:#fff"
                maxlength="64"
            >

            <button type="button" class="modal-next-btn" id="cp-pay-btn" onclick="startCloudPayment()">
                Оплатить картой
            </button>
            <p style="text-align:center;color:var(--muted);font-size:.78rem;margin-top:10px">
                Оплата через CloudPayments · Карты РФ, СБП
            </p>
        </div>

    </div>
</div>

<script src="{{ asset('js/cabinet.js') }}?v=8"></script>
<script src="https://cdn.jsdelivr.net/npm/qrcodejs@1.0.0/qrcode.min.js"></script>
<script>
// Web Push config
window.PUSH_VAPID_PUBLIC_KEY = '{{ config("webpush.vapid.public_key", "") }}';
window.PUSH_SUBSCRIBE_URL    = '{{ route("push.subscribe") }}';
window.PUSH_UNSUBSCRIBE_URL  = '{{ route("push.unsubscribe") }}';
window.PUSH_STATUS_URL       = '{{ route("push.status") }}';
window.CSRF_TOKEN            = '{{ csrf_token() }}';
window.PUSH_USER_ID          = {{ $user->id ?? 'null' }};
</script>
<script src="{{ asset('js/push-notifications.js') }}?v=6"></script>
<script>
// ── CloudPayments config ──
var CP_PUBLIC_ID = '{{ config("services.cloudpayments.public_id", "") }}';
var CP_CREATE_ORDER_URL = '{{ route("profile.cloudpayments.order") }}';
var CANCEL_SUBSCRIPTION_URL = '{{ route("profile.cancel-subscription") }}';
var CP_USER_EMAIL = '{{ $user->email ?? "" }}';
var CP_USER_NAME  = '{{ $user->name }}';
var _selectedPlanId    = null;
var _selectedPlanPrice = null;
var _selectedPlanName  = null;
var _selectedPlanMonths = null;
var _cloudPaymentsLoader = null;

function admCopy(btn, text, field) {
    var originalText = btn ? btn.textContent : null;
    var done = function() {
        if (field) {
            if (typeof field.select === 'function') field.select();
            field.classList.add('copy-field--copied');
            setTimeout(function() { field.classList.remove('copy-field--copied'); }, 900);
        }
        if (btn) {
            btn.textContent = 'Скопировано';
            setTimeout(function() { btn.textContent = originalText || 'Копировать'; }, 2000);
        }
    };
    var fallback = function() {
        var ta = document.createElement('textarea');
        ta.value = text || '';
        ta.setAttribute('readonly', '');
        ta.style.position = 'fixed';
        ta.style.left = '-9999px';
        document.body.appendChild(ta);
        ta.select();
        try { document.execCommand('copy'); done(); } catch (e) {}
        document.body.removeChild(ta);
    };

    if (navigator.clipboard && window.isSecureContext) {
        navigator.clipboard.writeText(text || '').then(done).catch(fallback);
    } else {
        fallback();
    }
}

function copyFieldKey(event, text, el) {
    if (event.key !== 'Enter' && event.key !== ' ') return;
    event.preventDefault();
    admCopy(null, text, el);
}

// ── QR Code Modal ──
function openCancelSubscriptionModal() {
    var modal = document.getElementById('cancelSubscriptionModal');
    var result = document.getElementById('cancelSubscriptionResult');
    if (!modal) return;
    if (result) {
        result.hidden = true;
        result.textContent = '';
        result.className = 'cancel-subscription-result';
    }
    modal.classList.add('active');
    document.body.style.overflow = 'hidden';
}

function closeCancelSubscriptionModal(event) {
    var modal = document.getElementById('cancelSubscriptionModal');
    if (!modal) return;
    if (event && event.target !== modal) return;
    modal.classList.remove('active');
    document.body.style.overflow = '';
}

function confirmCancelSubscription() {
    var btn = document.getElementById('cancelSubscriptionConfirmBtn');
    var result = document.getElementById('cancelSubscriptionResult');
    if (btn) btn.disabled = true;
    if (result) {
        result.hidden = true;
        result.textContent = '';
        result.className = 'cancel-subscription-result';
    }

    profileShowLoader('Отменяем автосписание', 'Останавливаем продление подписки, доступ сохранится до оплаченной даты.');

    fetch(CANCEL_SUBSCRIPTION_URL, {
        method: 'POST',
        headers: {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
            'X-CSRF-TOKEN': window.CSRF_TOKEN
        },
        body: JSON.stringify({})
    })
    .then(function(response) {
        return response.json().catch(function() { return {}; }).then(function(data) {
            if (!response.ok) throw data;
            return data;
        });
    })
    .then(function(data) {
        profileHideLoader();
        if (result) {
            result.hidden = false;
            result.textContent = data.message || 'Подписка отменена.';
            result.classList.add('is-success');
        }
        setTimeout(function() { window.location.reload(); }, 1100);
    })
    .catch(function(error) {
        profileHideLoader();
        if (btn) btn.disabled = false;
        if (result) {
            result.hidden = false;
            result.textContent = error.message || 'Не удалось отменить, обратитесь в поддержку.';
            result.classList.add('is-error');
        }
    });
}

function showQRCode(url) {
    var modal = document.getElementById('qrModal');
    var container = document.getElementById('qrCodeContainer');
    container.innerHTML = '';
    new QRCode(container, {
        text: url,
        width: 256,
        height: 256,
        colorDark: '#000000',
        colorLight: '#ffffff',
        correctLevel: QRCode.CorrectLevel.H
    });
    modal.style.display = 'flex';
}

function closeQRModal(event) {
    if (event && event.target !== event.currentTarget) return;
    document.getElementById('qrModal').style.display = 'none';
}

// ── Subscribe modal ──
function goToStep2() {
    var selected = document.querySelector('input[name="modal_plan"]:checked');
    if (!selected) return;

    var card = selected.closest('.modal-plan-card');
    _selectedPlanId     = selected.value;
    _selectedPlanPrice  = parseFloat(card.dataset.price);
    _selectedPlanName   = card.dataset.name;
    _selectedPlanMonths = parseInt(card.dataset.months);

    document.getElementById('summaryPlan').textContent  = _selectedPlanName;
    document.getElementById('summaryPrice').textContent = _selectedPlanPrice + ' ₽';
    document.getElementById('summaryDays').textContent  = _selectedPlanMonths + ' ' + (_selectedPlanMonths === 1 ? 'месяц' : (_selectedPlanMonths < 5 ? 'месяца' : 'месяцев'));

    document.getElementById('modalStep1').classList.add('hidden');
    document.getElementById('modalStep2').classList.remove('hidden');
}

function goToStep1() {
    document.getElementById('modalStep2').classList.add('hidden');
    document.getElementById('modalStep1').classList.remove('hidden');
}

// ── CloudPayments widget ──
function loadCloudPaymentsWidget() {
    if (window.cp && window.cp.CloudPayments) {
        return Promise.resolve();
    }

    if (_cloudPaymentsLoader) {
        return _cloudPaymentsLoader;
    }

    _cloudPaymentsLoader = new Promise(function(resolve, reject) {
        var script = document.createElement('script');
        script.src = 'https://widget.cloudpayments.ru/bundles/cloudpayments.js';
        script.async = true;
        script.onload = function() {
            if (window.cp && window.cp.CloudPayments) {
                resolve();
            } else {
                reject(new Error('CloudPayments загрузился некорректно'));
            }
        };
        script.onerror = function() {
            reject(new Error('Не удалось загрузить платёжный виджет CloudPayments. Проверьте подключение, сетевые фильтры или попробуйте позже.'));
        };
        document.head.appendChild(script);
    });

    return _cloudPaymentsLoader;
}

function startCloudPayment() {
    if (!_selectedPlanId || !_selectedPlanPrice) return;

    var errEl = document.getElementById('cp-error');
    var btn   = document.getElementById('cp-pay-btn');
    errEl.style.display = 'none';
    btn.disabled = true;
    btn.textContent = 'Создаём заказ...';
    profileShowLoader('Создаём заказ', 'Подготавливаем безопасную форму оплаты.');

    fetch(CP_CREATE_ORDER_URL, {
        method: 'POST',
        headers: {
            'X-CSRF-TOKEN': '{{ csrf_token() }}',
            'Accept': 'application/json',
            'Content-Type': 'application/json'
        },
        body: JSON.stringify({
            plan_id: _selectedPlanId,
            promocode: (document.getElementById('cp-promocode')?.value || '').trim()
        })
    })
    .then(function(response) {
        if (!response.ok) throw new Error('Не удалось создать заказ');
        return response.json();
    })
    .then(function(payload) {
        if (payload.free) {
            btn.disabled = false;
            btn.textContent = 'Оплатить картой →';
            closeSubscribeModal();
            profileShowLoader('Активируем подписку', 'Применяем промокод и обновляем данные.');
            var promoAlert = document.createElement('div');
            promoAlert.className = 'alert success';
            promoAlert.textContent = '✓ Промокод применён! Подписка активирована.';
            document.querySelector('main').prepend(promoAlert);
            setTimeout(function() { location.reload(); }, 2500);
            return Promise.resolve('free');
        }

        btn.textContent = 'Загружаем форму оплаты...';

        return loadCloudPaymentsWidget().then(function() {
            btn.textContent = 'Открываем форму оплаты...';
            profileHideLoader();

            var widget = new cp.CloudPayments({ language: 'ru-RU' });
            var options = payload.widget;

            if (widget.start) {
                return widget.start(options).then(function(result) {
                    if (result && result.status === 'success') {
                        return true;
                    }
                    throw new Error('Оплата не завершена');
                });
            }

            return new Promise(function(resolve, reject) {
                widget.pay('charge', {
                    publicId: options.publicId || CP_PUBLIC_ID,
                    description: options.description,
                    amount: options.amount,
                    currency: options.currency,
                    accountId: options.accountId,
                    invoiceId: options.invoiceId,
                    email: CP_USER_EMAIL || undefined,
                    data: options.data,
                    receipt: options.receipt,
                    skin: 'mini'
                }, {
                    onSuccess: function() { resolve(true); },
                    onFail: function(reason) { reject(new Error(reason || 'Оплата не прошла')); },
                    onComplete: function() {
                        btn.disabled = false;
                        btn.textContent = 'Оплатить картой →';
                    }
                });
            });
        });
    })
    .then(function(result) {
            if (result === 'free') return;
            btn.disabled = false;
            btn.textContent = 'Оплатить картой →';
            closeSubscribeModal();
            profileShowLoader('Обновляем подписку', 'Оплата прошла, синхронизируем статус.');
            var alert = document.createElement('div');
            alert.className = 'alert success';
            alert.textContent = '✓ Оплата прошла успешно! Подписка активируется в течение нескольких минут.';
            document.querySelector('main').prepend(alert);
            setTimeout(function() { location.reload(); }, 4000);
    })
    .catch(function(error) {
        btn.disabled = false;
        btn.textContent = 'Оплатить картой →';
        profileHideLoader();
        errEl.textContent = error.message || 'Оплата не прошла, попробуйте ещё раз';
        errEl.style.display = 'block';
    });
}

// ── Profile pages ──
var PROFILE_PAGES = ['overview', 'access', 'notifications', 'security', 'rewards', 'support'];

function switchProfilePage(page, options) {
    options = options || {};
    if (PROFILE_PAGES.indexOf(page) === -1) page = 'overview';

    if (!options.silent && !options.skipLoader) {
        profileShowLoader('Открываем раздел', 'Переходим к выбранной части кабинета.');
        setTimeout(function() {
            switchProfilePage(page, Object.assign({}, options, { skipLoader: true, instant: true }));
            setTimeout(profileHideLoader, 120);
        }, 180);
        return;
    }

    var main = document.getElementById('profileMain');
    if (main) main.dataset.profilePage = page;

    document.querySelectorAll('[data-profile-nav]').forEach(function(link) {
        link.classList.toggle('is-active', link.dataset.profileNav === page);
    });

    document.querySelectorAll('.profile-page').forEach(function(section) {
        section.classList.toggle('is-active', section.dataset.profilePage === page);
    });

    document.body.classList.toggle('profile-page-notifications', page === 'notifications');

    if (page === 'notifications') {
        setNotifyHubExpanded(true);
        loadNotifications();
    }

    if (!options.silent) {
        try {
            history.replaceState(null, '', '#' + page);
        } catch (e) {}
        if (window.matchMedia('(max-width: 980px)').matches) {
            setProfileSidebarCollapsed(true);
        }
        window.scrollTo({ top: 0, behavior: options.instant ? 'auto' : 'smooth' });
    }
}

function initProfilePages() {
    document.querySelectorAll('[data-profile-nav]').forEach(function(link) {
        link.addEventListener('click', function(event) {
            event.preventDefault();
            switchProfilePage(link.dataset.profileNav);
            if (window.matchMedia('(max-width: 980px)').matches) {
                closeProfileSidebar();
            }
        });
    });

    var initial = (window.location.hash || '').replace('#', '');
    switchProfilePage(PROFILE_PAGES.indexOf(initial) === -1 ? 'overview' : initial, { silent: true, instant: true });
}

function setProfileSidebarCollapsed(collapsed) {
    var isMobile = window.matchMedia('(max-width: 980px)').matches;
    if (!isMobile) {
        collapsed = false;
    }

    document.body.classList.toggle('profile-sidebar-collapsed', collapsed);
    document.body.classList.toggle('profile-sidebar-open', !collapsed && isMobile);

    var openBtn = document.querySelector('.profile-menu-open');
    var closeBtn = document.querySelector('.profile-sidebar__mobile-toggle');
    var overlay = document.getElementById('profileSidebarOverlay');
    if (openBtn) {
        openBtn.setAttribute('aria-expanded', collapsed ? 'false' : 'true');
    }
    if (closeBtn) {
        closeBtn.setAttribute('aria-expanded', collapsed ? 'false' : 'true');
    }
    if (overlay) {
        overlay.classList.toggle('open', !collapsed && isMobile);
    }
}

function toggleProfileSidebar() {
    setProfileSidebarCollapsed(!document.body.classList.contains('profile-sidebar-collapsed'));
}

function closeProfileSidebar() {
    setProfileSidebarCollapsed(true);
}

function initProfileSidebar() {
    if (window.matchMedia('(max-width: 980px)').matches) {
        setProfileSidebarCollapsed(true);
    } else {
        setProfileSidebarCollapsed(false);
        document.body.classList.remove('profile-sidebar-open');
    }
}

// ── Notifications ──
var _notifOpen = false;
var _notifPanelHome = null;
var NOTIFY_HUB_STORAGE_KEY = 'auralith.notifyHubExpanded';

function setNotifyHubExpanded(expanded) {
    var hub = document.getElementById('notificationsHub');
    var btn = document.getElementById('notifyHubToggle');
    if (!hub) return;

    hub.classList.toggle('notify-hub--collapsed', !expanded);
    if (!btn) return;

    btn.setAttribute('aria-expanded', expanded ? 'true' : 'false');

    var text = btn.querySelector('.notify-hub__toggle-text');
    if (text) text.textContent = expanded ? 'Свернуть' : 'Настроить';

    try {
        localStorage.setItem(NOTIFY_HUB_STORAGE_KEY, expanded ? '1' : '0');
    } catch (e) {}
}

function toggleNotifyHub() {
    var hub = document.getElementById('notificationsHub');
    if (!hub) return;
    setNotifyHubExpanded(hub.classList.contains('notify-hub--collapsed'));
}

function initNotifyHub() {
    setNotifyHubExpanded(true);
    document.documentElement.classList.remove('notify-hub-pref-collapsed');
}

function getNotifPanel() {
    return document.getElementById('notifPanel');
}

function isMobileNotifPanel() {
    return window.matchMedia('(max-width: 700px)').matches;
}

function placeNotifPanel(panel) {
    if (!_notifPanelHome) {
        _notifPanelHome = {
            parent: panel.parentNode,
            next: panel.nextSibling
        };
    }

    if (isMobileNotifPanel()) {
        if (panel.parentNode !== document.body) {
            document.body.appendChild(panel);
        }
        panel.classList.add('notif-panel--portal');
        return;
    }

    if (_notifPanelHome.parent && panel.parentNode !== _notifPanelHome.parent) {
        _notifPanelHome.parent.insertBefore(panel, _notifPanelHome.next);
    }
    panel.classList.remove('notif-panel--portal');
}

function openNotifPanel() {
    var panel = getNotifPanel();
    if (!panel) return;
    placeNotifPanel(panel);
    panel.classList.add('notif-panel--open');
    panel.style.display = 'flex';
    document.body.classList.add('notif-panel-open');
    _notifOpen = true;
    loadNotifications();
}

function closeNotifPanel() {
    var panel = getNotifPanel();
    if (!panel) return;
    panel.classList.remove('notif-panel--open');
    panel.style.display = 'none';
    document.body.classList.remove('notif-panel-open');
    _notifOpen = false;
}

function toggleNotifPanel() {
    if (_notifOpen) {
        closeNotifPanel();
    } else {
        openNotifPanel();
    }
}

function loadNotifications() {
    fetch('{{ route("notifications.index") }}', { headers: { 'Accept': 'application/json' } })
    .then(r => r.json())
    .then(data => {
        updateBadge(data.unread_count);
        renderNotifications(data.notifications);
    });
}

function renderNotifications(items) {
    var list = document.getElementById('notifList');
    if (!items.length) {
        list.innerHTML = '<p class="notif-panel__empty">Нет уведомлений</p>';
        return;
    }
    list.innerHTML = items.map(function(n) {
        var typeColor = n.type === 'success' ? '#4ade80' : (n.type === 'warning' ? '#fbbf24' : '#6b93c0');
        var typeBg    = n.type === 'success' ? 'rgba(74,222,128,.1)' : (n.type === 'warning' ? 'rgba(251,191,36,.08)' : 'rgba(79,126,181,.1)');
        var unreadLabel = n.is_read ? '' : '<span class="notif-item__new">Новое</span>';
        return '<div class="notif-item' + (n.is_read ? '' : ' notif-item--unread') + '" onclick="markRead(' + n.id + ', this)">' +
            '<div class="notif-item__head">' +
                '<span class="notif-item__type" style="color:' + typeColor + ';background:' + typeBg + '">' + n.type.toUpperCase() + '</span>' +
                unreadLabel +
                '<span class="notif-item__time">' + n.created_at + '</span>' +
            '</div>' +
            '<strong class="notif-item__title">' + n.title + '</strong>' +
            '<p class="notif-item__body">' + n.body + '</p>' +
        '</div>';
    }).join('');
}

function markRead(id, el) {
    if (el && el.classList.contains('notif-item--unread')) {
        el.classList.remove('notif-item--unread');
        fetch('/notifications/' + id + '/read', {
            method: 'POST',
            headers: { 'X-CSRF-TOKEN': '{{ csrf_token() }}', 'Accept': 'application/json' }
        }).then(r => r.json()).then(d => updateBadge(d.unread_count));
    }
}

function markAllRead() {
    profileShowLoader('Обновляем уведомления', 'Отмечаем сообщения прочитанными.');
    fetch('{{ route("notifications.read-all") }}', {
        method: 'POST',
        headers: { 'X-CSRF-TOKEN': '{{ csrf_token() }}', 'Accept': 'application/json' }
    }).then(r => r.json()).then(d => {
        updateBadge(0);
        document.querySelectorAll('.notif-item--unread').forEach(el => el.classList.remove('notif-item--unread'));
        profileHideLoader();
    }).catch(() => profileHideLoader());
}

function updateBadge(count) {
    var badge = document.getElementById('notifBadge');
    if (count > 0) {
        badge.textContent = count > 99 ? '99+' : count;
        badge.style.display = 'flex';
    } else {
        badge.style.display = 'none';
    }
}

// Close panel on outside click
document.addEventListener('click', function(e) {
    var bell = document.getElementById('notifBell');
    var panel = getNotifPanel();
    if (_notifOpen && bell && panel && !bell.contains(e.target) && !panel.contains(e.target)) {
        closeNotifPanel();
    }

    var sidebar = document.querySelector('.profile-sidebar');
    var openBtn = document.querySelector('.profile-menu-open');
    if (
        sidebar &&
        window.matchMedia('(max-width: 980px)').matches &&
        !document.body.classList.contains('profile-sidebar-collapsed') &&
        !sidebar.contains(e.target) &&
        !(openBtn && openBtn.contains(e.target))
    ) {
        setProfileSidebarCollapsed(true);
    }
});

document.addEventListener('keydown', function(e) {
    if (e.key === 'Escape' && _notifOpen) {
        closeNotifPanel();
    }
    if (e.key === 'Escape' && window.matchMedia('(max-width: 980px)').matches) {
        setProfileSidebarCollapsed(true);
    }
});

// Load unread count on page load
initNotifyHub();
initProfilePages();
initProfileSidebar();
window.addEventListener('resize', initProfileSidebar);
loadNotifications();

// ── Telegram linking ──
var _tgPollTimer = null;

function tgStartLink() {
    var btn = document.getElementById('tg-link-btn');
    var overviewBtn = document.getElementById('overview-tg-link-btn');
    var hint = document.getElementById('tg-link-hint');
    var overviewHint = document.getElementById('overview-tg-link-hint');
    if (btn) { btn.disabled = true; btn.textContent = 'Генерация ссылки...'; }
    if (overviewBtn) { overviewBtn.disabled = true; overviewBtn.querySelector('strong').textContent = 'Готовим ссылку...'; }
    profileShowLoader('Готовим Telegram', 'Создаём одноразовую ссылку для подключения.');

    fetch('{{ route("profile.telegram.link-token") }}', {
        method: 'POST',
        headers: {
            'X-CSRF-TOKEN': '{{ csrf_token() }}',
            'Accept': 'application/json',
        }
    })
    .then(r => r.json())
    .then(data => {
        if (!data.deep_link) throw new Error('No deep_link');
        profileHideLoader();
        if (hint) hint.textContent = 'Ссылка готова. Нажмите кнопку справа →';
        if (overviewHint) overviewHint.textContent = 'Ссылка готова. Откройте бота и подтвердите привязку.';
        if (btn) { btn.textContent = 'Открыть бота'; btn.disabled = false; btn.onclick = function() { window.open(data.deep_link, '_blank'); }; }
        if (overviewBtn) {
            overviewBtn.disabled = false;
            overviewBtn.querySelector('strong').textContent = 'Открыть Telegram';
            overviewBtn.onclick = function() { window.open(data.deep_link, '_blank'); };
        }
        _tgPollTimer = setInterval(tgPollStatus, 3000);
    })
    .catch(() => {
        profileHideLoader();
        if (btn) { btn.disabled = false; btn.textContent = 'Подключить Telegram'; }
        if (overviewBtn) { overviewBtn.disabled = false; overviewBtn.querySelector('strong').textContent = 'Подключить канал'; }
    });
}

function tgPollStatus() {
    fetch('{{ route("profile.telegram.status") }}', { headers: { 'Accept': 'application/json' } })
    .then(r => r.json())
    .then(data => {
        if (data.linked) {
            clearInterval(_tgPollTimer);
            location.reload();
        }
    });
}

function tgUnlink() {
    if (!confirm('Отвязать Telegram от профиля?')) return;
    profileShowLoader('Отвязываем Telegram', 'Обновляем настройки уведомлений.');
    fetch('{{ route("profile.telegram.unlink") }}', {
        method: 'DELETE',
        headers: { 'X-CSRF-TOKEN': '{{ csrf_token() }}', 'Accept': 'application/json' }
    })
    .then(r => r.json())
    .then(data => { if (data.ok) location.reload(); else profileHideLoader(); })
    .catch(() => profileHideLoader());
}
</script>
</body>
</html>
