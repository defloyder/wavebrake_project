<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * Keeps one indexable copy of the site: https://wavebreak.com.tr, no
 * trailing slash. The same app also answers on hosts that exist for
 * transport cover (r./x. subdomains, raw IPs); those stay reachable as-is
 * but are marked noindex, since redirecting them would change what those
 * endpoints serve.
 */
class CanonicalUrl
{
    private const HOST = 'wavebreak.com.tr';

    public function handle(Request $request, Closure $next): Response
    {
        $host = strtolower($request->getHost());

        if ($host === self::HOST || $host === 'www.'.self::HOST) {
            $path = $request->getPathInfo();
            $trimmed = $path !== '/' ? rtrim($path, '/') : $path;

            if ($host !== self::HOST || ! $request->isSecure() || $trimmed !== $path) {
                $query = $request->getQueryString();

                return redirect()->away('https://'.self::HOST.($trimmed ?: '/').($query ? '?'.$query : ''), 301);
            }

            return $next($request);
        }

        $response = $next($request);
        $response->headers->set('X-Robots-Tag', 'noindex, nofollow');

        return $response;
    }
}
