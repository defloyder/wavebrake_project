<?php

use Illuminate\Foundation\Application;
use Illuminate\Foundation\Configuration\Exceptions;
use Illuminate\Foundation\Configuration\Middleware;
use App\Http\Middleware\AdminOnly;
use Symfony\Component\HttpKernel\Exception\TooManyRequestsHttpException;

return Application::configure(basePath: dirname(__DIR__))
    ->withRouting(
        web: __DIR__.'/../routes/web.php',
        api: __DIR__.'/../routes/api.php',
        commands: __DIR__.'/../routes/console.php',
        health: '/up',
    )
    ->withMiddleware(function (Middleware $middleware): void {
        $middleware->alias([
            'admin' => AdminOnly::class,
        ]);

        $middleware->validateCsrfTokens(except: [
            'webhook/telegram-link',
            'api/webhook/telegram-link',
            'webhook/telegram-recovery',
            'api/webhook/telegram-recovery',
            'api/webhook/password-change-confirm',
            'api/webhook/sync-subscription',
            'api/webhook/sync-user',
            'payment/webhook',
            'payment/cloudpayments/check',
            'payment/cloudpayments/pay',
            'payment/cloudpayments/fail',
            'payment/cloudpayments/cancel',
            'payment/cloudpayments/webhook',
            'webhook/cloudpayments/pay',
        ]);
    })
    ->withExceptions(function (Exceptions $exceptions): void {
        $exceptions->render(function (TooManyRequestsHttpException $e, $request) {
            $retryAfter = $e->getHeaders()['Retry-After'] ?? null;
            $seconds = is_numeric($retryAfter) ? (int) $retryAfter : 60;
            $message = 'Слишком много попыток. Подождите ' . max(1, $seconds) . ' сек. и попробуйте снова.';

            if ($request->expectsJson()) {
                return response()->json([
                    'ok' => false,
                    'error' => 'too_many_requests',
                    'message' => $message,
                    'retry_after' => $seconds,
                ], 429);
            }

            return back()
                ->withInput($request->except(['password', 'password_confirmation']))
                ->withErrors(['identifier' => $message]);
        });
    })->create();
