<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasMany;

class Plan extends Model
{
    protected $fillable = [
        'name',
        'duration_months',
        'price_rub',
        'headline',
        'features',
        'is_highlighted',
    ];

    protected function casts(): array
    {
        return [
            'features' => 'array',
            'is_highlighted' => 'boolean',
        ];
    }

    public function subscriptions(): HasMany
    {
        return $this->hasMany(Subscription::class);
    }

    public function featureList(): array
    {
        $features = $this->features;

        for ($attempt = 0; $attempt < 2 && is_string($features); $attempt++) {
            $decoded = json_decode($features, true);
            if (json_last_error() !== JSON_ERROR_NONE) {
                break;
            }
            $features = $decoded;
        }

        if (! is_array($features)) {
            return [];
        }

        return array_values(array_filter(array_map(
            static fn ($feature) => trim((string) $feature),
            $features,
        )));
    }
}
