<?php

namespace App\Http\Controllers;

use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;

class PushSubscriptionController extends Controller
{
    /**
     * Save or update a push subscription for the current user.
     * POST /push/subscribe
     */
    public function subscribe(Request $request): JsonResponse
    {
        $data = $request->validate([
            'endpoint' => ['required', 'string', 'url', 'max:500'],
            'p256dh'   => ['required', 'string', 'max:512'],
            'auth'     => ['required', 'string', 'max:256'],
            'content_encoding' => ['nullable', 'string', 'max:50'],
        ]);

        $user = Auth::user();

        if (! $user) {
            return response()->json(['error' => 'Unauthenticated'], 401);
        }

        $user->updatePushSubscription(
            $data['endpoint'],
            $data['p256dh'],
            $data['auth'],
            $data['content_encoding'] ?? 'aes128gcm',
        );

        return response()->json(['ok' => true]);
    }

    /**
     * Remove a push subscription (user unsubscribed in browser).
     * DELETE /push/subscribe
     */
    public function unsubscribe(Request $request): JsonResponse
    {
        $data = $request->validate([
            'endpoint' => ['required', 'string', 'max:500'],
        ]);

        Auth::user()?->deletePushSubscription($data['endpoint']);

        return response()->json(['ok' => true]);
    }

    /**
     * Return the VAPID public key so the browser can subscribe.
     * GET /push/vapid-public-key
     */
    public function vapidPublicKey(): JsonResponse
    {
        return response()->json([
            'public_key' => config('webpush.vapid.public_key', ''),
        ]);
    }

    /**
     * Check if the current user has any active push subscriptions.
     * GET /push/status
     */
    public function status(): JsonResponse
    {
        $count = Auth::user()?->pushSubscriptions()->count() ?? 0;

        return response()->json(['subscribed' => $count > 0]);
    }
}
