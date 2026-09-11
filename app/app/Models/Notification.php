<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\BelongsToMany;
use Illuminate\Support\Facades\DB;

class Notification extends Model
{
    protected $fillable = ['title', 'body', 'type', 'is_global', 'user_id'];

    protected $casts = ['is_global' => 'boolean'];

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }

    public function readers(): BelongsToMany
    {
        return $this->belongsToMany(User::class, 'notification_reads')
            ->withPivot('read_at');
    }

    public static function forUser(int $userId, int $limit = 20): \Illuminate\Support\Collection
    {
        return self::query()
            ->where(function ($q) use ($userId) {
                $q->where('is_global', true)
                  ->orWhere('user_id', $userId);
            })
            ->orderByDesc('created_at')
            ->limit($limit)
            ->get()
            ->map(function (self $n) use ($userId) {
                $n->is_read = $n->readers()->where('user_id', $userId)->exists();
                return $n;
            });
    }

    public static function unreadCount(int $userId): int
    {
        $total = self::query()
            ->where(function ($q) use ($userId) {
                $q->where('is_global', true)
                  ->orWhere('user_id', $userId);
            })
            ->count();

        $read = DB::table('notification_reads')
            ->where('user_id', $userId)
            ->count();

        return max(0, $total - $read);
    }
}
