<?php

namespace App\View\Admin\Rows;

use App\Support\ByteFormatter;
use App\View\Admin\StatusBadge;

/** One line of the Plans table; the row opens the plan editor. */
final readonly class PlanRow
{
    private const INTERVALS = ['month' => 'месяц', 'year' => 'год', 'week' => 'неделя', 'day' => 'день'];

    /** @param array<string, mixed> $editable fields the plan editor pre-fills */
    public function __construct(
        public string $id,
        public string $name,
        public string $code,
        public string $description,
        public string $price,
        public int $priceSort,
        public string $term,
        public string $devices,
        public string $traffic,
        public StatusBadge $status,
        public bool $public,
        public string $offer,
        public array $editable,
    ) {}

    /** @param array<string, mixed> $plan Core plan */
    public static function fromCore(array $plan): self
    {
        $minor = (int) ($plan['price_minor'] ?? $plan['price_cents'] ?? 0);
        $interval = (string) ($plan['interval'] ?? 'month');
        $term = isset($plan['duration_days'])
            ? $plan['duration_days'].' дн.'
            : (self::INTERVALS[$interval] ?? $interval);

        return new self(
            id: (string) $plan['id'],
            name: (string) (($plan['name'] ?? '') ?: ($plan['code'] ?? 'Тариф')),
            code: (string) ($plan['code'] ?? ''),
            description: (string) ($plan['description'] ?? ''),
            price: self::money($minor, (string) ($plan['currency'] ?? 'USD')),
            priceSort: $minor,
            term: $term,
            devices: (string) ($plan['device_limit'] ?? '—'),
            traffic: ByteFormatter::format(isset($plan['traffic_limit_bytes']) && $plan['traffic_limit_bytes'] ? (int) $plan['traffic_limit_bytes'] : null),
            status: StatusBadge::plan((bool) ($plan['is_active'] ?? true)),
            public: (bool) ($plan['is_public'] ?? true),
            offer: self::offer($plan),
            editable: [
                'id' => $plan['id'],
                'code' => $plan['code'] ?? '',
                'name' => $plan['name'] ?? '',
                'description' => $plan['description'] ?? '',
                'price' => number_format($minor / 100, 2, '.', ''),
                'currency' => strtoupper((string) ($plan['currency'] ?? 'USD')),
                'interval' => $interval,
                'duration_days' => $plan['duration_days'] ?? '',
                'device_limit' => $plan['device_limit'] ?? 1,
                'traffic_limit_gb' => ByteFormatter::gigabytesInput(isset($plan['traffic_limit_bytes']) ? (int) $plan['traffic_limit_bytes'] : null),
                'is_active' => (bool) ($plan['is_active'] ?? true),
                'is_public' => (bool) ($plan['is_public'] ?? true),
                'original_price' => isset($plan['original_price_minor']) ? number_format(((int) $plan['original_price_minor']) / 100, 2, '.', '') : '',
                'badge' => $plan['badge'] ?? '',
            ],
        );
    }

    /** "было 599,00 ₽ · -17%" — the plan's offer, or "" without one. */
    private static function offer(array $plan): string
    {
        $parts = [];
        if (isset($plan['original_price_minor'])) {
            $parts[] = 'было '.self::money((int) $plan['original_price_minor'], (string) ($plan['currency'] ?? 'USD'));
        }
        if (($plan['badge'] ?? '') !== '') {
            $parts[] = (string) $plan['badge'];
        }

        return implode(' · ', $parts);
    }

    public static function money(int $minor, string $currency): string
    {
        $symbols = ['USD' => '$', 'EUR' => '€', 'RUB' => '₽', 'TRY' => '₺'];
        $amount = number_format($minor / 100, 2, ',', ' ');

        return isset($symbols[$currency]) ? "{$amount} {$symbols[$currency]}" : "{$amount} {$currency}";
    }

    public function search(): string
    {
        return "{$this->name} {$this->code}";
    }
}
