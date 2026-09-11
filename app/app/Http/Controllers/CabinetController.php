<?php

namespace App\Http\Controllers;

use App\Services\CoreApiService;
use App\Services\ClientReleaseService;
use App\Models\CpOrder;
use App\Models\PasswordChangeRequest;
use App\Models\Plan;
use App\Models\PromoCode;
use App\Models\Subscription;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Arr;
use Illuminate\Support\Str;
use Illuminate\View\View;
use App\Models\User;

class CabinetController extends Controller
{
    // Тарифы из Core API
    private const PLANS = [
        1  => ['name' => '1 месяц',  'days' => 30,  'price' => 169.0],
        3  => ['name' => '3 месяца', 'days' => 90,  'price' => 449.0],
        12 => ['name' => '1 год',    'days' => 365, 'price' => 1490.0],
    ];

    // Freekassa payment method IDs
    private const PAYMENT_METHODS = [
        36 => 'Карта РФ',
        44 => 'СБП QR',
        43 => 'СберПэй',
    ];

    public function __construct(
        private readonly CoreApiService $core,
        private readonly ClientReleaseService $clientReleases,
    ) {}

    // ──────────────────────────────────────────────────────────────
    // Profile page
    // ──────────────────────────────────────────────────────────────
    public function index(): View
    {
        $user  = Auth::user();
        $token = $user->token;

        // Получаем статус подписки из Core API только если Telegram подключён
        $subStatus = null;
        if ($token && $user->telegram_id) {
            $subStatus = $this->core->getSubStatus($token);

            // Если пользователь не найден в Core API - синхронизируем
            if ($subStatus === null) {
                $this->syncUserToCoreApi($user);
                // Повторно запрашиваем статус после синхронизации
                $subStatus = $this->core->getSubStatus($token);
            }
        }

        $isActive    = $subStatus['is_active'] ?? false;
        $isUnlimited = (bool) ($subStatus['is_unlimited'] ?? false);
        $expiresAt   = $subStatus['expires_at'] ?? null;
        $planId      = $subStatus['plan_id'] ?? null;
        $nodeName    = $subStatus['node_name'] ?? null;

        $localSub = Subscription::query()
            ->where('user_id', $user->id)
            ->whereIn('status', ['active', 'trial'])
            ->where(function ($query): void {
                $query->whereNull('ends_at')
                    ->orWhere('ends_at', '>', now());
            })
            ->with(['plan', 'node'])
            ->latest()
            ->first();

        if (! $isActive && $localSub) {
            $isActive = true;
            $isUnlimited = $localSub->ends_at === null;
            $expiresAt = $localSub->ends_at;
            $planId = $localSub->plan_id;
            $nodeName = $localSub->node?->name;
        }

        $hasCpSubscription = ! empty($subStatus['cp_subscription_id'] ?? null);
        $hasRecurringSubscription = $isActive && $hasCpSubscription;

        // Recalculate daysLeft using ceil so "23h 55m left" shows as 1 day, not 0
        $daysLeft = null;
        if ($isUnlimited) {
            $daysLeft = null;
        } elseif ($expiresAt) {
            $diff = now()->diffInSeconds(\Carbon\Carbon::parse($expiresAt), false);
            $daysLeft = $diff > 0 ? (int) ceil($diff / 86400) : ($diff >= 0 ? 0 : -1);
        } elseif (isset($subStatus['days_left']) && $subStatus['days_left'] !== null) {
            $daysLeft = (int) $subStatus['days_left'];
        }

        // Resolve plan name from DB, fallback to local subscription, then hardcoded map
        $planName = null;
        if ($planId) {
            $planName = Plan::query()->find($planId)?->name;
        }
        if (! $planName && $localSub) {
            $planName = $localSub?->plan?->name;
        }
        if (! $planName) {
            $planName = self::PLANS[$planId]['name'] ?? null;
        }
        if ($isUnlimited && ! $planName) {
            $planName = 'Безлимитная';
        }

        // Determine if subscription is trial
        $isTrial = false;
        if ($user->id) {
            $isTrial = Subscription::query()
                ->where('user_id', $user->id)
                ->where('status', 'trial')
                ->exists();
        }

        $expiryState = match (true) {
            $isUnlimited => 'ok',
            $daysLeft === null  => 'none',
            $daysLeft < 0      => 'expired',
            $daysLeft <= 2     => 'critical',
            $daysLeft <= 7     => 'warn',
            default            => 'ok',
        };

        $bonusData = null;
        $referralData = null;
        if ($token && $user->telegram_id) {
            $bonusData = $this->core->getBonus($token);
            $referralData = $this->core->getReferral($token);
        }

        $passwordChangeRequest = null;
        if ($user->has_password) {
            $passwordChangeRequest = PasswordChangeRequest::query()
                ->where('user_id', $user->id)
                ->whereIn('status', ['pending', 'confirmed'])
                ->whereNull('used_at')
                ->where(function ($query): void {
                    $query->where('expires_at', '>', now())
                        ->orWhere('confirmed_at', '>', now()->subMinutes(10));
                })
                ->latest()
                ->first();
        }

        $windowsRelease = $this->clientReleases->stableWindowsRelease();

        return view('cabinet', [
            'user'           => $user,
            'plans'          => self::PLANS,
            'dbPlans'        => Plan::query()->orderBy('duration_months')->get(),
            'isActive'       => $isActive,
            'isUnlimited'    => $isUnlimited,
            'expiresAt'      => $expiresAt,
            'daysLeft'       => $daysLeft,
            'expiryState'    => $expiryState,
            'planId'         => $planId,
            'planName'       => $planName,
            'isTrial'        => $isTrial,
            'nodeName'       => $nodeName,
            'paymentMethods' => self::PAYMENT_METHODS,
            'hasPassword'    => (bool) $user->has_password,
            'bonusData'      => $bonusData,
            'referralData'   => $referralData,
            'passwordChangeRequest' => $passwordChangeRequest,
            'hasRecurringSubscription' => $hasRecurringSubscription,
            'windowsRelease' => $windowsRelease,
        ]);
    }

