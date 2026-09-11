<?php

namespace App\Http\Controllers;

use App\Models\Notification;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;

class AdminNotificationController extends Controller
{
    public function send(Request $request): RedirectResponse
    {
        $data = $request->validate([
            'title' => ['required', 'string', 'max:255'],
            'body'  => ['required', 'string', 'max:2000'],
            'type'  => ['required', 'in:info,warning,success'],
        ]);

        Notification::query()->create([
            'title'     => $data['title'],
            'body'      => $data['body'],
            'type'      => $data['type'],
            'is_global' => true,
            'user_id'   => null,
        ]);

        return redirect()->route('admin.dashboard')
            ->with('success', 'Уведомление отправлено всем пользователям.');
    }

    public function destroy(Request $request, int $id): RedirectResponse|JsonResponse
    {
        Notification::query()->findOrFail($id)->delete();

        if ($request->expectsJson()) {
            return response()->json(['ok' => true, 'deleted' => 1]);
        }

        return redirect()->route('admin.dashboard')
            ->with('success', 'Уведомление удалено.');
    }

    public function destroyMany(Request $request): RedirectResponse|JsonResponse
    {
        $data = $request->validate([
            'ids' => ['required', 'array', 'min:1'],
            'ids.*' => ['integer', 'distinct'],
        ]);

        $deleted = Notification::query()
            ->whereIn('id', $data['ids'])
            ->delete();

        if ($request->expectsJson()) {
            return response()->json(['ok' => true, 'deleted' => $deleted]);
        }

        return redirect()->route('admin.dashboard')
            ->with('success', "Удалено уведомлений: {$deleted}.");
    }
}
