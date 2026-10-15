<?php

namespace App\View\Admin\Rows;

use App\Support\DisplayDate;
use App\View\Admin\AdminDirectory;
use App\View\Admin\StatusBadge;

/** One line of the Promo codes table; the row opens the promo editor. */
final readonly class PromoCodeRow
{
    /** @param array<string, mixed> $editable fields the promo editor pre-fills */
    public function __construct(
        public string $id,
        public string $code,
        public string $description,
        public string $discount,
        public string $plan,
        public string $validity,
        public string $activations,
        public StatusBadge $status,
        public array $editable,
    ) {}

    /** @param array<string, mixed> $promo Core promo code */
    public static function fromCore(array $promo, AdminDirectory $directory): self
    {
        $type = (string) ($promo['discount_type'] ?? 'percent');
        $value = (int) ($promo['discount_value'] ?? 0);
        $currency = (string) ($promo['currency'] ?? '');
        $discount = $type === 'percent'
            ? "−{$value}%"
            : '−'.PlanRow::money($value, $currency ?: 'USD');
        $planId = (string) ($promo['plan_id'] ?? '');
        $from = $promo['valid_from'] ?? null;
        $until = $promo['valid_until'] ?? null;
        $validity = match (true) {
            $from && $until => DisplayDate::date($from).' — '.DisplayDate::date($until),
            (bool) $until => 'до '.DisplayDate::date($until),
            (bool) $from => 'с '.DisplayDate::date($from),
            default => 'бессрочно',
        };
        $count = (int) ($promo['activations_count'] ?? 0);
        $max = $promo['max_activations'] ?? null;
        $expired = $until && strtotime((string) $until) <= time();
        $exhausted = $max !== null && $count >= (int) $max;

        return new self(
            id: (string) $promo['id'],
            code: (string) ($promo['code'] ?? ''),
            description: (string) ($promo['description'] ?? ''),
            discount: $discount,
            plan: $planId === '' ? 'все тарифы' : $directory->planName($planId),
            validity: $validity,
            activations: $max === null ? "{$count} / ∞" : "{$count} / {$max}",
            status: StatusBadge::promo((bool) ($promo['is_active'] ?? true), $expired, $exhausted),
            editable: [
                'id' => $promo['id'],
                'code' => $promo['code'] ?? '',
                'description' => $promo['description'] ?? '',
                'discount_type' => $type,
                'discount_value' => $type === 'percent' ? $value : number_format($value / 100, 2, '.', ''),
                'currency' => $currency ?: 'RUB',
                'plan_id' => $planId,
                'valid_from' => $from ? DisplayDate::inputDate($from) : '',
                'valid_until' => $until ? DisplayDate::inputDate($until) : '',
                'max_activations' => $max ?? '',
                'is_active' => (bool) ($promo['is_active'] ?? true),
            ],
        );
    }

    public function search(): string
    {
        return "{$this->code} {$this->description}";
    }
}