    public function devices(): JsonResponse
    {
        /** @var User $user */
        $user = Auth::user();
        $coreUserId = $user->core_user_id ? (int) $user->core_user_id : (int) $user->id;
        $result = $this->core->adminUserDevices($coreUserId);
        $devices = $this->normalizeCoreList($result, ['devices', 'items', 'data']);

        return response()->json([
            'ok' => $result !== null,
            'devices' => collect($devices ?? [])
                ->filter(fn ($device) => is_array($device))
                ->map(fn (array $device) => $this->normalizeClientDevice($device))
                ->values(),
            'error' => $result === null ? $this->core->lastErrorMessage() : null,
        ], $result !== null ? 200 : 502);
    }

    private function normalizeClientDevice(array $device): array
    {
        $rxBytes = $this->firstNumeric($device, ['rx_bytes', 'download_bytes', 'downloaded_bytes', 'down_bytes']);
        $txBytes = $this->firstNumeric($device, ['tx_bytes', 'upload_bytes', 'uploaded_bytes', 'up_bytes']);
        $totalBytes = $this->firstNumeric($device, ['traffic_bytes', 'total_bytes', 'bytes_total']);
        if ($totalBytes === null && ($rxBytes !== null || $txBytes !== null)) {
            $totalBytes = (float) ($rxBytes ?? 0) + (float) ($txBytes ?? 0);
        }

        return [
            'id' => Arr::get($device, 'id'),
            'display_name' => Arr::get($device, 'display_name')
                ?? Arr::get($device, 'device_name')
                ?? Arr::get($device, 'name')
                ?? ('Устройство #' . (Arr::get($device, 'id') ?? '')),
            'platform' => Arr::get($device, 'platform')
                ?? Arr::get($device, 'os')
                ?? Arr::get($device, 'client_platform')
                ?? 'unknown',
            'app_version' => Arr::get($device, 'app_version') ?? Arr::get($device, 'version'),
            'is_active' => filter_var(Arr::get($device, 'is_active', true), FILTER_VALIDATE_BOOL),
            'last_seen' => Arr::get($device, 'last_seen')
                ?? Arr::get($device, 'last_seen_at')
                ?? Arr::get($device, 'updated_at'),
            'fetch_count' => (int) (Arr::get($device, 'fetch_count') ?? 0),
            'traffic_bytes' => $totalBytes,
        ];
    }

