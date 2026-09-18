<?php

namespace Tests\Feature;

// use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class ExampleTest extends TestCase
{
    /**
     * A basic test example.
     */
    public function test_the_application_returns_a_successful_response(): void
    {
        $response = $this->get('/');

        $response->assertStatus(200);
    }

    public function test_download_page_replaces_web_account(): void
    {
        $this->get('/download')
            ->assertOk()
            ->assertSee('Волна меняется.')
            ->assertSee('Ссылки появятся')
            ->assertDontSee('href="/login"', false)
            ->assertDontSee('href="/register"', false);
    }

    public function test_legacy_account_pages_redirect_to_download(): void
    {
        foreach (['/login', '/register', '/dashboard', '/dashboard/devices'] as $path) {
            $this->get($path)->assertRedirect('/download');
        }
    }

    public function test_legacy_account_mutations_cannot_change_customer_data(): void
    {
        $this->post('/subscriptions')->assertRedirect('/download');
        $this->post('/access/grants')->assertRedirect('/download');
        $this->post('/devices')->assertRedirect('/download');
        $this->delete('/telegram')->assertRedirect('/download');
    }
}
