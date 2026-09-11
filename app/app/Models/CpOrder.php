<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class CpOrder extends Model
{
    protected $table = 'cp_orders';

    protected $fillable = [
        'invoice_id',
        'transaction_id',
        'user_id',
        'plan_id',
        'promo_code_id',
        'promo_code',
        'amount',
        'discount_amount',
        'original_amount',
        'currency',
        'status',
        'payment_method',
        'description',
        'raw_payload',
        'paid_at',
        'failed_at',
    ];

    protected function casts(): array
    {
        return [
            'amount' => 'float',
            'discount_amount' => 'float',
            'original_amount' => 'float',
            'raw_payload' => 'array',
            'paid_at' => 'datetime',
            'failed_at' => 'datetime',
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

    public function promoCode(): BelongsTo
    {
        return $this->belongsTo(PromoCode::class);
    }
}
