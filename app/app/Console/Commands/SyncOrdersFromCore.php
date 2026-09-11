<?php

namespace App\Console\Commands;

use App\Models\CpOrder;
use App\Models\FkOrder;
use App\Models\Plan;
use App\Models\User;
use App\Services\AdminAlertService;
use App\Services\CoreApiService;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Schema;

class SyncOrdersFromCore extends Command
{
    protected $signature = 'orders:sync {--limit=500} {--offset=0} {--all : Fetch pages until Core returns an empty page} {--no-alerts : Do not send payment event notifications during import}';
    protected $description = 'Sync orders from Core cp_orders/fk_orders into local cp_orders';

    public function __construct(
        private readonly CoreApiService $core,
        private readonly AdminAlertService $alerts,
    ) {
        parent::__construct();
    }

    public function handle(): int
    {
        $this->info('Starting orders sync from Core...');
        $this->ensureLocalOrderSchema();

        $apiResult = $this->syncFromCoreApi();
        if ($apiResult === self::SUCCESS) {
            return self::SUCCESS;
        }

        $this->warn('Core API sync unavailable, falling back to optional Core DB connection...');

        if ($this->syncFromCoreDatabase()) {
            return self::SUCCESS;
        }

        return self::FAILURE;
    }

    private function syncFromCoreDatabase(): bool
    {
        $connection = config('database.connections.core_mysql.database') ? 'core_mysql' : null;
        $table = env('CORE_ORDERS_TABLE', 'cp_orders');
        $limit = (int) $this->option('limit');
        $offset = (int) $this->option('offset');

        if (! $connection) {
            return false;
        }

        try {
            if (! Schema::connection($connection)->hasTable($table)) {
                $this->warn("Core table {$table} not found.");
                return false;
            }

            $orders = DB::connection($connection)
                ->table($table)
                ->orderByDesc('id')
                ->offset($offset)
                ->limit($limit)
                ->get();
        } catch (\Throwable $e) {
            Log::warning('orders:sync core DB failed', ['error' => $e->getMessage()]);
            return false;
        }

        $synced = 0;
        $skipped = 0;

        foreach ($orders as $order) {
            $user = $this->resolveUser($order);

            if (! $user) {
                $skipped++;
                continue;
            }

            $this->upsertLocalOrder($order, $user->id);
            $synced++;
        }

        $this->info("Core DB sync completed: {$synced} synced, {$skipped} skipped");

        return true;
    }

    private function syncFromCoreApi(): int
    {
        $limit = max(1, (int) $this->option('limit'));
        $offset = max(0, (int) $this->option('offset'));
        $syncAll = (bool) $this->option('all');
        $synced = 0;
        $skipped = 0;

        do {
            $coreOrders = $this->extractOrderRows(
                $this->core->adminCpOrders($limit, $offset) ?? $this->core->adminOrders($limit, $offset),
            );

            if ($coreOrders === []) {
                break;
            }

            foreach ($coreOrders as $order) {
                $order = (object) $order;
                $user = $this->resolveUser($order);

                if (! $user) {
                    $skipped++;
                    continue;
                }

                $this->upsertLocalOrder($order, $user->id);
                $synced++;
            }

            $this->line("Fetched page offset={$offset}: ".count($coreOrders).' rows');
            $offset += $limit;
        } while ($syncAll && count($coreOrders) >= $limit);

        if ($synced === 0 && $skipped === 0) {
            $this->error('Failed to fetch cp_orders from Core API. Expected endpoint: /admin/cp-orders or /admin/cp_orders');
            return self::FAILURE;
        }

        $this->info("Core API sync completed: {$synced} synced, {$skipped} skipped");

        return self::SUCCESS;
    }

    private function extractOrderRows(?array $payload): array
    {
        if (! $payload) {
            return [];
        }

        if (array_is_list($payload)) {
            return $payload;
        }

        foreach (['orders', 'data', 'items', 'results'] as $key) {
            if (isset($payload[$key]) && is_array($payload[$key])) {
                return $payload[$key];
            }
        }

        return [];
    }

