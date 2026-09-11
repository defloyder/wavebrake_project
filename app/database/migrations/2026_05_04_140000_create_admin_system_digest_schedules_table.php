<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('admin_system_digest_schedules', function (Blueprint $table): void {
            $table->id();
            $table->string('send_time', 5);
            $table->boolean('is_enabled')->default(true);
            $table->timestamp('last_sent_at')->nullable();
            $table->timestamps();

            $table->unique('send_time');
        });

        foreach (['09:00', '15:00', '21:00'] as $time) {
            DB::table('admin_system_digest_schedules')->insert([
                'send_time' => $time,
                'is_enabled' => true,
                'created_at' => now(),
                'updated_at' => now(),
            ]);
        }
    }

    public function down(): void
    {
        Schema::dropIfExists('admin_system_digest_schedules');
    }
};
