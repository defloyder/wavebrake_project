<?php

namespace App\Providers;

use App\Models\Notification;
use App\Observers\NotificationObserver;
use Illuminate\Support\Facades\Event;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\ServiceProvider;
use NotificationChannels\WebPush\Events\NotificationFailed;
use NotificationChannels\WebPush\Events\NotificationSent;

class AppServiceProvider extends ServiceProvider
{
    /**
     * Register any application services.
     */
    public function register(): void
    {
        //
    }

    /**
     * Bootstrap any application services.
     */
    public function boot(): void
    {
        \Carbon\Carbon::setLocale('ru');

        Notification::observe(NotificationObserver::class);

        Event::listen(NotificationSent::class, function (NotificationSent $event): void {
            Log::info('WebPush: notification accepted', [
                'subscription_id' => $event->subscription->id,
                'endpoint' => $event->report->getEndpoint(),
            ]);
        });

        Event::listen(NotificationFailed::class, function (NotificationFailed $event): void {
            if ($event->report->isSubscriptionExpired()) {
                $event->subscription->delete();
            }

            Log::warning('WebPush: notification failed', [
                'subscription_id' => $event->subscription->id,
                'endpoint' => $event->report->getEndpoint(),
                'reason' => $event->report->getReason(),
                'status' => $event->report->getResponse()?->getStatusCode(),
                'expired' => $event->report->isSubscriptionExpired(),
                'deleted' => $event->report->isSubscriptionExpired(),
            ]);
        });
    }
}
