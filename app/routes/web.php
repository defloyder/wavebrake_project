<?php

use App\Http\Controllers\AuthController;
use App\Http\Controllers\AccountRecoveryController;
use App\Http\Controllers\AdminAuthController;
use App\Http\Controllers\AdminCarContactCardController;
use App\Http\Controllers\AdminPanelController;
use App\Http\Controllers\AppLoginController;
use App\Http\Controllers\NodeHealthController;
use App\Http\Controllers\CabinetController;
use App\Http\Controllers\PasswordChangeController;
use App\Http\Controllers\UserWebAuthnController;
use App\Services\CoreApiService;
use App\Models\CarContactCard;
use App\Models\User;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Route;

Route::get('/admin.webmanifest', function () {
    $adminPath = trim(config('app.admin_path', 'admin'), '/');

    return response()->json([
        'name' => 'Auralith Admin',
        'short_name' => 'Auralith Admin',
        'description' => 'Панель управления Auralith',
        'id' => '/' . $adminPath . '/',
        'start_url' => '/' . $adminPath . '/',
        'scope' => '/' . $adminPath . '/',
        'display' => 'standalone',
        'background_color' => '#070d16',
        'theme_color' => '#0f1825',
        'icons' => [
            ['src' => '/images/pwa-192.png', 'sizes' => '192x192', 'type' => 'image/png', 'purpose' => 'any maskable'],
            ['src' => '/images/pwa-512.png', 'sizes' => '512x512', 'type' => 'image/png', 'purpose' => 'any maskable'],
        ],
    ], 200, ['Content-Type' => 'application/manifest+json']);
})->name('admin.manifest');

Route::get('/health', function () {
    return response()->json(['status' => 'ok']);
})->name('health');

Route::get('/', function () {
    $plans = \App\Models\Plan::query()->orderBy('duration_months')->get();
    return view('public-react', [
        'page' => 'landing',
        'bodyClass' => 'home-apple',
        'meta' => [
            'title' => 'Auralith / Ауралит — частный сетевой контур и IT-инфраструктура для бизнеса',
            'description' => 'Auralith помогает организовать управляемое подключение к собственной инфраструктуре и закрывает B2B-задачи: Core-мониторинг, облако, сети, DevOps, безопасность и поддержку.',
            'canonical' => route('home'),
        ],
        'props' => ['plans' => $plans->values()],
    ]);
})->name('home');
Route::get('/dev', function () {
    $plans = \App\Models\Plan::query()->orderBy('duration_months')->get();
    return view('public-react', [
        'page' => 'landing',
        'bodyClass' => 'home-apple',
        'meta' => ['title' => 'Auralith Dev', 'description' => 'Dev-страница Auralith.'],
        'props' => ['plans' => $plans->values(), 'devBrand' => true],
    ]);
})->name('dev.home');
Route::middleware('auth')->get('/dev/profile', [CabinetController::class, 'index'])->name('dev.profile');
Route::get('/dev/admin', function () {
    return redirect('/'.trim(config('app.admin_path', 'admin'), '/'));
})->name('dev.admin');
Route::get('/b2b', fn () => view('public-react', [
    'page' => 'b2b',
    'bodyClass' => 'b2b-page',
    'meta' => [
        'title' => 'Auralith B2B — управляемая IT-инфраструктура для бизнеса',
        'description' => 'Auralith B2B: Core-мониторинг, облачная инфраструктура, корпоративные сети, DevOps, безопасность, внешний IT-отдел и SLA.',
        'canonical' => route('b2b'),
    ],
    'props' => [],
]))->name('b2b');
Route::get('/faq', fn () => view('public-react', [
    'page' => 'faq',
    'meta' => [
        'title' => 'FAQ — Часто задаваемые вопросы | Auralith',
        'description' => 'FAQ Auralith: назначение сервиса, подключение устройств, оплата, отмена и правила допустимого использования.',
        'canonical' => route('faq'),
        'og_type' => 'article',
    ],
    'props' => [],
]))->name('faq');
Route::get('/offer', fn () => view('public-react', [
    'page' => 'offer',
    'meta' => [
        'title' => 'Публичная оферта — Auralith',
        'description' => 'Публичная оферта на оказание услуг сервиса Auralith.',
        'robots' => 'noindex, follow',
    ],
    'props' => [],
]))->name('offer');
Route::get('/private_policy', fn () => view('public-react', [
    'page' => 'privacy',
    'meta' => [
        'title' => 'Политика конфиденциальности — Auralith',
        'description' => 'Политика конфиденциальности сервиса Auralith.',
        'robots' => 'noindex, follow',
    ],
    'props' => [],
]))->name('privacy_policy');
Route::get('/legal', fn () => view('public-react', [
    'page' => 'legal-info',
    'meta' => [
        'title' => 'Правовая информация и реквизиты — Auralith',
        'description' => 'Реквизиты исполнителя, контакты и порядок направления обращений и претензий.',
        'robots' => 'noindex, follow',
    ],
    'props' => [],
]))->name('legal_info');
Route::get('/cookie-policy', fn () => view('public-react', [
    'page' => 'cookie-policy',
    'meta' => [
        'title' => 'Политика использования cookie — Auralith',
        'description' => 'Категории, цели и сроки использования файлов cookie на сайте Auralith.',
        'robots' => 'noindex, follow',
    ],
    'props' => [],
]))->name('cookie_policy');

