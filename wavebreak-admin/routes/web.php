<?php

use App\Http\Controllers\AdminController;
use Illuminate\Support\Facades\Route;

Route::get('/', [AdminController::class, 'index']);
Route::get('/login', [AdminController::class, 'loginPage']);
Route::get('/dashboard', [AdminController::class, 'dashboard']);
Route::get('/nodes', [AdminController::class, 'nodes']);
Route::get('/plans', [AdminController::class, 'plans']);
Route::get('/enroll', [AdminController::class, 'enroll']);
Route::get('/users', [AdminController::class, 'users']);
Route::get('/subscriptions', [AdminController::class, 'subscriptions']);
Route::get('/grants', [AdminController::class, 'grants']);
Route::get('/devices', [AdminController::class, 'devices']);
Route::get('/traffic', [AdminController::class, 'traffic']);
Route::get('/audit', [AdminController::class, 'audit']);
Route::post('/login', [AdminController::class, 'login']);
Route::post('/logout', [AdminController::class, 'logout']);
Route::post('/nodes/enroll', [AdminController::class, 'enrollNode']);
Route::post('/grants/{grantId}/revoke', [AdminController::class, 'revokeGrant']);
Route::post('/subscriptions/{subscriptionId}/status', [AdminController::class, 'updateSubscriptionStatus']);