    private function normalizeCoreList(?array $payload, array $keys): ?array
    {
        if ($payload === null) {
            return null;
        }

        foreach ($keys as $key) {
            $value = Arr::get($payload, $key);
            if (is_array($value)) {
                return $value;
            }
        }

        return array_is_list($payload) ? $payload : null;
    }

    private function firstNumeric(array $data, array $keys): int|float|null
    {
        foreach ($keys as $key) {
            $value = Arr::get($data, $key);
            if (is_numeric($value)) {
                return (float) $value;
            }
        }

        return null;
    }

    /**
     * Sync user data to Core API database.
     * Creates or updates user in Core API with Laravel user's token and client_uuid.
     */
    private function syncUserToCoreApi(User $user): void
    {
        try {
            Http::timeout(5)
                ->acceptJson()
                ->asJson()
                ->post(config('services.core.url') . '/webhook/sync-user', [
                    'telegram_id' => $user->telegram_id,
                    'username'    => $user->name,
                    'token'       => $user->token,
                    'client_uuid' => $user->client_uuid,
                ]);
        } catch (\Throwable $e) {
            Log::error("Failed to sync user to Core API: " . $e->getMessage());
        }
    }

    // ──────────────────────────────────────────────────────────────
    // Create payment via Core API → Freekassa
    // ──────────────────────────────────────────────────────────────
    public function createPayment(Request $request): RedirectResponse
    {
        $data = $request->validate([
            'plan_id'        => ['required', 'integer', 'in:1,3,12'],
            'payment_method' => ['required', 'integer', 'in:36,44,43'],
            'promocode'      => ['nullable', 'string', 'max:64'],
        ]);

        $user  = Auth::user();
        $token = $user->token;

        if (! $token) {
            return back()->withErrors(['plan_id' => 'Токен пользователя не найден.']);
        }

        $result = $this->core->createPayment(
            token:         $token,
            planId:        (int) $data['plan_id'],
            paymentMethod: (int) $data['payment_method'],
            promocode:     $data['promocode'] ?? null,
        );

        if (! $result || empty($result['payment_url'])) {
            return back()->withErrors(['plan_id' => 'Не удалось создать платёж. Попробуйте позже.']);
        }

        return redirect()->away($result['payment_url']);
    }

