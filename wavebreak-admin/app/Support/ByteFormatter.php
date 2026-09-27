<?php

namespace App\Support;

/**
 * Human-readable traffic in binary units (1 GB = 1024^3 bytes), the same
 * base Core uses for plan limits.
 */
final class ByteFormatter
{
    private const UNITS = ['B', 'KB', 'MB', 'GB', 'TB'];

    public static function format(?int $bytes, int $precision = 2): string
    {
        if ($bytes === null) {
            return '∞';
        }
        $value = (float) max(0, $bytes);
        $unit = 0;
        while ($value >= 1024 && $unit < count(self::UNITS) - 1) {
            $value /= 1024;
            $unit++;
        }
        $number = number_format($value, $unit === 0 ? 0 : $precision, '.', ' ');
        if (str_contains($number, '.')) {
            $number = rtrim(rtrim($number, '0'), '.');
        }

        return $number.' '.self::UNITS[$unit];
    }
}