Route::get('/car/{slug}', function (string $slug) {
    $card = CarContactCard::query()
        ->where('slug', $slug)
        ->where('is_active', true)
        ->first();

    if ($card) {
        return view('car-contact', [
            'contact' => [
                'phone' => $card->phone,
                'phone_e164' => $card->phone_e164,
                'phone_pretty' => $card->phone_pretty,
                'telegram' => $card->telegram,
                'email' => $card->email,
                'whatsapp_phone' => $card->whatsapp_phone ?: $card->phone,
                'accent' => in_array($card->accent_scheme, ['amber', 'violet'], true) ? 'amber' : 'mint',
            ],
            'message' => $card->message,
        ]);
    }

    $contacts = [
        '9332779343' => [
            'phone' => '9332779343',
            'phone_e164' => '+79332779343',
            'phone_pretty' => '+7 933 277-93-43',
            'whatsapp_phone' => '79332779343',
            'telegram' => 'defloyder',
            'email' => 'denizergecher@gmail.com',
            'accent' => 'mint',
        ],
        '9966566669' => [
            'phone' => '9966566669',
            'phone_e164' => '+79966566669',
            'phone_pretty' => '+7 996 656-66-69',
            'whatsapp_phone' => '79966566669',
            'telegram' => 'buffliner',
            'email' => 'buffliner@gmail.com',
            'accent' => 'amber',
        ],
    ];

    abort_unless(isset($contacts[$slug]), 404);

    return view('car-contact', [
        'contact' => $contacts[$slug],
        'message' => 'Здравствуйте! Я по поводу вашей машины.',
    ]);
})->where('slug', '[A-Za-z0-9._~\-]+')->name('car.contact');

Route::get('/sitemap.xml', function() {
    $lastmod = now()->toDateString();
    $urls = [
        ['loc' => route('home'), 'priority' => '1.0', 'changefreq' => 'weekly'],
        ['loc' => route('b2b'), 'priority' => '0.9', 'changefreq' => 'monthly'],
        ['loc' => route('faq'), 'priority' => '0.8', 'changefreq' => 'monthly'],
        ['loc' => route('offer'), 'priority' => '0.3', 'changefreq' => 'yearly'],
        ['loc' => route('privacy_policy'), 'priority' => '0.3', 'changefreq' => 'yearly'],
        ['loc' => route('legal_info'), 'priority' => '0.3', 'changefreq' => 'yearly'],
        ['loc' => route('cookie_policy'), 'priority' => '0.3', 'changefreq' => 'yearly'],
    ];

    $xml = view('sitemap', compact('urls', 'lastmod'))->render();

    return response($xml, 200, ['Content-Type' => 'application/xml']);
});
Route::get('/login', [AuthController::class, 'showLogin'])->name('login');
Route::post('/login', [AuthController::class, 'login'])->name('login.submit');
Route::get('/app-login', [AppLoginController::class, 'show'])->name('app-login.show');
Route::post('/app-login', [AppLoginController::class, 'submit'])->name('app-login.submit');
Route::get('/webauthn/has-credentials', [UserWebAuthnController::class, 'hasCredentials'])->name('webauthn.has');
Route::post('/webauthn/auth/challenge', [UserWebAuthnController::class, 'authChallenge'])->name('webauthn.auth.challenge');
Route::post('/webauthn/auth/verify', [UserWebAuthnController::class, 'authVerify'])->name('webauthn.auth.verify');
Route::get('/forgot-access', [AccountRecoveryController::class, 'showRequest'])->name('account-recovery.request');
Route::post('/forgot-access', [AccountRecoveryController::class, 'request'])
    ->middleware('throttle:5,1')
    ->name('account-recovery.request.submit');
