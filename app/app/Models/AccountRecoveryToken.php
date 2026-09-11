<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class AccountRecoveryToken extends Model
{
    protected $fillable = [
        'user_id',
        'request_token_hash',
        'reset_token_hash',
        'identifier',
        'ip',
        'user_agent',
        'confirmed_at',
        'used_at',
        'expires_at',
    ];

    protected function casts(): array
    {
        return [
            'confirmed_at' => 'datetime',
            'used_at' => 'datetime',
            'expires_at' => 'datetime',
        ];
    }

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }
}
