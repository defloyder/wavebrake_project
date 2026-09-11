<?php

namespace App\Console\Commands;

use App\Models\PromoCode;
use App\Services\CoreApiService;
use Illuminate\Console\Command;

class SyncPromoCodesFromCore extends Command
{
    protected $signature = 'promo-codes:sync {--limit=500}';
    protected $description = 'Sync promo codes from Core API into Laravel';

    public function __construct(private readonly CoreApiService $core)
    {
        parent::__construct();
    }

    public function handle(): int
    {
        $payload = $this->core->adminPromoCodes((int) $this->option('limit'), 0);
        $rows = $this->extractRows($payload);

        if ($rows === []) {
            $this->warn('No promo codes received from Core API.');
            return self::SUCCESS;
        }

        $synced = 0;

        foreach ($rows as $row) {
            $promo = (object) $row;
            $code = mb_strtoupper(trim((string) ($promo->code ?? '')));

            if ($code === '') {
                continue;
            }

            PromoCode::query()->updateOrCreate(
                ['code' => $code],
                [
                    'type' => $this->normalizeType((string) ($promo->type ?? 'percent')),
                    'value' => (float) ($promo->value ?? $promo->discount ?? $promo->days ?? 0),
                    'is_active' => (bool) ($promo->is_active ?? $promo->active ?? true),
                    'starts_at' => $promo->starts_at ?? null,
                    'expires_at' => $promo->expires_at ?? $promo->valid_until ?? null,
                    'max_uses' => $promo->max_uses ?? $promo->usage_limit ?? null,
                    'used_count' => (int) ($promo->used_count ?? $promo->uses ?? 0),
                ]
            );

            $synced++;
        }

        $this->info("Promo codes synced: {$synced}");

        return self::SUCCESS;
    }

    private function extractRows(?array $payload): array
    {
        if (! $payload) {
            return [];
        }

        if (array_is_list($payload)) {
            return $payload;
        }

        foreach (['promo_codes', 'promocodes', 'promos', 'data', 'items', 'results'] as $key) {
            if (isset($payload[$key]) && is_array($payload[$key])) {
                return $payload[$key];
            }
        }

        return [];
    }

    private function normalizeType(string $type): string
    {
        return match ($type) {
            'fixed', 'amount', 'rub' => 'fixed',
            'duration_days', 'free_days', 'days' => 'duration_days',
            default => 'percent',
        };
    }
}
