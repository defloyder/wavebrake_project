<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        if (! Schema::hasTable('fk_orders') || ! Schema::hasTable('cp_orders')) {
            return;
        }

        DB::table('fk_orders')
            ->orderBy('id')
            ->get()
            ->each(function ($order): void {
                DB::table('cp_orders')->updateOrInsert(
                    ['invoice_id' => $order->order_id],
                    [
                        'transaction_id' => null,
                        'user_id' => $order->user_id,
                        'plan_id' => $order->plan_id,
                        'amount' => $order->amount,
                        'discount_amount' => 0,
                        'original_amount' => $order->amount,
                        'currency' => $order->currency ?? 'RUB',
                        'status' => $order->status,
                        'payment_method' => (string) $order->payment_method,
                        'description' => 'Imported from fk_orders',
                        'paid_at' => $order->paid_at,
                        'failed_at' => null,
                        'created_at' => $order->created_at,
                        'updated_at' => now(),
                    ]
                );
            });
    }

    public function down(): void
    {
        DB::table('cp_orders')
            ->where('description', 'Imported from fk_orders')
            ->delete();
    }
};
