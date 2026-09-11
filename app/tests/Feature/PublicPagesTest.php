<?php

namespace Tests\Feature;

use App\Models\Plan;
use App\Models\Lead;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class PublicPagesTest extends TestCase
{
    use RefreshDatabase;

    public function test_home_page_and_seo_pages_are_available(): void
    {
        Plan::query()->create([
            'name' => 'Advanced',
            'duration_months' => 1,
            'price_rub' => 169,
            'headline' => 'Стабильный доступ',
            'features' => ['Личный кабинет'],
            'is_highlighted' => true,
        ]);

        $this->get('/')
            ->assertOk()
            ->assertSee('Auralith', false)
            ->assertSee('Ауралит', false);

        $this->get('/faq')->assertOk()->assertSee('FAQ', false);
        $this->get('/offer')
            ->assertOk()
            ->assertSee('data-page="offer"', false)
            ->assertSee('Сервис не предназначен для обхода ограничений доступа', false);
        $this->get('/private_policy')
            ->assertOk()
            ->assertSee('data-page="privacy"', false)
            ->assertSee('Согласие даётся отдельным флажком', false);
        $this->get('/legal')
            ->assertOk()
            ->assertSee('data-page="legal-info"', false)
            ->assertSee('Регистрирующий орган', false);
        $this->get('/cookie-policy')
            ->assertOk()
            ->assertSee('data-page="cookie-policy"', false)
            ->assertSee('Аналитические cookie', false);
        $this->get('/sitemap.xml')->assertOk()->assertSee('https://auralith.ru/', false);
    }

    public function test_private_sections_are_not_indexed_publicly(): void
    {
        $this->get('/profile')->assertRedirect('/login');
    }

    public function test_car_contact_pages_are_available_for_qr_codes(): void
    {
        $this->get('/car/9332779343')
            ->assertOk()
            ->assertSee('tel:+79332779343', false)
            ->assertSee('https://wa.me/79332779343', false)
            ->assertSee('https://t.me/defloyder', false)
            ->assertSee('mailto:denizergecher@gmail.com', false)
            ->assertSee('noindex, nofollow', false);

        $this->get('/car/9966566669')
            ->assertOk()
            ->assertSee('tel:+79966566669', false)
            ->assertSee('https://wa.me/79966566669', false)
            ->assertSee('https://t.me/buffliner', false)
            ->assertSee('mailto:buffliner@gmail.com', false);

        $this->assertFileExists(public_path('qr/car-9332779343.png'));
        $this->assertFileExists(public_path('qr/car-9966566669.png'));
        $this->assertFileExists(public_path('qr/car-card-9332779343.png'));
        $this->assertFileExists(public_path('qr/car-card-9966566669.png'));
        $this->assertFileExists(public_path('qr/car-cards.html'));
    }

    public function test_contact_form_requires_explicit_consent(): void
    {
        $payload = [
            'name' => 'Пётр',
            'email' => 'petr@example.test',
            'message' => 'Нужна консультация',
        ];

        $this->postJson('/contact', $payload)
            ->assertUnprocessable()
            ->assertJsonValidationErrors('privacy_consent');

        $this->postJson('/contact', $payload + ['privacy_consent' => '1'])
            ->assertOk()
            ->assertJson(['ok' => true]);

        $this->assertDatabaseCount((new Lead())->getTable(), 1);
    }
}
