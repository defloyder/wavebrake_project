<?php

namespace Tests\Feature;

use Illuminate\Support\Facades\Http;
use Tests\TestCase;

class ExampleTest extends TestCase
{
    /**
     * A basic test example.
     */
    public function test_the_application_returns_a_successful_response(): void
    {
        Http::fake(['*/healthz' => Http::response(['status' => 'ok'])]);

        $response = $this->get('/');

        $response->assertStatus(200);
    }
}
