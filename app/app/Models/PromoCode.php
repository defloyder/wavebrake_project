<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class PromoCode extends Model
{
    protected $fillable = [
        'code',
        'type',
        'value',
        'is_active',
        'starts_at',
        'expires_at',
        'max_uses',
        'used_count',
    ];

    protected function casts(): array
    {
        return [
            'value' => 'float',
            'is_active' => 'boolean',
            'starts_at' => 'datetime',
            'expires_at' => 'datetime',
        ];
    }

    public function isValid(): bool
    {
        if (! $this->is_active) {
            return false;
        }

        if ($this->starts_at && $this->starts_at->isFuture()) {
            return false;
        }

        if ($this->expires_at && $this->expires_at->isPast()) {
            return false;
        }

        if ($this->max_uses !== null && $this->used_count >= $this->max_uses) {
            return false;
        }

        return true;
    }

    public function discountFor(float $amount): float
    {
        if (! $this->isValid()) {
            return 0.0;
        }

        $discount = match ($this->type) {
            'percent' => $amount * min(100, max(0, $this->value)) / 100,
            'fixed' => max(0, $this->value),
            'duration_days' => $amount,
            default => 0,
        };

        return round(min($amount, $discount), 2);
    }
}
