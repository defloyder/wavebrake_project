<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class AdminWebAuthnCredential extends Model
{
    protected $table = 'admin_webauthn_credentials';

    protected $fillable = [
        'admin_id',
        'credential_id',
        'public_key',
        'sign_count',
        'device_name',
    ];

    public function admin(): BelongsTo
    {
        return $this->belongsTo(Admin::class);
    }
}
