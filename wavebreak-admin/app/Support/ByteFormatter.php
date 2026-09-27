<?php

namespace App\Support;

/**
 * Human-readable traffic in binary units (1 ГБ = 1024^3 bytes), the same
 * base Core uses for plan limits. Labels are Russian everywhere in the UI.
 */
final class ByteFormatter
{
    private const UNITS = ['Б', 'КБ', 'МБ', 'ГБ', 'ТБ'];

    public const GIB = 1073741824;

    public static function format(?int $bytes, int $precision = 2): string
    {
        if ($bytes === null) {
            return 'Безлимит';
        }
        $value = (float) max(0, $bytes);
        $unit = 0;
        while ($value >= 1024 && $unit < count(self::UNITS) - 1) {
            $value /= 1024;
            $unit++;
        }

        return self::number($value, $unit === 0 ? 0 : $precision).' '.self::UNITS[$unit];
    }

    /** Always in ГБ, for columns that must line up (e.g. "12,5 ГБ"). */
    public static function gigabytes(?int $bytes, int $precision = 2): string
    {
        return $bytes === null ? 'Безлимит' : self::number(max(0, $bytes) / self::GIB, $precision).' ГБ';
    }

    /** Bytes -> ГБ as a plain number for form inputs ("" for unlimited). */
    public static function gigabytesInput(?int $bytes): string
    {
        if ($bytes === null) {
            return '';
        }

        return rtrim(rtrim(number_format($bytes / self::GIB, 2, '.', ''), '0'), '.');
    }

    private static function number(float $value, int $precision): string
    {
        $number = number_format($value, $precision, ',', ' ');
        if (str_contains($number, ',')) {
            $number = rtrim(rtrim($number, '0'), ',');
        }

        return $number;
    }
}
