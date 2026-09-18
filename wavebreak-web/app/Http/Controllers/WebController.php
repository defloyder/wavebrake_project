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
        return view('home', $this->publicData(loadPlans: false));
    }

    public function pricing(): View
    {
        return view('pricing', $this->publicData());
    }

    public function access(): View
    {
        return view('access', $this->publicData(loadPlans: false));
    }

    public function download(): View
    {
        return view('download', $this->publicData(loadPlans: false));
    }

    private function publicData(array $extra = [], bool $loadPlans = true): array
    {
        $plans = $loadPlans ? $this->safePlans() : $this->defaultPlans();

        return array_merge([
            'health' => ['status' => 'online'],
            'plans' => $plans,
        ], $extra);
    }

    private function safePlans(): array
    {
        try {
            $plans = $this->core->plans();
            return $plans !== [] ? $plans : $this->defaultPlans();
        } catch (Throwable) {
            return $this->defaultPlans();
        }
    }

    private function defaultPlans(): array
    {
        return [
            ['id' => 'starter', 'code' => 'starter', 'name' => 'Starter', 'price_cents' => 900, 'interval' => 'month'],
            ['id' => 'plus', 'code' => 'plus', 'name' => 'Plus', 'price_cents' => 1900, 'interval' => 'month'],
            ['id' => 'fleet', 'code' => 'fleet', 'name' => 'Fleet', 'price_cents' => 4900, 'interval' => 'month'],
        ];
    }
}