    private function resolveUser(object $order): ?User
    {
        foreach (['local_user_id', 'site_user_id', 'user_id'] as $field) {
            if (! empty($order->{$field})) {
                $user = User::query()->find((int) $order->{$field});
                if ($user) {
                    return $user;
                }
            }
        }

        foreach (['core_user_id', 'core_id'] as $field) {
            if (! empty($order->{$field})) {
                $user = User::query()->where('core_user_id', (int) $order->{$field})->first();
                if ($user) {
                    return $user;
                }
            }
        }

        foreach (['telegram_id', 'tg_chat_id', 'tg_user_id'] as $field) {
            if (! empty($order->{$field})) {
                $user = User::query()->where('telegram_id', $order->{$field})->first();
                if ($user) {
                    return $user;
                }
            }
        }

        foreach (['token', 'user_token', 'subscription_token', 'uuid', 'client_uuid'] as $field) {
            if (! empty($order->{$field})) {
                $user = User::query()->where('token', $order->{$field})
                    ->orWhere('client_uuid', $order->{$field})
                    ->first();

                if ($user) {
                    return $user;
                }
            }
        }

        return null;
    }

    private function upsertLocalOrder(object $order, int $userId): void
    {
        $invoiceId = $order->invoice_id ?? $order->order_id ?? ('CORE-' . $order->id);
        $status = $order->status ?? 'pending';
        $amount = (float) ($order->amount ?? 0);
        $corePlanId = (int) ($order->plan_id ?? 0);
        $planId = $this->resolvePlanId($order);
        $createdAt = $order->created_at ?? now();
        $paidAt = $order->paid_at ?? null;
        $transactionId = $order->transaction_id ?? $order->transactionId ?? $order->payment_id ?? $order->cp_transaction_id ?? null;

        $existing = CpOrder::query()->where('invoice_id', $invoiceId)->first();
        $previousStatus = $existing?->status;

        $localOrder = CpOrder::query()->updateOrCreate(
            ['invoice_id' => $invoiceId],
            [
                'transaction_id' => $transactionId,
                'user_id' => $userId,
                'plan_id' => $planId,
                'promo_code' => $order->promo_code ?? $order->promocode ?? $order->promocode_id ?? null,
                'amount' => $amount,
                'discount_amount' => (float) ($order->discount_amount ?? 0),
                'original_amount' => (float) ($order->original_amount ?? $amount),
                'currency' => $order->currency ?? 'RUB',
                'payment_method' => $order->payment_method ?? 'core_cp',
                'status' => $status,
                'description' => $corePlanId > 0
                    ? "Imported from core cp_orders; core_plan_id={$corePlanId}"
                    : 'Imported from core cp_orders',
                'raw_payload' => (array) $order,
                'paid_at' => $paidAt,
                'failed_at' => in_array($status, ['failed', 'cancelled', 'expired'], true) ? ($order->expires_at ?? null) : null,
                'created_at' => $createdAt,
                'updated_at' => now(),
            ]
        );

        FkOrder::query()->updateOrCreate(
            ['order_id' => $invoiceId],
            [
                'user_id' => $userId,
                'plan_id' => $planId,
                'amount' => $amount,
                'currency' => $order->currency ?? 'RUB',
                'payment_method' => 0,
                'status' => $status,
                'paid_at' => $paidAt,
            ]
        );

        if (! $this->option('no-alerts') && ($localOrder->wasRecentlyCreated || $previousStatus !== $status)) {
            $this->sendPaymentEventNotification($localOrder);
        }
    }

