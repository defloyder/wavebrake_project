<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('users', function (Blueprint $table): void {
            if (! Schema::hasColumn('users', 'receives_payment_notifications')) {
                $table->boolean('receives_payment_notifications')->default(false)->after('has_password');
            }
        });

        Schema::create('promo_codes', function (Blueprint $table): void {
            $table->id();
            $table->string('code', 64)->unique();
            $table->string('type', 16)->default('percent');
            $table->decimal('value', 10, 2)->default(0);
            $table->boolean('is_active')->default(true);
            $table->timestamp('starts_at')->nullable();
            $table->timestamp('expires_at')->nullable();
            $table->unsignedInteger('max_uses')->nullable();
            $table->unsignedInteger('used_count')->default(0);
            $table->timestamps();
        });

        Schema::table('cp_orders', function (Blueprint $table): void {
            if (! Schema::hasColumn('cp_orders', 'promo_code_id')) {
                $table->unsignedBigInteger('promo_code_id')->nullable()->after('plan_id')->index();
            }
            if (! Schema::hasColumn('cp_orders', 'promo_code')) {
                $table->string('promo_code', 64)->nullable()->after('promo_code_id');
            }
            if (! Schema::hasColumn('cp_orders', 'discount_amount')) {
                $table->decimal('discount_amount', 10, 2)->default(0)->after('amount');
            }
            if (! Schema::hasColumn('cp_orders', 'original_amount')) {
                $table->decimal('original_amount', 10, 2)->nullable()->after('discount_amount');
            }
        });
    }

    public function down(): void
    {
        Schema::table('cp_orders', function (Blueprint $table): void {
            foreach (['promo_code_id', 'promo_code', 'discount_amount', 'original_amount'] as $column) {
                if (Schema::hasColumn('cp_orders', $column)) {
                    $table->dropColumn($column);
                }
            }
        });

        Schema::dropIfExists('promo_codes');

        Schema::table('users', function (Blueprint $table): void {
            if (Schema::hasColumn('users', 'receives_payment_notifications')) {
                $table->dropColumn('receives_payment_notifications');
            }
        });
    }
};
