<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Run the migrations.
     */
    public function up(): void
    {
        Schema::create('subscriptions', function (Blueprint $table) {
            $table->id();
            $table->foreignId('user_id')->constrained()->cascadeOnDelete();
            $table->foreignId('plan_id')->constrained()->cascadeOnDelete();
            $table->string('email');
            $table->string('telegram')->nullable();
            $table->enum('status', ['pending', 'active', 'expired'])->default('pending');
            $table->decimal('traffic_used_gb', 8, 2)->default(0);
            $table->decimal('traffic_limit_gb', 8, 2)->default(500);
            $table->decimal('avg_speed_mbps', 8, 2)->default(0);
            $table->decimal('peak_speed_mbps', 8, 2)->default(0);
            $table->unsignedInteger('devices_online')->default(0);
            $table->timestamp('last_sync_at')->nullable();
            $table->timestamp('starts_at')->nullable();
            $table->timestamp('ends_at')->nullable();
            $table->timestamps();
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::dropIfExists('subscriptions');
    }
};