    private function ensureLocalOrderSchema(): void
    {
        if (! Schema::hasTable('cp_orders')) {
            Schema::create('cp_orders', function ($table): void {
                $table->id();
                $table->string('invoice_id', 128)->unique();
                $table->string('transaction_id', 128)->nullable()->index();
                $table->foreignId('user_id')->constrained()->cascadeOnDelete();
                $table->foreignId('plan_id')->constrained()->cascadeOnDelete();
                $table->decimal('amount', 10, 2)->default(0);
                $table->string('currency', 8)->default('RUB');
                $table->string('status', 24)->default('pending')->index();
                $table->string('payment_method', 64)->nullable();
                $table->string('description')->nullable();
                $table->json('raw_payload')->nullable();
                $table->timestamp('paid_at')->nullable();
                $table->timestamp('failed_at')->nullable();
                $table->unsignedBigInteger('promo_code_id')->nullable()->index();
                $table->string('promo_code', 64)->nullable();
                $table->decimal('discount_amount', 10, 2)->default(0);
                $table->decimal('original_amount', 10, 2)->nullable();
                $table->timestamps();
            });

            return;
        }

        $columns = [
            'invoice_id' => "ALTER TABLE cp_orders ADD COLUMN invoice_id varchar(128)",
            'transaction_id' => "ALTER TABLE cp_orders ADD COLUMN transaction_id varchar(128)",
            'user_id' => "ALTER TABLE cp_orders ADD COLUMN user_id integer",
            'plan_id' => "ALTER TABLE cp_orders ADD COLUMN plan_id integer",
            'amount' => "ALTER TABLE cp_orders ADD COLUMN amount numeric not null default 0",
            'currency' => "ALTER TABLE cp_orders ADD COLUMN currency varchar(8) not null default 'RUB'",
            'status' => "ALTER TABLE cp_orders ADD COLUMN status varchar(24) not null default 'pending'",
            'payment_method' => "ALTER TABLE cp_orders ADD COLUMN payment_method varchar(64)",
            'description' => "ALTER TABLE cp_orders ADD COLUMN description varchar",
            'raw_payload' => "ALTER TABLE cp_orders ADD COLUMN raw_payload text",
            'paid_at' => "ALTER TABLE cp_orders ADD COLUMN paid_at datetime",
            'failed_at' => "ALTER TABLE cp_orders ADD COLUMN failed_at datetime",
            'promo_code_id' => "ALTER TABLE cp_orders ADD COLUMN promo_code_id integer",
            'promo_code' => "ALTER TABLE cp_orders ADD COLUMN promo_code varchar(64)",
            'discount_amount' => "ALTER TABLE cp_orders ADD COLUMN discount_amount numeric not null default 0",
            'original_amount' => "ALTER TABLE cp_orders ADD COLUMN original_amount numeric",
            'created_at' => "ALTER TABLE cp_orders ADD COLUMN created_at datetime",
            'updated_at' => "ALTER TABLE cp_orders ADD COLUMN updated_at datetime",
        ];

        foreach ($columns as $column => $sql) {
            if (! Schema::hasColumn('cp_orders', $column)) {
                DB::statement($sql);
            }
        }
    }

    private function resolvePlanId(object $order): int
    {
        $durationMonths = (int) (
            $order->duration_months
            ?? $order->months
            ?? $order->period_months
            ?? $order->plan_months
            ?? 0
        );

        if ($durationMonths > 0) {
            $plan = Plan::query()->where('duration_months', $durationMonths)->first();
            if ($plan) {
                return $plan->id;
            }
        }

        $amount = $order->amount ?? $order->price_rub ?? $order->price ?? $order->paid_amount ?? null;
        if (is_numeric($amount)) {
            $plan = Plan::query()->where('price_rub', (int) round((float) $amount))->first();
            if ($plan) {
                return $plan->id;
            }
        }

        $planName = $order->plan_name ?? $order->tariff ?? $order->tariff_name ?? null;
        if (is_string($planName) && trim($planName) !== '') {
            $planName = trim($planName);
            $plan = Plan::query()
                ->where('name', $planName)
                ->orWhere('headline', $planName)
                ->first();
            if ($plan) {
                return $plan->id;
            }
        }

        $corePlanId = (int) ($order->plan_id ?? 0);
        if (filter_var(env('CORE_PLAN_IDS_ARE_LOCAL', false), FILTER_VALIDATE_BOOL) && $corePlanId > 0) {
            $plan = Plan::query()->find($corePlanId);
            if ($plan) {
                return $plan->id;
            }
        }

        return Plan::query()->orderBy('id')->value('id') ?? 1;
    }

    private function sendPaymentEventNotification(CpOrder $order): void
    {
        $this->alerts->sendOrderEvent($order->refresh());
    }
}
