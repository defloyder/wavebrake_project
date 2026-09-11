<?php

namespace App\Http\Middleware;

use Illuminate\Foundation\Http\Middleware\VerifyCsrfToken as Middleware;

class VerifyCsrfToken extends Middleware
{
    protected $except = [
        'api/webhook/telegram-link',
        'webhook/telegram-link',
        'api/webhook/telegram-recovery',
        'webhook/telegram-recovery',
        'api/webhook/password-change-confirm',
    ];
}
