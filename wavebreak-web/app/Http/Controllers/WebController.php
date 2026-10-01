<?php

namespace App\Http\Controllers;

use App\Services\CoreClient;
use App\Support\Locales;
use Illuminate\Http\Response;
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

        $tiers = $this->pricingTiers($plans);
        $hasYearly = collect($tiers)->contains(fn (array $tier) => $tier['year'] !== null);
        $hasMonthly = collect($tiers)->contains(fn (array $tier) => $tier['month'] !== null);
        $maxDiscount = collect($tiers)->max(fn (array $tier) => $tier['year']['discount'] ?? 0) ?: null;

        return view('pricing', compact('plans', 'tiers', 'hasYearly', 'hasMonthly', 'maxDiscount'));
    }

    /**
     * Pairs the monthly and yearly variant of each plan by name, so the page
     * can switch one card between them. Ordered by the monthly price.
     *
     * @param  list<array<string, mixed>>  $plans
     * @return list<array{name: string, month: ?array, year: ?array}>
     */
    private function pricingTiers(array $plans): array
    {
        $tiers = [];
        foreach ($plans as $plan) {
            $key = mb_strtolower(trim((string) ($plan['name'] ?? '')));
            $tiers[$key] ??= ['name' => (string) ($plan['name'] ?? ''), 'month' => null, 'year' => null];
            $isYearly = ($plan['interval'] ?? '') === 'year' || (int) ($plan['duration_days'] ?? 0) >= 360;
            $tiers[$key][$isYearly ? 'year' : 'month'] ??= $this->offer($plan);
        }

        foreach ($tiers as &$tier) {
            $month = $tier['month'];
            $year = $tier['year'];
            if ($month !== null && $year !== null && $month['currency'] === $year['currency'] && $month['price'] > 0) {
                $fullYear = $month['price'] * 12;
                $tier['year']['saving'] = $fullYear > $year['price'] ? $fullYear - $year['price'] : null;
                $tier['year']['discount'] = $fullYear > $year['price'] ? (int) round((1 - $year['price'] / $fullYear) * 100) : null;
            }
        }
        unset($tier);

        $tiers = array_values($tiers);
        usort($tiers, fn (array $a, array $b) => ($a['month']['price'] ?? ($a['year']['price'] ?? 0) / 12)
            <=> ($b['month']['price'] ?? ($b['year']['price'] ?? 0) / 12));

        return $tiers;
    }

    /** @param array<string, mixed> $plan */
    private function offer(array $plan): array
    {
        $price = ($plan['price_minor'] ?? $plan['price_cents'] ?? 0) / 100;
        $currency = strtoupper((string) ($plan['currency'] ?? 'USD'));
        $isYearly = ($plan['interval'] ?? '') === 'year' || (int) ($plan['duration_days'] ?? 0) >= 360;
        $days = $plan['duration_days'] ?? null;

        return [
            'price' => $price,
            'currency' => $currency,
            'currency_label' => ['RUB' => '₽', 'USD' => '$', 'EUR' => '€', 'TRY' => '₺'][$currency] ?? $currency,
            'period' => $isYearly ? __('site.pricing.period_year')
                : ($days ? trans_choice('site.pricing.period_days', (int) $days, ['days' => $days])
                : (in_array($plan['interval'] ?? '', ['month', 'week'], true) ? __('site.pricing.period_'.$plan['interval']) : __('site.pricing.period_other'))),
            'per_month' => $isYearly ? $price / 12 : null,
            'saving' => null,
            'discount' => null,
            'devices' => $plan['device_limit'] ?? null,
            'traffic' => $plan['traffic_limit_bytes'] ?? null,
            'concurrent' => $plan['concurrent_connection_limit'] ?? null,
        ];
    }

    public function access(): View
    {
        return view('access');
    }

    public function download(): View
    {
        return view('download');
    }

    public function terms(): View
    {
        return view('legal.'.Locales::current().'.terms');
    }

    public function privacy(): View
    {
        return view('legal.'.Locales::current().'.privacy');
    }

    public function sitemap(): Response
    {
        return response()
            ->view('sitemap', ['pages' => array_keys(Locales::PAGES), 'locales' => array_keys(Locales::SUPPORTED)])
            ->header('Content-Type', 'application/xml; charset=utf-8');
    }

    public function manifest(): \Illuminate\Http\JsonResponse
    {
        $locale = Locales::current();

        return response()->json([
            'name' => 'WAVEBREAK',
            'short_name' => 'WAVEBREAK',
            'description' => __('site.meta.description_default'),
            'lang' => $locale,
            'start_url' => Locales::path('home'),
            'display' => 'browser',
            'background_color' => '#020507',
            'theme_color' => '#020507',
            'icons' => [
                ['src' => '/images/favicon.png', 'sizes' => '192x192', 'type' => 'image/png'],
                ['src' => '/images/apple-touch-icon.png', 'sizes' => '180x180', 'type' => 'image/png'],
            ],
        ], 200, ['Content-Type' => 'application/manifest+json']);
    }
}
