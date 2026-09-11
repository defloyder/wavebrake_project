<?php

namespace App\Http\Controllers;

use App\Models\Lead;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class LeadController extends Controller
{
    public function store(Request $request): JsonResponse
    {
        $data = $request->validate([
            'name'    => ['required', 'string', 'max:120'],
            'email'   => ['required', 'email', 'max:180'],
            'message' => ['nullable', 'string', 'max:2000'],
            'privacy_consent' => ['accepted'],
        ]);

        Lead::query()->create([
            'name' => $data['name'],
            'email' => $data['email'],
            'message' => $data['message'] ?? null,
        ]);

        return response()->json(['ok' => true]);
    }
}
