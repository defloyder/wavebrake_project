<?php

namespace App\Support;

use Carbon\CarbonImmutable;
use Throwable;

/**
 * Core timestamps (RFC 3339, UTC) as operators read them: local timezone,
 * Russian day-first format, "бессрочно" for the far-future sentinel Core
 * uses for unlimited subscriptions.
 */
final class DisplayDate
{
    /** Core stores "no end date" as a date in year 2100+. */
    private const UNLIMITED_YEAR = 2100;

    public static function parse(?string $value): ?CarbonImmutable
    {
        if ($value === null || trim($value) === '') {
            return null;
        }
        try {
            return CarbonImmutable::parse($value)->setTimezone(self::timezone());
        } catch (Throwable) {
            return null;
        }
    }

    public static function isUnlimited(?string $value): bool
    {
        return (self::parse($value)?->year ?? 0) >= self::UNLIMITED_YEAR;
    }

    public static function dateTime(?string $value, string $empty = '—'): string
    {
        return self::render($value, 'd.m.Y H:i', $empty);
    }

    public static function date(?string $value, string $empty = '—'): string
    {
        return self::render($value, 'd.m.Y', $empty);
    }

    /** "5 минут назад", "через 3 дня". */
    public static function relative(?string $value, string $empty = 'никогда'): string
    {
        $date = self::parse($value);
        if ($date === null) {
            return $empty;
        }
        if ($date->year >= self::UNLIMITED_YEAR) {
            return 'бессрочно';
        }

        return $date->locale('ru')->diffForHumans();
    }

    /** Whole days until $value (negative when past), null if no date/unlimited. */
    public static function daysLeft(?string $value): ?int
    {
        $date = self::parse($value);
        if ($date === null || $date->year >= self::UNLIMITED_YEAR) {
            return null;
        }

        return (int) floor(CarbonImmutable::now(self::timezone())->diffInDays($date, false));
    }

    /** Stable key for client-side sorting (ISO in UTC, "" when empty). */
    public static function sortKey(?string $value): string
    {
        return self::parse($value)?->utc()->format('Y-m-d\TH:i:s') ?? '';
    }

    /** Y-m-d for <input type="date">. */
    public static function inputDate(?string $value): string
    {
        $date = self::parse($value);

        return $date === null || $date->year >= self::UNLIMITED_YEAR ? '' : $date->format('Y-m-d');
    }

    public static function timezone(): string
    {
        return (string) config('services.wavebreak.display_timezone', 'Europe/Istanbul');
    }

    private static function render(?string $value, string $format, string $empty): string
    {
        $date = self::parse($value);
        if ($date === null) {
            return $empty;
        }

        return $date->year >= self::UNLIMITED_YEAR ? 'бессрочно' : $date->format($format);
    }
}
