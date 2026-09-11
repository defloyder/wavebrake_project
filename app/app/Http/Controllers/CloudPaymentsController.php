<?php

namespace App\Http\Controllers;

use App\Models\CpOrder;
use App\Models\FkOrder;
use App\Models\Node;
use App\Models\Subscription;
use App\Services\AdminAlertService;
use App\Services\CoreApiService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;

class CloudPaymentsController extends Controller
{
    public function __construct(
        private readonly CoreApiService $core,
        private readonly AdminAlertService $alerts,
    ) {}

    public function check(Request $request): JsonResponse
    {
        if (! $this->verifySignature($request)) {
            Log::warning('CloudPayments Check: invalid signature', ['ip' => $request->ip()]);
            return $this->cpResponse(13);
        }

        $data = $this->payload($request);
        $order = $this->findOrder($data);

        if (! $order) {
            return $this->cpResponse(10);
        }

        if ((string) $order->user_id !== (string) ($data['AccountId'] ?? '')) {
            return $this->cpResponse(11);
        }

        if (! $this->sameAmount($order->amount, (float) ($data['Amount'] ?? 0))) {
            return $this->cpResponse(12);
        }

        if ($order->currency !== ($data['Currency'] ?? 'RUB')) {
            return $this->cpResponse(13);
        }

        if (! in_array($order->status, ['pending', 'failed'], true)) {
            return $this->cpResponse(20);
        }

        return $this->cpResponse(0);
    }

    public function pay(Request $request): JsonResponse
    {
        if (! $this->verifySignature($request)) {
            Log::warning('CloudPayments Pay: invalid signature', ['ip' => $request->ip()]);
            return $this->cpResponse(13);
        }

        return $this->handlePaidPayment($request);
    }

    public function fail(Request $request): JsonResponse
    {
        if (! $this->verifySignature($request)) {
            Log::warning('CloudPayments Fail: invalid signature', ['ip' => $request->ip()]);
            return $this->cpResponse(13);
        }

        $data = $this->payload($request);
        $order = $this->findOrder($data);

        if ($order && $order->status !== 'paid') {
            $order->update([
                'transaction_id' => $data['TransactionId'] ?? $order->transaction_id,
                'status' => 'failed',
                'payment_method' => $data['PaymentMethod'] ?? $order->payment_method,
                'raw_payload' => $data,
                'failed_at' => now(),
            ]);

            $this->sendPaymentEventNotification($order);
        }

        return $this->cpResponse(0);
    }

    public function cancel(Request $request): JsonResponse
    {
        if (! $this->verifySignature($request)) {
            Log::warning('CloudPayments Cancel: invalid signature', ['ip' => $request->ip()]);
            return $this->cpResponse(13);
        }

        $data = $this->payload($request);
        $order = $this->findOrder($data);

        if ($order && $order->status !== 'paid') {
            $order->update([
                'transaction_id' => $data['TransactionId'] ?? $order->transaction_id,
                'status' => 'cancelled',
                'payment_method' => $data['PaymentMethod'] ?? $order->payment_method,
                'raw_payload' => $data,
                'failed_at' => now(),
            ]);

            $this->sendPaymentEventNotification($order);
        }

        return $this->cpResponse(0);
    }

    public function webhook(Request $request): JsonResponse
    {
        return $this->pay($request);
    }

    private function handlePaidPayment(Request $request): JsonResponse
    {
        $data = $this->payload($request);
        $order = $this->findOrder($data);

        if (! $order) {
            Log::error('CloudPayments Pay: order not found', ['payload' => $data]);
            return $this->cpResponse(10);
        }

        if (! $this->sameAmount($order->amount, (float) ($data['Amount'] ?? 0))) {
            Log::error('CloudPayments Pay: amount mismatch', [
                'invoice_id' => $order->invoice_id,
                'expected' => $order->amount,
                'actual' => $data['Amount'] ?? null,
            ]);
            return $this->cpResponse(12);
        }

        if ($order->currency !== ($data['Currency'] ?? 'RUB')) {
            return $this->cpResponse(13);
        }

        if ($order->status === 'paid') {
            return $this->cpResponse(0);
        }

        DB::transaction(function () use ($order, $data): void {
            $order->update([
                'transaction_id' => $data['TransactionId'] ?? $order->transaction_id,
                'status' => 'paid',
                'payment_method' => $data['PaymentMethod'] ?? 'cloudpayments',
                'raw_payload' => $data,
                'paid_at' => $order->paid_at ?? now(),
            ]);

            FkOrder::query()->updateOrCreate(
                ['order_id' => $order->invoice_id],
                [
                    'user_id' => $order->user_id,
                    'plan_id' => $order->plan_id,
                    'amount' => $order->amount,
                    'currency' => $order->currency,
                    'payment_method' => 0,
                    'status' => 'paid',
                    'paid_at' => $order->paid_at ?? now(),
                ]
            );

            $this->activateLocalSubscription($order);

            if ($order->promo_code_id) {
                $order->promoCode()->increment('used_count');
            }
        });

        $this->sendPaymentEventNotification($order);

        $this->extendCoreSubscription($order);

        return $this->cpResponse(0);
    }

