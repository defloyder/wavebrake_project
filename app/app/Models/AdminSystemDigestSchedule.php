<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class AdminSystemDigestSchedule extends Model
{
    protected $fillable = [
        'send_time',
        'is_enabled',
        'last_sent_at',
    ];

    protected function casts(): array
    {
        return [
            'is_enabled' => 'boolean',
            'last_sent_at' => 'datetime',
        ];
    }

    public function sentToday(): bool
    {
        return $this->last_sent_at?->isSameDay(now()) ?? false;
    }
}