    // ──────────────────────────────────────────────────────────────
    // Apply promo code (free_days type)
    // ──────────────────────────────────────────────────────────────
    public function createCloudPaymentOrder(Request $request): JsonResponse
    {
        $data = $request->validate([
            'plan_id' => ['required', 'integer', 'exists:plans,id'],
            'promocode' => ['nullable', 'string', 'max:64'],
        ]);

        $user = Auth::user();
        $plan = Plan::query()->findOrFail($data['plan_id']);
        $publicId = config('services.cloudpayments.public_id');

        if (! $publicId) {
            return response()->json([
                'message' => 'CloudPayments is not configured.',
            ], 422);
        }

        $originalAmount = round((float) $plan->price_rub, 2);
        $promoCode = null;
        $discount = 0.0;

        if (! empty($data['promocode'])) {
            $promoCode = PromoCode::query()
                ->whereRaw('LOWER(code) = ?', [mb_strtolower($data['promocode'])])
                ->first();

            if (! $promoCode || ! $promoCode->isValid()) {
                return response()->json(['message' => 'Промокод недействителен или истёк.'], 422);
            }

            if ($promoCode->type === 'duration_days') {
                $invoiceId = 'PROMO-' . now()->format('YmdHis') . '-' . Str::upper(Str::random(8));

                CpOrder::query()->create([
                    'invoice_id' => $invoiceId,
                    'user_id' => $user->id,
                    'plan_id' => $plan->id,
                    'promo_code_id' => $promoCode->id,
                    'promo_code' => $promoCode->code,
                    'amount' => 0,
                    'discount_amount' => $originalAmount,
                    'original_amount' => $originalAmount,
                    'currency' => 'RUB',
                    'status' => 'paid',
                    'payment_method' => 'promo',
                    'description' => 'Promo subscription - ' . $promoCode->code,
                    'paid_at' => now(),
                ]);

                $this->activatePromoSubscription($user, $plan, max(1, (int) round($promoCode->value)));
                $promoCode->increment('used_count');

                return response()->json([
                    'free' => true,
                    'order' => [
                        'invoice_id' => $invoiceId,
                        'amount' => 0,
                        'original_amount' => $originalAmount,
                        'discount_amount' => $originalAmount,
                        'currency' => 'RUB',
                        'description' => 'Promo subscription - ' . $promoCode->code,
                    ],
                ]);
            }

            $discount = $promoCode->discountFor($originalAmount);
        }

        $amount = round(max(1, $originalAmount - $discount), 2);
        $invoiceId = 'CP-' . now()->format('YmdHis') . '-' . Str::upper(Str::random(8));
        $description = 'Auralith Access - ' . $plan->name;

        CpOrder::query()->create([
            'invoice_id' => $invoiceId,
            'user_id' => $user->id,
            'plan_id' => $plan->id,
            'promo_code_id' => $promoCode?->id,
            'promo_code' => $promoCode?->code,
            'amount' => $amount,
            'discount_amount' => $discount,
            'original_amount' => $originalAmount,
            'currency' => 'RUB',
            'status' => 'pending',
            'payment_method' => 'cloudpayments',
            'description' => $description,
        ]);

        $options = [
            'publicTerminalId' => $publicId,
            'publicId' => $publicId,
            'paymentSchema' => 'Single',
            'description' => $description,
            'amount' => $amount,
            'currency' => 'RUB',
            'accountId' => (string) $user->id,
            'externalId' => $invoiceId,
            'invoiceId' => $invoiceId,
            'skin' => 'modern',
            'culture' => 'ru-RU',
            'emailBehavior' => 'Required',
            'retryPayment' => false,
            'items' => [[
                'id' => 'plan-' . $plan->id,
                'name' => $description,
                'count' => 1,
                'price' => $amount,
            ]],
            'metadata' => [
                'plan_id' => $plan->id,
                'user_id' => $user->id,
                'token' => $user->token,
                'promocode' => $promoCode?->code,
            ],
            'data' => [
                'plan_id' => $plan->id,
                'user_id' => $user->id,
                'token' => $user->token,
                'promocode' => $promoCode?->code,
            ],
            'successRedirectUrl' => route('payment.success'),
            'failRedirectUrl' => route('payment.fail'),
        ];

        $receipt = $this->cloudPaymentsReceipt($plan, $amount, $user);
        if ($receipt) {
            $options['receipt'] = $receipt;
        }

        return response()->json([
            'order' => [
                'invoice_id' => $invoiceId,
                'amount' => $amount,
                'original_amount' => $originalAmount,
                'discount_amount' => $discount,
                'currency' => 'RUB',
                'description' => $description,
            ],
            'widget' => $options,
        ]);
    }

    private function cloudPaymentsReceipt(Plan $plan, float $amount, User $user): ?array
    {
        if (! config('services.cloudpayments.receipt.enabled')) {
            return null;
        }

        return [
            'items' => [[
                'id' => 'plan-' . $plan->id,
                'label' => 'Подписка Auralith - ' . $plan->name,
                'price' => $amount,
                'quantity' => 1.00,
                'amount' => $amount,
                'vat' => config('services.cloudpayments.receipt.vat'),
                'method' => config('services.cloudpayments.receipt.method'),
                'object' => config('services.cloudpayments.receipt.object'),
                'measurementUnit' => 'шт',
            ]],
            'calculationPlace' => config('services.cloudpayments.receipt.calculation_place'),
            'taxationSystem' => config('services.cloudpayments.receipt.taxation_system'),
            'customerInfo' => $user->name ?: $user->username,
            'isBso' => false,
            'amounts' => [
                'electronic' => $amount,
                'advancePayment' => 0.00,
                'credit' => 0.00,
                'provision' => 0.00,
            ],
        ];
    }

