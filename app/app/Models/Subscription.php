<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class Subscription extends Model
{
    protected $fillable = [
        'user_id',
        'plan_id',
        'node_id',
        'status',
        'traffic_used_gb',
        'traffic_limit_gb',
        'avg_speed_mbps',
        'peak_speed_mbps',
        'devices_online',
        'last_sync_at',
        'starts_at',
        'ends_at',
    ];

    protected function casts(): array
    {
        return [
            'traffic_used_gb' => 'float',
            'traffic_limit_gb' => 'float',
            'avg_speed_mbps' => 'float',
            'peak_speed_mbps' => 'float',
            'last_sync_at' => 'datetime',
            'starts_at' => 'datetime',
            'ends_at' => 'datetime',
        ];
    }

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }

    public function plan(): BelongsTo
    {
        return $this->belongsTo(Plan::class);
    }

    public function node(): BelongsTo
    {
        return $this->belongsTo(Node::class);
    }
}
