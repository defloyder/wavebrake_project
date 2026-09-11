<?php

namespace App\Console\Commands;

use Illuminate\Console\Command;

class SyncSubscriptionsFromCore extends Command
{
    protected $signature = 'subscriptions:sync';
    protected $description = 'Sync subscriptions from Core API to Laravel database';

    public function handle(): int
    {
        $this->info('Starting subscription sync from Core API...');

        return $this->call('core:sync');
    }
}
