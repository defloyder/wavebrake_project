<?php

namespace App\Http\Controllers;

use App\Models\Notification;
use Illuminate\Http\JsonResponse;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\DB;

class NotificationController extends Controller
{
    public function index(): JsonResponse
    {
        $userId = (int) Auth::user()->id;
        $notifications = Notification::forUser($userId, 30);
        $unreadCount   = Notification::unreadCount($userId);

        return response()->json([
            'unread_count'  => $unreadCount,
            'notifications' => $notifications->map(fn($n) => [
                'id'        => $n->id,
                'title'     => $n->title,
                'body'      => $n->body,
                'type'      => $n->type,
                'is_read'   => $n->is_read,
                'created_at'=> $n->created_at?->diffForHumans(),
            ])->values(),
        ]);
    }

    public function markRead(int $id): JsonResponse
    {
        $userId = (int) Auth::user()->id;
        DB::table('notification_reads')->insertOrIgnore([
            'notification_id' => $id,
            'user_id'         => $userId,
            'read_at'         => now(),
        ]);

        return response()->json([
            'ok' => true,
            'unread_count' => Notification::unreadCount($userId),
        ]);
    }

    public function markAllRead(): JsonResponse
    {
        $userId = (int) Auth::user()->id;

        $notifIds = Notification::query()
            ->where(function ($q) use ($userId) {
                $q->where('is_global', true)->orWhere('user_id', $userId);
            })
            ->pluck('id');

        foreach ($notifIds as $notifId) {
            DB::table('notification_reads')->insertOrIgnore([
                'notification_id' => $notifId,
                'user_id'         => $userId,
                'read_at'         => now(),
            ]);
        }

        return response()->json(['ok' => true]);
    }
}
