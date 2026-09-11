<?php

use App\Models\User;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('push_subscriptions', function (Blueprint $table): void {
            if (! Schema::hasColumn('push_subscriptions', 'subscribable_type')) {
                $table->string('subscribable_type')->nullable()->after('id');
            }

            if (! Schema::hasColumn('push_subscriptions', 'subscribable_id')) {
                $table->unsignedBigInteger('subscribable_id')->nullable()->after('subscribable_type');
            }

            if (! Schema::hasColumn('push_subscriptions', 'public_key')) {
                $table->string('public_key', 512)->nullable()->after('endpoint');
            }

            if (! Schema::hasColumn('push_subscriptions', 'auth_token')) {
                $table->string('auth_token', 256)->nullable()->after('public_key');
            }

            if (! Schema::hasColumn('push_subscriptions', 'content_encoding')) {
                $table->string('content_encoding', 50)->nullable()->after('auth_token');
            }
        });

        DB::table('push_subscriptions')
            ->whereNull('subscribable_type')
            ->whereNotNull('user_id')
            ->update([
                'subscribable_type' => User::class,
            ]);

        DB::table('push_subscriptions')
            ->whereNull('subscribable_id')
            ->whereNotNull('user_id')
            ->update([
                'subscribable_id' => DB::raw('user_id'),
            ]);

        DB::table('push_subscriptions')
            ->whereNull('public_key')
            ->whereNotNull('p256dh')
            ->update([
                'public_key' => DB::raw('p256dh'),
            ]);

        DB::table('push_subscriptions')
            ->whereNull('auth_token')
            ->whereNotNull('auth')
            ->update([
                'auth_token' => DB::raw('auth'),
            ]);

        DB::table('push_subscriptions')
            ->whereNull('content_encoding')
            ->update(['content_encoding' => 'aes128gcm']);

        if (! Schema::hasIndex('push_subscriptions', 'push_subscriptions_subscribable_morph_idx')) {
            Schema::table('push_subscriptions', function (Blueprint $table): void {
                $table->index(['subscribable_type', 'subscribable_id'], 'push_subscriptions_subscribable_morph_idx');
            });
        }
    }

    public function down(): void
    {
        Schema::table('push_subscriptions', function (Blueprint $table): void {
            if (Schema::hasIndex('push_subscriptions', 'push_subscriptions_subscribable_morph_idx')) {
                $table->dropIndex('push_subscriptions_subscribable_morph_idx');
            }

            $table->dropColumn([
                'subscribable_type',
                'subscribable_id',
                'public_key',
                'auth_token',
                'content_encoding',
            ]);
        });
    }
};