Route::get('/forgot-access/status/{token}', [AccountRecoveryController::class, 'status'])
    ->middleware('throttle:30,1')
    ->name('account-recovery.status');
Route::get('/reset-access/{token}', [AccountRecoveryController::class, 'showReset'])->name('account-recovery.reset.show');
Route::post('/reset-access/{token}', [AccountRecoveryController::class, 'reset'])
    ->middleware('throttle:5,1')
    ->name('account-recovery.reset.submit');
Route::get('/register', [AuthController::class, 'showRegister'])->name('register');
Route::post('/register', [AuthController::class, 'register'])->name('register.submit');
Route::post('/logout', [AuthController::class, 'logout'])->name('logout');

Route::middleware('auth')->group(function (): void {
    Route::get('/profile', [CabinetController::class, 'index'])->name('profile.index');
    Route::get('/profile/devices', [CabinetController::class, 'devices'])->name('profile.devices');
    Route::post('/profile/payments/create', [CabinetController::class, 'createPayment'])->name('profile.payments.create');
    Route::post('/profile/cloudpayments/order', [CabinetController::class, 'createCloudPaymentOrder'])->name('profile.cloudpayments.order');
    Route::post('/profile/promo/apply', [CabinetController::class, 'applyPromo'])->name('profile.promo.apply');
    Route::post('/profile/trial', [CabinetController::class, 'activateTrial'])->name('profile.trial');
    Route::post('/profile/set-password', [CabinetController::class, 'setPassword'])->name('profile.set-password');
    Route::get('/profile/webauthn/status', [UserWebAuthnController::class, 'status'])->name('profile.webauthn.status');
    Route::post('/profile/webauthn/register/challenge', [UserWebAuthnController::class, 'registerChallenge'])->name('profile.webauthn.register.challenge');
    Route::post('/profile/webauthn/register/verify', [UserWebAuthnController::class, 'registerVerify'])->name('profile.webauthn.register.verify');
    Route::delete('/profile/webauthn', [UserWebAuthnController::class, 'deleteAll'])->name('profile.webauthn.delete');
    Route::post('/profile/password-change/request', [PasswordChangeController::class, 'request'])
        ->middleware('throttle:5,1')
        ->name('profile.password-change.request');
    Route::get('/profile/password-change/status/{pwdToken}', [PasswordChangeController::class, 'status'])
        ->middleware('throttle:30,1')
        ->name('profile.password-change.status');
    Route::post('/profile/cancel-subscription', [CabinetController::class, 'cancelSubscription'])->name('profile.cancel-subscription');

    // Notifications

    // Telegram linking
    Route::post('/profile/telegram/link-token', [\App\Http\Controllers\TelegramLinkController::class, 'generateToken'])->name('profile.telegram.link-token');
    Route::get('/profile/telegram/status', [\App\Http\Controllers\TelegramLinkController::class, 'status'])->name('profile.telegram.status');
    Route::delete('/profile/telegram/unlink', [\App\Http\Controllers\TelegramLinkController::class, 'unlink'])->name('profile.telegram.unlink');

    // Notifications
    Route::get('/notifications', [\App\Http\Controllers\NotificationController::class, 'index'])->name('notifications.index');
    Route::post('/notifications/{id}/read', [\App\Http\Controllers\NotificationController::class, 'markRead'])->name('notifications.read');
    Route::post('/notifications/read-all', [\App\Http\Controllers\NotificationController::class, 'markAllRead'])->name('notifications.read-all');

    // Web Push subscriptions
    Route::get('/push/vapid-public-key', [\App\Http\Controllers\PushSubscriptionController::class, 'vapidPublicKey'])->name('push.vapid-key');
    Route::get('/push/status', [\App\Http\Controllers\PushSubscriptionController::class, 'status'])->name('push.status');
    Route::post('/push/subscribe', [\App\Http\Controllers\PushSubscriptionController::class, 'subscribe'])->name('push.subscribe');
    Route::delete('/push/subscribe', [\App\Http\Controllers\PushSubscriptionController::class, 'unsubscribe'])->name('push.unsubscribe');
});

