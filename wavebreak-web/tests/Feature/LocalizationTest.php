<?php

namespace Tests\Feature;

use Illuminate\Support\Facades\Http;
use Tests\TestCase;

class LocalizationTest extends TestCase
{
    private const PAGES = ['', '/pricing', '/access', '/download', '/terms', '/privacy'];

    protected function setUp(): void
    {
        parent::setUp();
        Http::fake(['*' => Http::response(['plans' => [
            ['name' => 'Plus', 'price_minor' => 19900, 'currency' => 'RUB', 'interval' => 'month', 'duration_days' => 30, 'traffic_limit_bytes' => 10737418240],
            ['name' => 'Plus', 'price_minor' => 199000, 'currency' => 'RUB', 'interval' => 'year', 'duration_days' => 365],
        ]])]);
    }

    public function test_english_and_turkish_pages_are_fully_translated(): void
    {
        foreach (['en', 'tr'] as $locale) {
            foreach (self::PAGES as $page) {
                $url = 'https://wavebreak.com.tr/'.$locale.$page;
                $response = $this->get($url)->assertOk()->assertHeader('Content-Language', $locale);
                $html = $response->getContent();

                $this->assertStringContainsString('<html lang="'.$locale.'">', $html, $url);
                $this->assertStringContainsString('<link rel="canonical" href="'.$url.'">', $html, $url);
                $this->assertSame(1, substr_count($html, '<h1'), $url);
                $this->assertDoesNotMatchRegularExpression('/\bVPN\b/i', $html, $url);

                // The only Cyrillic allowed is the language switcher's own name for Russian.
                $visible = str_replace('title="Русский"', '', $html);
                $this->assertDoesNotMatchRegularExpression('/[А-Яа-яЁё]/u', $visible, $url);
            }
        }
    }

    public function test_every_version_links_its_alternates(): void
    {
        foreach (['https://wavebreak.com.tr/pricing', 'https://wavebreak.com.tr/en/pricing', 'https://wavebreak.com.tr/tr/pricing'] as $url) {
            $this->get($url)->assertOk()
                ->assertSee('<link rel="alternate" hreflang="ru" href="https://wavebreak.com.tr/pricing">', false)
                ->assertSee('<link rel="alternate" hreflang="en" href="https://wavebreak.com.tr/en/pricing">', false)
                ->assertSee('<link rel="alternate" hreflang="tr" href="https://wavebreak.com.tr/tr/pricing">', false)
                ->assertSee('<link rel="alternate" hreflang="x-default" href="https://wavebreak.com.tr/en/pricing">', false);
        }
    }

    public function test_switcher_keeps_the_page_and_nav_stays_in_language(): void
    {
        $this->get('https://wavebreak.com.tr/tr/access')->assertOk()
            ->assertSee('href="/access" hreflang="ru"', false)
            ->assertSee('href="/en/access" hreflang="en"', false)
            ->assertSee('href="/tr/pricing"', false)
            ->assertSee('href="/tr/privacy"', false)
            ->assertSee('Teknoloji');
        $this->get('https://wavebreak.com.tr/en')->assertOk()->assertSee('href="/en/download"', false);
    }

    public function test_pricing_uses_locale_number_formats_and_words(): void
    {
        $this->get('https://wavebreak.com.tr/en/pricing')->assertOk()
            ->assertSee('1,990')->assertSee('per 30 days')->assertSee('10.0 GB')->assertSee('from 199 ₽ a Month');
        $this->get('https://wavebreak.com.tr/tr/pricing')->assertOk()
            ->assertSee('1.990')->assertSee('30 gün için')->assertSee('10,0 GB');
    }

    public function test_legal_documents_follow_the_jurisdiction_of_the_language(): void
    {
        $this->get('https://wavebreak.com.tr/tr/privacy')->assertOk()
            ->assertSee('6698 sayılı')->assertSee('KVKK md. 11')->assertSee('Kişisel Verileri Koruma Kurulu');
        $this->get('https://wavebreak.com.tr/tr/terms')->assertOk()
            ->assertSee('Mesafeli Sözleşmeler Yönetmeliği')->assertSee('tüketici hakem heyetlerine');
        $this->get('https://wavebreak.com.tr/en/privacy')->assertOk()
            ->assertSee('GDPR')->assertSee('California Consumer Privacy Act');
        $this->get('https://wavebreak.com.tr/en/terms')->assertOk()
            ->assertSee('withdraw from the agreement within 14 days');
    }

    public function test_sitemap_lists_every_page_in_every_language_with_alternates(): void
    {
        $xml = $this->get('https://wavebreak.com.tr/sitemap.xml')->assertOk()
            ->assertHeader('Content-Type', 'application/xml; charset=utf-8')->getContent();

        $this->assertSame(18, substr_count($xml, '<loc>'));
        $this->assertStringContainsString('<loc>https://wavebreak.com.tr/tr/privacy</loc>', $xml);
        $this->assertStringContainsString('<loc>https://wavebreak.com.tr/en</loc>', $xml);
        $this->assertNotFalse(simplexml_load_string($xml));
    }

    public function test_locale_prefix_trailing_slash_redirects(): void
    {
        $this->get('https://wavebreak.com.tr/en/?ref=x')->assertStatus(301)->assertRedirect('https://wavebreak.com.tr/en?ref=x');
    }
}
