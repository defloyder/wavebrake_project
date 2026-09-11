<?php

namespace Database\Seeders;

use App\Models\Plan;
use Illuminate\Database\Seeder;

class PlanSeeder extends Seeder
{
    /**
     * Run the database seeds.
     */
    public function run(): void
    {
        Plan::query()->delete();

        Plan::insert([
            [
                'name' => 'Basic',
                'duration_months' => 1,
                'price_rub' => 169,
                'headline' => 'Доступ к частному сетевому контуру на месяц',
                'features' => json_encode([
                    'Подключение собственных и разрешённых ресурсов',
                    'Управление устройствами в личном кабинете',
                    'Поддержка в рабочее время',
                ], JSON_UNESCAPED_UNICODE),
                'is_highlighted' => false,
                'created_at' => now(),
                'updated_at' => now(),
            ],
            [
                'name' => 'Standard',
                'duration_months' => 3,
                'price_rub' => 449,
                'headline' => 'Частный сетевой контур на три месяца',
                'features' => json_encode([
                    'Экономия относительно помесячной оплаты',
                    'Управление сроком и устройствами',
                    'Для регулярной работы с частной инфраструктурой',
                ], JSON_UNESCAPED_UNICODE),
                'is_highlighted' => true,
                'created_at' => now(),
                'updated_at' => now(),
            ],
            [
                'name' => 'Advanced',
                'duration_months' => 12,
                'price_rub' => 1490,
                'headline' => 'Годовой доступ к частной инфраструктуре',
                'features' => json_encode([
                    'Лучшая цена за месяц',
                    'Управление подключёнными устройствами',
                    'Поддержка по вопросам частного контура',
                ], JSON_UNESCAPED_UNICODE),
                'is_highlighted' => false,
                'created_at' => now(),
                'updated_at' => now(),
            ],
        ]);
    }
}
