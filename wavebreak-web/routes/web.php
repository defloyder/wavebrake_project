<?php

use App\Http\Controllers\WebController;
use Illuminate\Support\Facades\Route;

Route::get('/', [WebController::class, 'index']);
Route::get('/pricing', [WebController::class, 'pricing']);
Route::get('/access', [WebController::class, 'access']);
Route::get('/download', [WebController::class, 'download']);

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
