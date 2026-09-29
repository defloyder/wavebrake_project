<?php

use App\Http\Controllers\WebController;
use App\Http\Middleware\SetLocale;
use App\Support\Locales;
use Illuminate\Support\Facades\Route;

$pages = function (): void {
    Route::get('/', [WebController::class, 'index'])->name('home');
    Route::get('/pricing', [WebController::class, 'pricing'])->name('pricing');
    Route::get('/access', [WebController::class, 'access'])->name('access');
    Route::get('/download', [WebController::class, 'download'])->name('download');
    Route::get('/terms', [WebController::class, 'terms'])->name('terms');
    Route::get('/privacy', [WebController::class, 'privacy'])->name('privacy');
};

// Russian lives at the root; every other language under its own prefix.
foreach (array_keys(Locales::SUPPORTED) as $locale) {
    Route::middleware(SetLocale::class.':'.$locale)
        ->prefix($locale === Locales::DEFAULT ? '' : $locale)
        ->name($locale.'.')
        ->group($pages);
}

Route::get('/sitemap.xml', [WebController::class, 'sitemap']);

// Account management lives in the native clients. Keep old bookmarks useful,
// while ensuring the website can no longer mutate customer data.
Route::any('/login', fn () => redirect('/download'));
Route::any('/register', fn () => redirect('/download'));
Route::any('/logout', fn () => redirect('/download'));
Route::any('/dashboard/{path?}', fn () => redirect('/download'))->where('path', '.*');
Route::any('/subscriptions', fn () => redirect('/download'));
Route::any('/access/grants/{path?}', fn () => redirect('/download'))->where('path', '.*');
Route::any('/devices', fn () => redirect('/download'));
Route::any('/telegram/{path?}', fn () => redirect('/download'))->where('path', '.*');
