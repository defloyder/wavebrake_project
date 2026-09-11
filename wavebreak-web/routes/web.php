<?php

use App\Http\Controllers\WebController;
use Illuminate\Support\Facades\Route;

Route::get('/', [WebController::class, 'index']);
Route::get('/pricing', [WebController::class, 'pricing']);
Route::get('/access', [WebController::class, 'access']);
Route::get('/login', [WebController::class, 'loginPage']);
Route::get('/register', [WebController::class, 'registerPage']);
Route::post('/login', [WebController::class, 'login']);
Route::post('/register', [WebController::class, 'register']);
Route::post('/logout', [WebController::class, 'logout']);
Route::get('/dashboard', [WebController::class, 'dashboard']);
Route::get('/dashboard/subscription', [WebController::class, 'subscription']);
Route::get('/dashboard/access', [WebController::class, 'accessDashboard']);
Route::get('/dashboard/nodes', [WebController::class, 'nodes']);
Route::get('/dashboard/devices', [WebController::class, 'devices']);
Route::post('/subscriptions', [WebController::class, 'subscribe']);
Route::post('/access/grants', [WebController::class, 'grant']);
Route::post('/access/grants/{grantId}/revoke', [WebController::class, 'revokeGrant']);
Route::post('/devices', [WebController::class, 'createDevice']);
Route::post('/telegram/link', [WebController::class, 'createTelegramLink']);
Route::delete('/telegram', [WebController::class, 'unlinkTelegram']);