    private function activatePromoSubscription(User $user, Plan $plan, int $days): void
    {
        $startsAt = now();
        $existing = Subscription::query()->where('user_id', $user->id)->first();

        if ($existing?->ends_at && $existing->ends_at->isFuture()) {
            $startsAt = $existing->ends_at;
        }

        Subscription::query()->updateOrCreate(
            ['user_id' => $user->id],
            [
                'plan_id' => $plan->id,
                'node_id' => $existing?->node_id,
                'status' => 'active',
                'starts_at' => $existing?->starts_at ?? now(),
                'ends_at' => (clone $startsAt)->addDays($days),
                'last_sync_at' => now(),
            ]
        );
    }

    public function applyPromo(Request $request): RedirectResponse
    {
        $data = $request->validate([
            'code' => ['required', 'string', 'max:64'],
        ]);

        $token = Auth::user()->token;

        if (! $token) {
            return back()->withErrors(['code' => 'Токен пользователя не найден.']);
        }

        $result = $this->core->applyPromo($token, $data['code']);

        if (! $result) {
            return back()->withErrors(['code' => 'Промокод недействителен или уже использован.']);
        }

        $days = $result['days_added'] ?? 0;
        return redirect()->route('profile.index')
            ->with('success', "Промокод применён! Добавлено {$days} дней.");
    }

    // ──────────────────────────────────────────────────────────────
    // Activate trial
    // ──────────────────────────────────────────────────────────────
    public function activateTrial(): RedirectResponse
    {
        $token = Auth::user()->token;

        if (! $token) {
            return back()->withErrors(['trial' => 'Токен пользователя не найден.']);
        }

        $result = $this->core->activateTrial($token);

        if (! $result) {
            return back()->with('error', 'Пробный период недоступен или уже использован.');
        }

        return redirect()->route('profile.index')
            ->with('success', 'Пробный период на 3 дня активирован!');
    }

    // ──────────────────────────────────────────────────────────────
    // Payment callbacks (redirects from Freekassa)
    // ──────────────────────────────────────────────────────────────
    public function setPassword(Request $request): RedirectResponse
    {
        $data = $request->validate([
            'password' => ['required', 'string', 'min:8', 'confirmed'],
            'password_change_token' => ['nullable', 'uuid'],
        ]);

        $user = Auth::user();

        if ($user->has_password) {
            $passwordChange = PasswordChangeRequest::query()
                ->where('user_id', $user->id)
                ->where('pwd_token', $data['password_change_token'] ?? '')
                ->where('status', 'confirmed')
                ->whereNull('used_at')
                ->where(function ($query): void {
                    $query->where('expires_at', '>', now())
                        ->orWhere('confirmed_at', '>', now()->subMinutes(10));
                })
                ->first();

            if (! $passwordChange) {
                return back()->with('error', 'Подтвердите смену пароля в Telegram и попробуйте снова.');
            }
        }

        $user->password = \Illuminate\Support\Facades\Hash::make($data['password']);
        $user->has_password = true;
        $user->save();

        if (isset($passwordChange)) {
            $passwordChange->forceFill(['used_at' => now()])->save();
        }

        return redirect()->route('profile.index')
            ->with('success', 'Пароль установлен. Теперь вы можете входить по логину ' . $user->username . ' и паролю.');
    }

    public function cancelSubscription(Request $request): JsonResponse
    {
        $user = Auth::user();
        $token = $user->token;

        if (! $token) {
            return response()->json([
                'ok' => false,
                'message' => 'Не удалось отменить, обратитесь в поддержку.',
            ], 422);
        }

        $result = $this->core->cancelCloudPaymentsSubscription($token);

        if (($result['ok'] ?? false) === true) {
            return response()->json([
                'ok' => true,
                'message' => 'Подписка отменена.',
            ]);
        }

        return response()->json([
            'ok' => false,
            'message' => 'Не удалось отменить, обратитесь в поддержку.',
        ], 502);
    }

    public function paymentSuccess(): RedirectResponse
    {
        return redirect()->route('profile.index')
            ->with('success', 'Оплата получена. Подписка будет активирована в течение нескольких минут.');
    }

    public function paymentFail(): RedirectResponse
    {
        return redirect()->route('profile.index')
            ->with('error', 'Оплата не прошла. Попробуйте ещё раз или выберите другой способ оплаты.');
    }
}
