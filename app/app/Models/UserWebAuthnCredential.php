<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class UserWebAuthnCredential extends Model
{
    protected $table = 'user_webauthn_credentials';

    protected $fillable = [
        'user_id',
        'credential_id',
        'public_key',
        'sign_count',
        'device_name',
    ];

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }
}
