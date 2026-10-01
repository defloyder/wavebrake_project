{!! '<'.'?xml version="1.0" encoding="UTF-8"?>' !!}
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" xmlns:xhtml="http://www.w3.org/1999/xhtml">
@php
    // Was a single hardcoded date for all 18 URLs. Most pages map straight
    // to a view file (see Locales::PAGES); terms/privacy instead live one
    // level down per locale (legal/{locale}/{page}.blade.php, each
    // independently translated). Using each file's own mtime gives a real,
    // zero-maintenance lastmod instead of a constant nobody updates.
    $viewPath = fn (string $page, string $locale) => in_array($page, ['terms', 'privacy'], true)
        ? "views/legal/{$locale}/{$page}.blade.php"
        : "views/{$page}.blade.php";
    $lastmod = fn (string $page, string $locale) => date('Y-m-d', filemtime(resource_path($viewPath($page, $locale))));
@endphp
@foreach ($pages as $page)
@foreach ($locales as $locale)
  <url>
    <loc>{{ \App\Support\Locales::url($page, $locale) }}</loc>
    <lastmod>{{ $lastmod($page, $locale) }}</lastmod>
    <changefreq>{{ in_array($page, ['terms', 'privacy']) ? 'yearly' : 'weekly' }}</changefreq>
    <priority>{{ ['home' => '1.0', 'pricing' => '0.9', 'download' => '0.9', 'access' => '0.7'][$page] ?? '0.3' }}</priority>
@foreach ($locales as $alternate)
    <xhtml:link rel="alternate" hreflang="{{ $alternate }}" href="{{ \App\Support\Locales::url($page, $alternate) }}"/>
@endforeach
    <xhtml:link rel="alternate" hreflang="x-default" href="{{ \App\Support\Locales::url($page, 'en') }}"/>
  </url>
@endforeach
@endforeach
</urlset>
