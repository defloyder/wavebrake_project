<?php

namespace Tests\Feature;

use App\Services\CoreClient;
use Illuminate\Http\Client\RequestException;
use Illuminate\Http\Client\Response;
use Mockery\MockInterface;
use Tests\TestCase;

class UserManagementTest extends TestCase
{
    public function test_admin_can_create_a_normalized_user_through_json_endpoint(): void
    {
        $this->mock(CoreClient::class, function (MockInterface $mock) {
            $mock->shouldReceive('createUser')->once()->with('access-token', [
                'email' => 'user@example.com',
                'username' => 'operator',
                'password' => 'long-password',
                'role' => 'user',
                'status' => 'active',
            ])->andReturn(['id' => 'user-id', 'email' => 'user@example.com']);
        });

        $this->withSession(['wavebreak_admin_tokens' => ['access_token' => 'access-token']])
            ->postJson('/users', [
                'email' => '  User@Example.COM ',
                'username' => 'operator',
                'password' => 'long-password',
                'role' => 'user',
                'status' => 'active',
            ])
            ->assertOk()
            ->assertJsonPath('data.email', 'user@example.com');
    }

    public function test_duplicate_email_conflict_is_returned_to_the_ui(): void
    {
        $response = new Response(new \GuzzleHttp\Psr7\Response(409, ['Content-Type' => 'application/json'], json_encode([
            'error' => 'email or username already exists',
        ])));
        $exception = new RequestException($response);

        $this->mock(CoreClient::class, function (MockInterface $mock) use ($exception) {
            $mock->shouldReceive('createUser')->once()->andThrow($exception);
        });

        $this->withSession(['wavebreak_admin_tokens' => ['access_token' => 'access-token']])
            ->postJson('/users', [
                'email' => 'user@example.com',
                'username' => '',
                'password' => 'long-password',
                'role' => 'user',
                'status' => 'active',
            ])
            ->assertConflict()
            ->assertJson(['message' => 'email or username already exists']);
    }
}
