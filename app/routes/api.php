<?php

use Illuminate\Support\Facades\Route;
use App\Http\Controllers\PasswordChangeController;
use App\Http\Controllers\TelegramLinkController;
use App\Http\Controllers\SyncWebhookController;

Route::post('/webhook/telegram-link', [TelegramLinkController::class, 'handle'])
    ->name('api.webhook.telegram-link');

Route::post('/webhook/password-change-confirm', [PasswordChangeController::class, 'confirm'])
    ->name('api.webhook.password-change-confirm');

Route::post('/webhook/sync-subscription', [SyncWebhookController::class, 'syncSubscription'])
    ->name('api.webhook.sync-subscription');

Route::post('/webhook/sync-user', [SyncWebhookController::class, 'syncUser'])
    ->name('api.webhook.sync-user');

Route::post('/webhook/core-sync', [SyncWebhookController::class, 'coreSync'])
    ->name('api.webhook.core-sync');
