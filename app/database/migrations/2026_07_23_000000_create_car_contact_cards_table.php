<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('car_contact_cards', function (Blueprint $table): void {
            $table->id();
            $table->string('slug')->unique();
            $table->string('phone');
            $table->string('phone_e164');
            $table->string('phone_pretty');
            $table->string('whatsapp_phone')->nullable();
            $table->string('telegram')->nullable();
            $table->string('email')->nullable();
            $table->string('accent_scheme')->default('aurora');
            $table->string('message')->default('Здравствуйте! Я по поводу вашей машины.');
            $table->string('qr_path')->nullable();
            $table->string('card_path')->nullable();
            $table->boolean('is_active')->default(true);
            $table->timestamps();

            $table->index('phone');
            $table->index('is_active');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('car_contact_cards');
    }
};
