{!! '<'.'?xml version="1.0" encoding="UTF-8"?>' !!}
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" xmlns:xhtml="http://www.w3.org/1999/xhtml">
@foreach ($pages as $page)
@foreach ($locales as $locale)
  <url>
    <loc>{{ \App\Support\Locales::url($page, $locale) }}</loc>
    <lastmod>2026-09-29</lastmod>
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
