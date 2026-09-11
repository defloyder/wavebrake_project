<?php

namespace App\Notifications;

use Illuminate\Notifications\Notification;
use NotificationChannels\WebPush\WebPushChannel;
use NotificationChannels\WebPush\WebPushMessage;

class WebPushNotification extends Notification
{
    public function __construct(
        private readonly string $title,
        private readonly string $body,
        private readonly string $type = 'info',
        private readonly string $url = '/profile',
    ) {}

    public function via(object $notifiable): array
    {
        return [WebPushChannel::class];
    }

    public function toWebPush(object $notifiable, Notification $notification): WebPushMessage
    {
        return (new WebPushMessage())
            ->title($this->title)
            ->body($this->body)
            ->icon('/images/pwa-192.png')
            ->badge('/images/notification-badge.png')
            ->tag('auralith-notification')
            ->renotify()
            ->data([
                'url' => $this->url,
                'type' => $this->type,
            ])
            ->options(['TTL' => 86400]);
    }
}
