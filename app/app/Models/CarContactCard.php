<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;

class CarContactCard extends Model
{
    use HasFactory;

    protected $fillable = [
        'slug',
        'phone',
        'phone_e164',
        'phone_pretty',
        'whatsapp_phone',
        'telegram',
        'email',
        'accent_scheme',
        'message',
        'qr_path',
        'card_path',
        'is_active',
    ];

    protected function casts(): array
    {
        return [
            'is_active' => 'boolean',
        ];
    }

    public function pageUrl(): string
    {
        return route('car.contact', ['slug' => $this->slug]);
    }

    public function qrUrl(): ?string
    {
        return $this->qr_path ? asset($this->qr_path) : null;
    }

    public function cardUrl(): ?string
    {
        return $this->card_path ? asset($this->card_path) : null;
    }
}
