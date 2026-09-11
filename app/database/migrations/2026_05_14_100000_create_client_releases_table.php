<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('client_releases', function (Blueprint $table): void {
            $table->id();
            $table->string('channel', 32)->unique();
            $table->string('label', 64);
            $table->string('version', 64)->nullable();
            $table->string('download_path', 512)->nullable();
            $table->string('latest_json_path', 512)->nullable();
            $table->text('notes')->nullable();
            $table->boolean('is_enabled')->default(true);
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('client_releases');
    }
};
