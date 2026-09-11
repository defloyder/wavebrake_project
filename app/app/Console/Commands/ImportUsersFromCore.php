<?php

namespace App\Console\Commands;

use App\Models\User;
use App\Services\CoreApiService;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;

class ImportUsersFromCore extends Command
{
    protected $signature = 'users:import';
    protected $description = 'Import users from Core API to Laravel database';

    public function __construct(private readonly CoreApiService $core)
    {
        parent::__construct();
    }

    public function handle(): int
    {
        $this->info('Starting user import from Core API...');

        // Get all users from Core API
        $coreUsers = $this->core->adminUsers();
        
        if (! $coreUsers) {
            $this->error('Failed to fetch users from Core API');
            return self::FAILURE;
        }

        $imported = 0;

        foreach ($coreUsers as $coreUser) {
            DB::transaction(function () use ($coreUser, &$imported) {
                User::query()->updateOrCreate(
                    ['telegram_id' => $coreUser['telegram_id']],
                    [
                        'name' => $coreUser['username'] ?? 'User' . $coreUser['telegram_id'],
                        'username' => $coreUser['username'] ?? 'user' . $coreUser['telegram_id'],
                        'email' => ($coreUser['username'] ?? 'user' . $coreUser['telegram_id']) . '@auralith.local',
                        'password' => Hash::make('password'), // Default password
                        'token' => $coreUser['token'],
                        'client_uuid' => $coreUser['token'], // Will be updated on first login
                    ]
                );
                $imported++;
            });

            $this->info("Imported user: {$coreUser['username']} (telegram_id: {$coreUser['telegram_id']})");
        }

        $this->info("Import completed: {$imported} users imported");
        return self::SUCCESS;
    }
}
