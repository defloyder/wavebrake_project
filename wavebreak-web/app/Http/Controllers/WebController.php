<?php

namespace App\Http\Controllers;

use App\Services\CoreClient;
use Illuminate\View\View;
use Throwable;

class WebController extends Controller
{
    public function __construct(private readonly CoreClient $core)
    {
    }

    public function index(): View
    {
        return view('home');
    }

    public function pricing(): View
    {
        try {
            $plans = array_values(array_filter($this->core->plans(), fn (array $plan) =>
                ($plan['is_active'] ?? true) && ($plan['is_public'] ?? true)
            ));
        } catch (Throwable) {
            $plans = [];
        }

        return view('pricing', compact('plans'));
    }

    public function access(): View
    {
        return view('access');
    }

    public function download(): View
    {
        return view('download');
    }
}
