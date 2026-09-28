<?php

namespace Tests\Feature;

use Illuminate\Support\Facades\Http;
use Tests\TestCase;

class PublicSiteTest extends TestCase
{
    public function test_all_public_pages_share_navigation_branding_and_footer(): void
    {
        Http::fake(['*' => Http::response(['plans' => []])]);

        foreach (['/', '/pricing', '/access', '/download'] as $path) {
            $response = $this->get($path)->assertOk()
                ->assertSee('class="site-footer"', false)
                ->assertSee('id="main"', false)
                ->assertSee('images/wavebreak-mark.png', false)
                ->assertSee('aria-label="Основная навигация"', false)
                ->assertSee('wavebreak-site.css', false)
                ->assertSee('wavebreak-fonts.css', false)
                ->assertDontSee('fonts.googleapis.com')
                ->assertDontSee('href="/login"', false)
                ->assertDontSee('href="/register"', false);

            $html = $response->getContent();
            $this->assertSame(1, substr_count($html, '<h1'));
            $this->assertSame(1, substr_count($html, '<footer'));
            $this->assertSame(1, substr_count($html, '<header'));
            $this->assertDoesNotMatchRegularExpression('/aura'.'lith|aura'.'lit|Аура'.'лит|\bVPN\b|ВПН/iu', $html);
        }
    }

    public function test_pricing_uses_actual_currency_and_limits_and_excludes_hidden_plans(): void
    {
        Http::fake(['*' => Http::response(['plans' => [
            ['name' => 'Business & Team', 'price_minor' => 16900, 'currency' => 'RUB', 'interval' => 'month', 'device_limit' => 3, 'traffic_limit_bytes' => 10737418240, 'is_active' => true, 'is_public' => true],
            ['name' => 'Hidden plan', 'is_public' => false],
            ['name' => 'Disabled plan', 'is_active' => false],
        ]])]);

        $this->get('/pricing')->assertOk()
            ->assertSee('Business &amp; Team', false)
            ->assertSee('169')
            ->assertSee('₽')
            ->assertSee('10,0 ГБ')
            ->assertDontSee('Hidden plan')
            ->assertDontSee('Disabled plan');
    }

    public function test_pricing_pairs_monthly_and_yearly_plans_behind_a_switch(): void
    {
        Http::fake(['*' => Http::response(['plans' => [
            ['name' => 'Plus', 'price_minor' => 199000, 'currency' => 'RUB', 'interval' => 'year', 'duration_days' => 365, 'device_limit' => 5],
            ['name' => 'Starter', 'price_minor' => 11900, 'currency' => 'RUB', 'interval' => 'month', 'duration_days' => 30, 'device_limit' => 3],
            ['name' => 'Plus', 'price_minor' => 19900, 'currency' => 'RUB', 'interval' => 'month', 'duration_days' => 30, 'device_limit' => 5],
            ['name' => 'Starter', 'price_minor' => 119000, 'currency' => 'RUB', 'interval' => 'year', 'duration_days' => 365, 'device_limit' => 3],
        ]])]);

        $html = $this->get('/pricing')->assertOk()
            ->assertSee('id="period-year"', false)
            ->assertSee('−17%')
            ->assertSee('1 990')
            ->assertSee('≈ 166')
            ->assertSee('выгода 398')
            ->assertSee('≈ 99')
            ->getContent();

        // One card per tier, not per plan; cheapest tier first; month checked by default.
        $this->assertSame(2, substr_count($html, '<article class="plan"'));
        $this->assertLessThan(strpos($html, '<h2>Plus</h2>'), strpos($html, '<h2>Starter</h2>'));
        $this->assertMatchesRegularExpression('/id="period-month"[^>]*checked/', $html);
    }

    public function test_pricing_without_yearly_plans_has_no_switch(): void
    {
        Http::fake(['*' => Http::response(['plans' => [
            ['name' => 'Plus', 'price_minor' => 19900, 'currency' => 'RUB', 'interval' => 'month', 'duration_days' => 30],
        ]])]);

        $this->get('/pricing')->assertOk()
            ->assertSee('199')
            ->assertSee('за 30 дней')
            ->assertDontSee('period-switch', false)
            ->assertDontSee('Только годовая оплата');
    }

    public function test_tier_without_yearly_variant_says_so_in_year_mode(): void
    {
        Http::fake(['*' => Http::response(['plans' => [
            ['name' => 'Plus', 'price_minor' => 19900, 'currency' => 'RUB', 'interval' => 'month'],
            ['name' => 'Plus', 'price_minor' => 199000, 'currency' => 'RUB', 'interval' => 'year'],
            ['name' => 'Starter', 'price_minor' => 11900, 'currency' => 'RUB', 'interval' => 'month'],
        ]])]);

        $this->get('/pricing')->assertOk()->assertSee('Только помесячная оплата');
    }

    public function test_pricing_does_not_invent_prices_when_upstream_is_down(): void
    {
        Http::fake(['*' => Http::response([], 503)]);

        $this->get('/pricing')->assertOk()
            ->assertSee('загрузить цены.')
            ->assertDontSee('Starter')
            ->assertDontSee('Fleet');
    }

    public function test_old_marketing_pages_are_not_served(): void
    {
        foreach (['/b2b', '/cabinet', '/payment.html', '/landing', '/faq'] as $path) {
            $this->get($path)->assertNotFound();
        }
    }
}