Route::post('/contact', [\App\Http\Controllers\LeadController::class, 'store'])->name('contact.store');

// Telegram login (one-time token from bot)
Route::get('/auth/telegram-login', [\App\Http\Controllers\TelegramAuthController::class, 'login'])->name('auth.telegram-login');
Route::get('/auth/telegram-login/status', [\App\Http\Controllers\TelegramAuthController::class, 'status'])->name('auth.telegram-login.status');
Route::get('/auth/telegram-login/{token}', [\App\Http\Controllers\TelegramAuthController::class, 'login'])
    ->where('token', '[A-Za-z0-9._~\-]+')
    ->name('auth.telegram-login.token');
Route::get('/telegram-login', [\App\Http\Controllers\TelegramAuthController::class, 'login'])->name('auth.telegram-login.alias');
Route::get('/telegram-login/status', [\App\Http\Controllers\TelegramAuthController::class, 'status'])->name('auth.telegram-login.status.alias');
Route::get('/telegram-login/{token}', [\App\Http\Controllers\TelegramAuthController::class, 'login'])
    ->where('token', '[A-Za-z0-9._~\-]+')
    ->name('auth.telegram-login.alias.token');

// Telegram link webhook (called by bot/Core API)
Route::post('/webhook/telegram-link', [\App\Http\Controllers\TelegramLinkController::class, 'handle'])
    ->name('webhook.telegram-link')
    ->withoutMiddleware([\App\Http\Middleware\VerifyCsrfToken::class]);

Route::post('/webhook/telegram-recovery', [AccountRecoveryController::class, 'confirmTelegram'])
    ->name('webhook.telegram-recovery')
    ->withoutMiddleware([\App\Http\Middleware\VerifyCsrfToken::class]);

// Sync webhooks from Core API (no CSRF)
Route::post('/api/webhook/sync-subscription', [\App\Http\Controllers\SyncWebhookController::class, 'syncSubscription'])
    ->name('webhook.sync-subscription')
    ->withoutMiddleware([\App\Http\Middleware\VerifyCsrfToken::class]);

Route::post('/api/webhook/sync-user', [\App\Http\Controllers\SyncWebhookController::class, 'syncUser'])
    ->name('webhook.sync-user')
    ->withoutMiddleware([\App\Http\Middleware\VerifyCsrfToken::class]);
Route::get('/payment/success', [CabinetController::class, 'paymentSuccess'])->name('payment.success');
Route::get('/payment/fail', [CabinetController::class, 'paymentFail'])->name('payment.fail');
Route::post('/payment/webhook', [CabinetController::class, 'paymentWebhook'])->name('payment.webhook')->withoutMiddleware([\App\Http\Middleware\VerifyCsrfToken::class]);

// CloudPayments webhook
Route::post('/payment/cloudpayments/check', [\App\Http\Controllers\CloudPaymentsController::class, 'check'])
    ->name('payment.cloudpayments.check')
    ->withoutMiddleware([\App\Http\Middleware\VerifyCsrfToken::class]);
Route::post('/payment/cloudpayments/pay', [\App\Http\Controllers\CloudPaymentsController::class, 'pay'])
    ->name('payment.cloudpayments.pay')
    ->withoutMiddleware([\App\Http\Middleware\VerifyCsrfToken::class]);
Route::post('/webhook/cloudpayments/pay', [\App\Http\Controllers\CloudPaymentsController::class, 'pay'])
    ->name('webhook.cloudpayments.pay')
    ->withoutMiddleware([\App\Http\Middleware\VerifyCsrfToken::class]);
Route::post('/payment/cloudpayments/fail', [\App\Http\Controllers\CloudPaymentsController::class, 'fail'])
    ->name('payment.cloudpayments.fail')
    ->withoutMiddleware([\App\Http\Middleware\VerifyCsrfToken::class]);
