<?php

namespace Database\Seeders;

use App\Models\Admin;
use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\Hash;

class AdminSeeder extends Seeder
{
    /**
     * Run the database seeds.
     */
    public function run(): void
    {
        Admin::query()->updateOrCreate(
            ['username' => 'admin'],
            [
                'name' => 'Main Admin',
                'password' => Hash::make('admin123'),
            ]
        );
    }
}
