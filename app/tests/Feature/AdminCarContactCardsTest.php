<?php

namespace Tests\Feature;

use App\Models\Admin;
use App\Models\CarContactCard;
use App\Services\NodeMonitorService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Tests\TestCase;

class AdminCarContactCardsTest extends TestCase
{
    use RefreshDatabase;

    public function test_admin_can_generate_car_contact_page_qr_and_print_card(): void
    {
        $admin = $this->admin();
        $this->fakeNodeMonitor();

        $this->withSession(['admin_id' => $admin->id, 'admin_name' => $admin->name])
            ->get(route('admin.car-cards.create'))
            ->assertOk()
            ->assertSee('Создать QR-карточку для авто', false);

        $response = $this->withSession(['admin_id' => $admin->id, 'admin_name' => $admin->name])
            ->post(route('admin.car-cards.store'), [
                'phone' => '+7 901 222 33 44',
                'whatsapp_phone' => '',
                'telegram' => '@client_user',
                'email' => 'client@example.test',
                'message' => 'Здравствуйте! Машина мешает.',
            ]);

        $card = CarContactCard::query()->firstOrFail();
        $response->assertRedirect(route('admin.car-cards.show', $card));

        $this->assertSame('79012223344', $card->phone);
        $this->assertSame('+7 901 222 33 44', $card->phone_pretty);
        $this->assertSame('client_user', $card->telegram);
        $this->assertNotNull($card->qr_path);
        $this->assertNotNull($card->card_path);
        $this->assertFileExists(public_path($card->qr_path));
        $this->assertFileExists(public_path($card->card_path));

        $this->get('/car/'.$card->slug)
            ->assertOk()
            ->assertSee('tel:+79012223344', false)
            ->assertSee('https://wa.me/79012223344', false)
            ->assertSee('https://t.me/client_user', false)
            ->assertSee('mailto:client@example.test', false);

        $this->withSession(['admin_id' => $admin->id, 'admin_name' => $admin->name])
            ->get(route('admin.car-cards.index'))
            ->assertOk()
            ->assertSee('+7 901 222 33 44', false)
            ->assertDontSee('1 вариант', false);

        $qrPath = public_path($card->qr_path);
        $cardPath = public_path($card->card_path);

        $this->withSession(['admin_id' => $admin->id, 'admin_name' => $admin->name])
            ->delete(route('admin.car-cards.destroy', $card))
            ->assertRedirect(route('admin.car-cards.index'));

        $this->assertDatabaseMissing('car_contact_cards', ['id' => $card->id]);
        $this->assertFileDoesNotExist($qrPath);
        $this->assertFileDoesNotExist($cardPath);
    }

    private function admin(): Admin
    {
        return Admin::query()->create([
            'name' => 'Admin',
            'username' => 'admin',
            'password' => Hash::make('password'),
        ]);
    }

    private function fakeNodeMonitor(): void
    {
        $this->app->instance(NodeMonitorService::class, new class extends NodeMonitorService {
            public function health(): array
            {
                return [
                    'alive_nodes' => 0,
                    'total_nodes' => 0,
                    'avg_load_percent' => 0,
                    'nodes' => [],
                ];
            }
        });
    }
}