Route::post('/payment/cloudpayments/cancel', [\App\Http\Controllers\CloudPaymentsController::class, 'cancel'])
    ->name('payment.cloudpayments.cancel')
    ->withoutMiddleware([\App\Http\Middleware\VerifyCsrfToken::class]);
Route::post('/payment/cloudpayments/webhook', [\App\Http\Controllers\CloudPaymentsController::class, 'webhook'])
    ->name('payment.cloudpayments.webhook')
    ->withoutMiddleware([\App\Http\Middleware\VerifyCsrfToken::class]);

Route::redirect('/cabinet', '/profile');

Route::prefix(config('app.admin_path', 'admin'))->name('admin.')->group(function (): void {
    Route::get('/login', [AdminAuthController::class, 'showLogin'])->name('login');
    Route::post('/login', [AdminAuthController::class, 'login'])->name('login.submit');

    // WebAuthn authentication (no auth required — happens before login)
    Route::post('/webauthn/auth/challenge', [\App\Http\Controllers\AdminWebAuthnController::class, 'authChallenge'])->name('webauthn.auth.challenge');
    Route::post('/webauthn/auth/verify', [\App\Http\Controllers\AdminWebAuthnController::class, 'authVerify'])->name('webauthn.auth.verify');
    Route::get('/webauthn/has-credentials', [\App\Http\Controllers\AdminWebAuthnController::class, 'hasCredentials'])->name('webauthn.has.public');

    Route::middleware('admin')->group(function (): void {
        Route::get('/', [AdminPanelController::class, 'dashboard'])->name('dashboard');
        Route::get('/car-cards', [AdminCarContactCardController::class, 'index'])->name('car-cards.index');
        Route::get('/car-cards/create', [AdminCarContactCardController::class, 'create'])->name('car-cards.create');
        Route::post('/car-cards', [AdminCarContactCardController::class, 'store'])->name('car-cards.store');
        Route::get('/car-cards/{carCard}', [AdminCarContactCardController::class, 'show'])->name('car-cards.show');
        Route::post('/car-cards/{carCard}/regenerate', [AdminCarContactCardController::class, 'regenerate'])->name('car-cards.regenerate');
        Route::delete('/car-cards/{carCard}', [AdminCarContactCardController::class, 'destroy'])->name('car-cards.destroy');
        Route::put('/client-releases', [AdminPanelController::class, 'updateClientReleases'])->name('client-releases.update');
        Route::get('/settings', [\App\Http\Controllers\AdminSettingsController::class, 'index'])->name('settings.index');
        Route::get('/diagnostics', [AdminPanelController::class, 'diagnostics'])->name('diagnostics');
        Route::get('/settings/push/status', [\App\Http\Controllers\AdminSettingsController::class, 'pushStatus'])->name('settings.push.status');
        Route::post('/settings/push/subscribe', [\App\Http\Controllers\AdminSettingsController::class, 'subscribe'])->name('settings.push.subscribe');
        Route::delete('/settings/push/subscribe', [\App\Http\Controllers\AdminSettingsController::class, 'unsubscribe'])->name('settings.push.unsubscribe');
        Route::post('/settings/push/test', [\App\Http\Controllers\AdminSettingsController::class, 'sendTestNotification'])->name('settings.push.test');
        Route::post('/settings/system-digest/send-now', [\App\Http\Controllers\AdminSettingsController::class, 'sendSystemDigestNow'])->name('settings.digest.send-now');
        Route::put('/settings/system-digest-schedule', [\App\Http\Controllers\AdminSettingsController::class, 'updateDigestSchedule'])->name('settings.digest-schedule.update');
        Route::get('/system', [\App\Http\Controllers\AdminSystemController::class, 'index'])->name('system.index');
        Route::get('/system/checks', [\App\Http\Controllers\AdminSystemController::class, 'checksJson'])->name('system.checks');
        Route::post('/system/tests', [\App\Http\Controllers\AdminSystemController::class, 'runTests'])->name('system.tests');
        Route::post('/logout', [AdminAuthController::class, 'logout'])->name('logout');

        // Notifications broadcast
        Route::post('/notifications/send', [\App\Http\Controllers\AdminNotificationController::class, 'send'])->name('notifications.send');
        Route::delete('/notifications', [\App\Http\Controllers\AdminNotificationController::class, 'destroyMany'])->name('notifications.destroy-many');
        Route::delete('/notifications/{id}', [\App\Http\Controllers\AdminNotificationController::class, 'destroy'])->name('notifications.destroy');

        // Admin logs
        Route::get('/logs', [AdminPanelController::class, 'logs'])->name('logs');

        // Internal polling endpoint for node health metrics
        Route::get('/api/nodes/health', [NodeHealthController::class, 'index'])->name('api.nodes.health');

        // WebAuthn credentials management (requires admin auth)
        Route::post('/webauthn/register/challenge', [\App\Http\Controllers\AdminWebAuthnController::class, 'registerChallenge'])->name('webauthn.register.challenge');
        Route::post('/webauthn/register/verify', [\App\Http\Controllers\AdminWebAuthnController::class, 'registerVerify'])->name('webauthn.register.verify');
        Route::delete('/webauthn/credentials/{id}', [\App\Http\Controllers\AdminWebAuthnController::class, 'deleteCredential'])->name('webauthn.delete');

        // Send personal notification to user — must be BEFORE /{resource}/{id} wildcard
        Route::post('/users/{id}/notify', [\App\Http\Controllers\AdminPanelController::class, 'sendNotification'])->name('users.notify');
        Route::post('/users/{user}/recovery-link', [AccountRecoveryController::class, 'createAdminResetLink'])->name('users.recovery-link');
        Route::get('/users/{user}/core-devices', [AdminPanelController::class, 'userCoreDevices'])->name('users.core-devices');
        Route::get('/users/{user}/active-sessions', [AdminPanelController::class, 'userCoreActiveSessions'])->name('users.active-sessions');
        Route::get('/users/{user}/traffic', [AdminPanelController::class, 'userCoreTraffic'])->name('users.traffic');
        Route::delete('/users/{user}/core-devices/{device}', [AdminPanelController::class, 'deactivateUserDevice'])->name('users.core-devices.deactivate');
        Route::post('/users/{user}/core-devices/{device}/reactivate', [AdminPanelController::class, 'reactivateUserDevice'])->name('users.core-devices.reactivate');
        Route::get('/support/app-client', [AdminPanelController::class, 'supportAppClient'])->name('support.app-client');
        Route::post('/support/app-client/{supportCode}/request-diagnostics', [AdminPanelController::class, 'requestAppClientDiagnostics'])->name('support.app-client.request-diagnostics');
        Route::get('/support/app-client/{supportCode}/diagnostics', [AdminPanelController::class, 'appClientDiagnostics'])->name('support.app-client.diagnostics');

        Route::get('/{resource}', [AdminPanelController::class, 'index'])->name('resource.index');
        Route::get('/{resource}/create', [AdminPanelController::class, 'create'])->name('resource.create');
        Route::post('/{resource}', [AdminPanelController::class, 'store'])->name('resource.store');
        Route::get('/{resource}/{id}', [AdminPanelController::class, 'show'])->name('resource.show');
        Route::get('/{resource}/{id}/edit', [AdminPanelController::class, 'edit'])->name('resource.edit');
        Route::put('/{resource}/{id}', [AdminPanelController::class, 'update'])->name('resource.update');
        Route::delete('/{resource}/{id}', [AdminPanelController::class, 'destroy'])->name('resource.destroy');
    });
});

