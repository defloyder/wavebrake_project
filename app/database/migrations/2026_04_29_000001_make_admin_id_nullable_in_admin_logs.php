<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('admin_logs', function (Blueprint $table) {
            // Make admin_id nullable to allow logging failed login attempts
            // where no admin session exists yet
            $table->foreignId('admin_id')->nullable()->change();
        });
    }

    public function down(): void
    {
        Schema::table('admin_logs', function (Blueprint $table) {
            $table->foreignId('admin_id')->nullable(false)->change();
        });
    }
};