    private function activateLocalSubscription(CpOrder $order): void
    {
        $plan = $order->plan()->firstOrFail();
        $startsAt = now();
        $existing = Subscription::query()->where('user_id', $order->user_id)->first();

        if ($existing?->ends_at && $existing->ends_at->isFuture()) {
            $startsAt = $existing->ends_at;
        }

        $endsAt = (clone $startsAt)->addMonthsNoOverflow((int) $plan->duration_months);
        $nodeId = $existing?->node_id
            ?? Node::query()->where('is_active', true)->orderBy('id')->value('id')
            ?? Node::query()->orderBy('id')->value('id');

        Subscription::query()->updateOrCreate(
            ['user_id' => $order->user_id],
            [
                'plan_id' => $plan->id,
                'node_id' => $nodeId,
                'status' => 'active',
                'starts_at' => $existing?->starts_at ?? now(),
                'ends_at' => $endsAt,
                'last_sync_at' => now(),
            ]
        );
    }

    private function extendCoreSubscription(CpOrder $order): void
    {
        try {
            $plan = $order->plan()->first();
            if (! $plan) {
                return;
            }

            $user = $order->user()->first();
            if (! $user) {
                return;
            }

            $days = max(1, (int) round((int) $plan->duration_months * 30.4375));
            $result = $this->core->adminExtendUserSubscription($user, $days);

            if (! $result) {
                Log::warning('CloudPayments Pay: Core subscription extension failed', [
                    'invoice_id' => $order->invoice_id,
                    'user_id' => $order->user_id,
                    'core_user_id' => $user->core_user_id,
                    'telegram_id' => $user->telegram_id,
                    'days' => $days,
                ]);
            }
        } catch (\Throwable $e) {
            Log::error('CloudPayments Pay: Core subscription extension exception', [
                'invoice_id' => $order->invoice_id,
                'error' => $e->getMessage(),
            ]);
        }
    }

    private function sendPaymentEventNotification(CpOrder $order): void
    {
        $this->alerts->sendOrderEvent($order->refresh());
    }

    private function findOrder(array $data): ?CpOrder
    {
        $invoiceId = $data['InvoiceId'] ?? $data['externalId'] ?? null;

        if (! $invoiceId) {
            return null;
        }

        return CpOrder::query()->where('invoice_id', (string) $invoiceId)->first();
    }

    private function payload(Request $request): array
    {
        $data = $request->all();

        if (isset($data['Data']) && is_string($data['Data'])) {
            $decoded = json_decode($data['Data'], true);
            if (json_last_error() === JSON_ERROR_NONE) {
                $data['Data'] = $decoded;
            }
        }

        return $data;
    }

    private function sameAmount(float $expected, float $actual): bool
    {
        return abs(round($expected, 2) - round($actual, 2)) < 0.01;
    }

    private function cpResponse(int $code): JsonResponse
    {
        return response()->json(['code' => $code]);
    }

    private function verifySignature(Request $request): bool
    {
        $secret = config('services.cloudpayments.api_secret');

        if (! $secret) {
            return true;
        }

        $headers = array_filter([
            $request->header('Content-HMAC'),
            $request->header('X-Content-HMAC'),
        ]);

        if (! $headers) {
            return false;
        }

        $body = $request->getContent();
        $candidates = array_unique([$body, urldecode($body)]);

        foreach ($candidates as $candidate) {
            $expected = base64_encode(hash_hmac('sha256', $candidate, $secret, true));

            foreach ($headers as $header) {
                if (hash_equals($expected, $header)) {
                    return true;
                }
            }
        }

        return false;
    }
}
