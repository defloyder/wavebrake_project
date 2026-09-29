<?php

namespace Tests\Feature;

use Illuminate\Support\Facades\Http;
use Tests\TestCase;

class SeoTest extends TestCase
{
    protected function setUp(): void
    {
        parent::setUp();
        Http::fake(['*' => Http::response(['plans' => [
            ['name' => 'Starter', 'price_minor' => 11900, 'currency' => 'RUB', 'interval' => 'month', 'duration_days' => 30],
            ['name' => 'Starter', 'price_minor' => 119000, 'currency' => 'RUB', 'interval' => 'year', 'duration_days' => 365],
        ]])]);
    }

    public function test_non_canonical_urls_redirect_permanently_to_https_apex(): void
    {
        $this->get('http://wavebreak.com.tr/pricing')->assertStatus(301)->assertRedirect('https://wavebreak.com.tr/pricing');
        $this->get('https://www.wavebreak.com.tr/')->assertStatus(301)->assertRedirect('https://wavebreak.com.tr/');
        $this->get('https://wavebreak.com.tr/pricing/?a=1')->assertStatus(301)->assertRedirect('https://wavebreak.com.tr/pricing?a=1');
        $this->get('https://wavebreak.com.tr/pricing')->assertOk()->assertHeaderMissing('X-Robots-Tag');
    }

    public function test_cover_hosts_stay_served_but_are_not_indexed(): void
    {
        foreach (['https://r.wavebreak.com.tr/', 'https://x.wavebreak.com.tr/', 'http://45.15.41.3/'] as $url) {
            $this->get($url)->assertOk()->assertHeader('X-Robots-Tag', 'noindex, nofollow');
        }
    }

    public function test_every_page_has_complete_meta_and_valid_structured_data(): void
    {
        foreach (['/', '/pricing', '/access', '/download', '/terms', '/privacy'] as $path) {
            $html = $this->get('https://wavebreak.com.tr'.$path)->assertOk()->getContent();

            $this->assertMatchesRegularExpression('/<title>[^<]{20,70}<\/title>/u', $html, $path);
            preg_match('/<meta name="description" content="([^"]+)"/u', $html, $m);
            $this->assertGreaterThanOrEqual(70, mb_strlen(html_entity_decode($m[1] ?? '')), $path);
            $this->assertLessThanOrEqual(200, mb_strlen(html_entity_decode($m[1] ?? '')), $path);
            $canonical = 'https://wavebreak.com.tr'.$path;
            $this->assertStringContainsString('<link rel="canonical" href="'.$canonical.'">', $html);
            $this->assertStringContainsString('og:image" content="https://wavebreak.com.tr/images/og-cover.png"', $html);
            $this->assertStringContainsString('rel="manifest"', $html);

            preg_match_all('/<script type="application\/ld\+json">(.*?)<\/script>/s', $html, $blocks);
            $this->assertNotEmpty($blocks[1], $path);
            foreach ($blocks[1] as $json) {
                $this->assertIsArray(json_decode($json, true, flags: JSON_THROW_ON_ERROR), $path);
            }
        }
    }

    public function test_page_specific_schema(): void
    {
        $this->get('https://wavebreak.com.tr/')->assertSee('"@type":"FAQPage"', false)->assertSee('"@type":"Organization"', false);
        $this->get('https://wavebreak.com.tr/access')->assertSee('"@type":"FAQPage"', false)->assertSee('"@type":"BreadcrumbList"', false);
        $this->get('https://wavebreak.com.tr/download')->assertSee('"@type":"SoftwareApplication"', false);
        $this->get('https://wavebreak.com.tr/pricing')
            ->assertSee('"@type":"Service"', false)
            ->assertSee('"price":"1190.00"', false)
            ->assertSee('от 119 ₽ в месяц');
    }

    public function test_home_h1_carries_the_positioning(): void
    {
        $html = $this->get('https://wavebreak.com.tr/')->getContent();
        preg_match('/<h1[^>]*>(.*?)<\/h1>/su', $html, $h1);
        $text = trim(preg_replace('/\s+/u', ' ', strip_tags($h1[1] ?? '')));
        $this->assertStringContainsString('Платформа защищённого подключения и управления доступом', $text);
        $this->assertStringContainsString('WAVEBREAK', $text);
    }
}
