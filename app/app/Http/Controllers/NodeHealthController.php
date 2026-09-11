<?php

namespace App\Http\Controllers;

use App\Services\NodeMonitorService;
use Illuminate\Http\JsonResponse;

/**
 * NodeHealthController
 *
 * Internal JSON endpoint consumed by the admin dashboard frontend.
 * Polled every 15 seconds via fetch() in admin-dashboard.js.
 *
 * Route: GET /admin/api/nodes/health   (middleware: admin)
 */
class NodeHealthController extends Controller
{
    public function __construct(private readonly NodeMonitorService $monitor) {}

    public function index(): JsonResponse
    {
        return response()->json($this->monitor->health());
    }
}
