<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Collection;
use Illuminate\Database\Eloquent\Model;

class ClientRelease extends Model
{
    public const CHANNELS = [
        'stable' => 'Актуальная',
        'prerelease' => 'Предрелиз',
        'test' => 'Тестовая',
    ];

    protected $fillable = [
        'channel',
        'label',
        'version',
        'download_path',
        'latest_json_path',
        'notes',
        'is_enabled',
    ];

    protected function casts(): array
    {
        return [
            'is_enabled' => 'boolean',
        ];
    }

    public static function defaults(): Collection
    {
        foreach (self::CHANNELS as $channel => $label) {
            self::query()->firstOrCreate(
                ['channel' => $channel],
                ['label' => $label, 'is_enabled' => true],
            );
        }

        return self::query()
            ->whereIn('channel', array_keys(self::CHANNELS))
            ->get()
            ->sortBy(fn (self $release): int => array_search($release->channel, array_keys(self::CHANNELS), true))
            ->values();
    }
}
