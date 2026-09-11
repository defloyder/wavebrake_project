<?php

use Illuminate\Foundation\Inspiring;
use Illuminate\Support\Facades\Artisan;
use Illuminate\Support\Facades\Schedule;

Artisan::command('inspire', function () {
    $this->comment(Inspiring::quote());
})->purpose('Display an inspiring quote');

Schedule::command('orders:sync --limit=500 --all --no-alerts')->everyMinute()->withoutOverlapping()->runInBackground();
Schedule::command('nodes:sync')->everyMinute()->withoutOverlapping()->runInBackground();
Schedule::command('core:sync')->everyMinute()->withoutOverlapping()->runInBackground();
Schedule::command('promo-codes:sync')->everyFiveMinutes()->withoutOverlapping()->runInBackground();
Schedule::command('admin:system-digest')->everyMinute()->withoutOverlapping()->runInBackground();
