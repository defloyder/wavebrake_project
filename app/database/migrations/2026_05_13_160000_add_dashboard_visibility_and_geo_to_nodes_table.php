<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('nodes', function (Blueprint $table): void {
            if (! Schema::hasColumn('nodes', 'hidden_on_dashboard')) {
                $table->boolean('hidden_on_dashboard')->default(false)->after('is_active');
            }
            if (! Schema::hasColumn('nodes', 'country')) {
                $table->string('country', 80)->nullable()->after('ip');
            }
            if (! Schema::hasColumn('nodes', 'city')) {
                $table->string('city', 80)->nullable()->after('country');
            }
            if (! Schema::hasColumn('nodes', 'lat')) {
                $table->decimal('lat', 10, 7)->nullable()->after('city');
            }
            if (! Schema::hasColumn('nodes', 'lng')) {
                $table->decimal('lng', 10, 7)->nullable()->after('lat');
            }
        });
    }

    public function down(): void
    {
        Schema::table('nodes', function (Blueprint $table): void {
            foreach (['hidden_on_dashboard', 'lng', 'lat', 'city', 'country'] as $column) {
                if (Schema::hasColumn('nodes', $column)) {
                    $table->dropColumn($column);
                }
            }
        });
    }
};
