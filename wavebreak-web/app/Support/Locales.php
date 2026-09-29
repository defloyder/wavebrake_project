<?php

namespace App\Support;

/**
 * The site's languages and its localized URL scheme: Russian at the root,
 * every other language under its own prefix (/en, /tr).
 */
class Locales
{
    public const DEFAULT = 'ru';

    /** code => [label, native name, og:locale] */
    public const SUPPORTED = [
        'ru' => ['RU', 'Русский', 'ru_RU'],
        'en' => ['EN', 'English', 'en_US'],
        'tr' => ['TR', 'Türkçe', 'tr_TR'],
    ];

    /** Localized page keys and their unprefixed paths. */
    public const PAGES = [
        'home' => '/',
        'pricing' => '/pricing',
        'access' => '/access',
        'download' => '/download',
        'terms' => '/terms',
        'privacy' => '/privacy',
    ];

    public static function current(): string
    {
        $locale = app()->getLocale();

        return isset(self::SUPPORTED[$locale]) ? $locale : self::DEFAULT;
    }

    /** Relative URL of a page in a locale (the current one by default). */
    public static function path(string $page, ?string $locale = null): string
    {
        $locale ??= self::current();
        $path = self::PAGES[$page] ?? $page;
        $prefix = $locale === self::DEFAULT ? '' : '/'.$locale;

        return $path === '/' ? ($prefix ?: '/') : $prefix.$path;
    }

    public static function url(string $page, ?string $locale = null): string
    {
        return 'https://wavebreak.com.tr'.self::path($page, $locale);
    }

    /** Page key of the current request, e.g. "pricing" for route "en.pricing". */
    public static function page(): ?string
    {
        $name = request()->route()?->getName();

        return $name ? substr($name, strpos($name, '.') + 1) : null;
    }
}
