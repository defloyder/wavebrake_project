<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class AdminLog extends Model
{
    protected $fillable = ['admin_id', 'action', 'resource', 'resource_id', 'changes', 'ip'];

    protected $casts = ['changes' => 'array'];

    public function admin(): BelongsTo
    {
        return $this->belongsTo(Admin::class);
    }

    public static function log(string $action, ?string $resource = null, ?int $resourceId = null, ?array $changes = null): void
    {
        $adminId = session('admin_id');
        if (! $adminId) return;

        static::create([
            'admin_id'    => $adminId,
            'action'      => $action,
            'resource'    => $resource,
            'resource_id' => $resourceId,
            'changes'     => $changes,
            'ip'          => request()->ip(),
        ]);
    }

    public static function logFailedLogin(string $username, string $reason): void
    {
        try {
            static::create([
                'admin_id'    => null,
                'action'      => 'failed_login',
                'resource'    => null,
                'resource_id' => null,
                'changes'     => ['username' => $username, 'reason' => $reason],
                'ip'          => request()->ip(),
            ]);
        } catch (\Throwable) {}
    }
}
