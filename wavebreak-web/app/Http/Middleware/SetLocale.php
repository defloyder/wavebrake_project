<?php

namespace App\Http\Middleware;

use App\Support\Locales;
use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

class SetLocale
{
    public function handle(Request $request, Closure $next, string $locale = Locales::DEFAULT): Response
    {
        app()->setLocale(isset(Locales::SUPPORTED[$locale]) ? $locale : Locales::DEFAULT);

        $response = $next($request);
        $response->headers->set('Content-Language', app()->getLocale());

        return $response;
    }
}
