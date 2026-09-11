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
        Schema::create('nodes', function (Blueprint $table): void {
            $table->id();
            $table->string('name', 64)->unique();
            $table->string('ip', 45);
            $table->unsignedInteger('port')->default(443);
            $table->unsignedInteger('api_port')->default(8443);
            $table->string('api_secret');
            $table->string('status', 16)->default('unknown');
            $table->float('latency')->nullable();
            $table->float('load')->default(0);
            $table->unsignedInteger('errors')->default(0);
            $table->boolean('is_active')->default(true);
            $table->timestamp('updated_at')->nullable();
            $table->timestamp('created_at')->nullable();
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::dropIfExists('nodes');
    }
};
