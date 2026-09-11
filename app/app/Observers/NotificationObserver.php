<?php

namespace App\Observers;

use App\Models\Notification;
use App\Services\WebPushService;

class NotificationObserver
{
    /**
     * After a Notification is created — send Web Push to the relevant users.
     */
    public function created(Notification $notification): void
    {
        /** @var WebPushService $push */
        $push = app(WebPushService::class);

        if ($notification->is_global) {
            $push->sendToAll(
                $notification->title,
                $notification->body,
                $notification->type,
            );
        } elseif ($notification->user_id) {
            $push->sendToUser(
                $notification->user_id,
                $notification->title,
                $notification->body,
                $notification->type,
            );
        }
    }
}
