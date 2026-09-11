<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('subscriptions', function (Blueprint $table): void {
            $table->string('status', 32)->default('pending')->change();
        });
    }

    public function down(): void
    {
        // Core uses more states than the original enum, so narrowing the column is unsafe.
    }
};