Route::get('/sub/{token}/connect', function (string $token) {
    $coreResponse = app(CoreApiService::class)->publicGetRaw("/sub/{$token}/connect");
    if ($coreResponse) {
        return response($coreResponse->body(), $coreResponse->status())
            ->header('Content-Type', $coreResponse->header('Content-Type', 'text/html; charset=UTF-8'));
    }

    $user = User::query()->where('token', $token)->firstOrFail();
    $subscription = $user->subscriptions()
        ->with(['node', 'plan'])
        ->whereIn('status', ['active', 'trial', 'expiring_soon'])
        ->where(function ($query): void {
            $query->whereNull('ends_at')
                ->orWhere('ends_at', '>', now());
        })
        ->latest()
        ->firstOrFail();

    $nodeName = $subscription->node?->name ?? 'NL1';
    $subscriptionUrl = route('sub.content', ['token' => $token]);
    $encodedUrl = rawurlencode($subscriptionUrl);

    return view('public-react', [
        'page' => 'subscription-import',
        'bodyClass' => 'subscription-import-page',
        'meta' => ['title' => 'Auralith | Импорт подписки', 'robots' => 'noindex, nofollow'],
        'props' => [
        'subscriptionUrl' => $subscriptionUrl,
        'rawUrl' => route('sub.content', ['token' => $token, 'raw' => 1]),
        'nodeName' => $nodeName,
        'apps' => [
            [
                'name' => 'Karing',
                'href' => "karing://install-config?url={$encodedUrl}",
                'ios' => 'https://apps.apple.com/search?term=Karing',
                'android' => 'https://play.google.com/store/search?q=Karing&c=apps',
            ],
            [
                'name' => 'Hiddify',
                'href' => "hiddify://import/{$subscriptionUrl}#Auralith",
                'ios' => 'https://apps.apple.com/search?term=Hiddify',
                'android' => 'https://play.google.com/store/search?q=Hiddify&c=apps',
            ],
        ],
        ],
    ]);
})->name('sub.connect');

