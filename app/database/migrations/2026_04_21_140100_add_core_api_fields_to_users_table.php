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
        Schema::table('users', function (Blueprint $table): void {
            $table->unsignedBigInteger('telegram_id')->nullable()->unique()->after('id');
            $table->string('username')->nullable()->after('name');
            $table->uuid('token')->nullable()->unique()->after('email');
            $table->uuid('client_uuid')->nullable()->unique()->after('token');
            $table->boolean('trial_used')->default(false)->after('client_uuid');
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::table('users', function (Blueprint $table): void {
            $table->dropUnique(['telegram_id']);
            $table->dropUnique(['token']);
            $table->dropUnique(['client_uuid']);
            $table->dropColumn(['telegram_id', 'username', 'token', 'client_uuid', 'trial_used']);
        });
    }
};
