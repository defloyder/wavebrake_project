<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasMany;

class Node extends Model
{
    protected $fillable = [
        'name',
        'ip',
        'country',
        'city',
        'lat',
        'lng',
        'port',
        'api_port',
        'api_secret',
        'status',
        'latency',
        'load',
        'errors',
        'is_active',
        'hidden_on_dashboard',
    ];

    protected function casts(): array
    {
        return [
            'latency' => 'float',
            'load' => 'float',
            'lat' => 'float',
            'lng' => 'float',
            'is_active' => 'boolean',
            'hidden_on_dashboard' => 'boolean',
        ];
    }

    public function subscriptions(): HasMany
    {
        return $this->hasMany(Subscription::class);
    }
}