Route::get('/sub/{token}/qr', function (string $token) {
    $coreResponse = app(CoreApiService::class)->publicGetRaw("/sub/{$token}/qr");
    abort_if(! $coreResponse, 404);

    return response($coreResponse->body(), $coreResponse->status())
        ->header('Content-Type', $coreResponse->header('Content-Type', 'image/png'));
})->name('sub.qr');

Route::get('/sub/{token}', function (Request $request, string $token) {
    $user = User::query()->where('token', $token)->firstOrFail();
    $subscription = $user->subscriptions()
        ->with(['node', 'plan'])
        ->whereIn('status', ['active', 'trial', 'expiring_soon'])
        ->where(function ($query): void {
            $query->whereNull('ends_at')
                ->orWhere('ends_at', '>', now());
        })
        ->latest()
        ->firstOrFail();

    $nodeName = $subscription->node?->name ?? 'NL1';
    $nodeIp = $subscription->node?->ip ?? '127.0.0.1';
    $content = "vless://{$user->client_uuid}@{$nodeIp}:443?security=reality&fp=chrome&sni=auralith.app#Auralith-{$nodeName}";
    $accept = strtolower((string) $request->header('Accept', ''));

    if (! $request->boolean('raw') && str_contains($accept, 'text/html')) {
        return redirect()->route('sub.connect', ['token' => $token]);
    }

    return response(base64_encode($content), 200, ['Content-Type' => 'text/plain']);
})->name('sub.content');

Route::get('/sub/{token}/status', function (string $token) {
    $coreStatus = app(CoreApiService::class)->getSubStatus($token);
    if (is_array($coreStatus)) {
        return response()->json($coreStatus);
    }

    $user = User::query()->where('token', $token)->firstOrFail();
    $subscription = $user->subscriptions()
        ->with(['node', 'plan'])
        ->whereIn('status', ['active', 'trial', 'expiring_soon'])
        ->where(function ($query): void {
            $query->whereNull('ends_at')
                ->orWhere('ends_at', '>', now());
        })
        ->latest()
        ->first();

    if (! $subscription) {
        return response()->json([
            'is_active' => false,
            'is_frozen' => false,
            'is_unlimited' => false,
            'expires_at' => null,
            'days_left' => 0,
            'plan_id' => null,
            'node_name' => null,
            'frozen_until' => null,
        ]);
    }

    $isUnlimited = $subscription->ends_at === null;
    $isActive = true;
    $daysLeft = $subscription->ends_at ? max(0, now()->diffInDays($subscription->ends_at, false)) : 0;

    return response()->json([
        'is_active' => $isActive,
        'is_frozen' => false,
        'is_unlimited' => $isUnlimited,
        'expires_at' => optional($subscription->ends_at)->toIso8601String(),
        'days_left' => $daysLeft,
        'plan_id' => $subscription->plan_id,
        'node_name' => $subscription->node?->name,
        'frozen_until' => null,
    ]);
})->name('sub.status');
