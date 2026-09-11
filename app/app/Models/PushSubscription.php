<?php

namespace App\Models;

use NotificationChannels\WebPush\PushSubscription as WebPushPushSubscription;

class PushSubscription extends WebPushPushSubscription
{
    protected $fillable = [
        'subscribable_type',
        'subscribable_id',
        'user_id',
        'endpoint',
        'public_key',
        'auth_token',
        'content_encoding',
    ];

    protected static function booted(): void
    {
        static::creating(function (self $subscription): void {
            $subscription->syncLegacyColumns();
        });

        static::saving(function (self $subscription): void {
            $subscription->syncLegacyColumns();
        });
    }

    private function syncLegacyColumns(): void
    {
        if ($this->subscribable_type === User::class && $this->subscribable_id) {
            $this->user_id = $this->subscribable_id;
        } elseif ($this->subscribable_type) {
            $this->user_id = null;
        }

        $this->p256dh = $this->public_key;
        $this->auth = $this->auth_token;
    }
}
