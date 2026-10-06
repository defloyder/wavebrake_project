<?php

use App\Http\Controllers\AdminController;
use App\Http\Controllers\UserDetailsController;
use Illuminate\Support\Facades\Route;

// The user card: opened by clicking a user anywhere; every per-user action
// lives here and answers with the re-rendered card.
Route::prefix('/users/{userId}')->controller(UserDetailsController::class)->group(function () {
    Route::get('/details', 'show');
    Route::post('/profile', 'updateProfile');
    Route::post('/block', 'block');
    Route::post('/unblock', 'unblock');
    Route::post('/remove', 'destroy');
    Route::post('/password-reset', 'requestPasswordReset');
    Route::post('/subscription', 'issueSubscription');
    Route::post('/access', 'issueAccess');
    Route::post('/subscriptions/{subscriptionId}/edit', 'editSubscription');
    Route::post('/subscriptions/{subscriptionId}/reset-traffic', 'resetTraffic');
    Route::post('/subscriptions/{subscriptionId}/reissue', 'reissueAccess');
    Route::post('/subscriptions/{subscriptionId}/cancel', 'cancelSubscription');
    Route::post('/devices/{deviceId}/revoke', 'revokeDevice');
    Route::post('/grants/{grantId}/revoke', 'revokeGrant');
});

Route::get('/', [AdminController::class, 'index']);
Route::get('/login', [AdminController::class, 'loginPage']);
Route::post('/login', [AdminController::class, 'login']);
Route::post('/logout', [AdminController::class, 'logout']);

Route::get('/traffic/live', [AdminController::class, 'trafficLive']);
Route::get('/traffic/health', [AdminController::class, 'trafficHealth']);
Route::post('/assistant/message', [AdminController::class, 'assistantMessage']);
Route::post('/assistant/confirm', [AdminController::class, 'assistantConfirm']);

Route::post('/users', [AdminController::class, 'createUser']);
Route::post('/plans', [AdminController::class, 'createPlan']);
Route::post('/plans/{planId}', [AdminController::class, 'updatePlan']);
Route::post('/plans/{planId}/delete', [AdminController::class, 'deletePlan']);
Route::post('/promo-codes', [AdminController::class, 'createPromoCode']);
Route::post('/promo-codes/{promoId}', [AdminController::class, 'updatePromoCode']);
Route::post('/promo-codes/{promoId}/delete', [AdminController::class, 'deletePromoCode']);
Route::post('/nodes/enroll', [AdminController::class, 'enrollNode']);

Route::get('/{section}', [AdminController::class, 'section'])
    ->whereIn('section', ['dashboard', 'users', 'subscriptions', 'plans', 'promo-codes', 'nodes', 'grants', 'devices', 'traffic', 'audit', 'enroll']);
