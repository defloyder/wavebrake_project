<?php

return [

    /*
    |--------------------------------------------------------------------------
    | Third Party Services
    |--------------------------------------------------------------------------
    |
    | This file is for storing the credentials for third party services such
    | as Mailgun, Postmark, AWS and more. This file provides the de facto
    | location for this type of information, allowing packages to have
    | a conventional file to locate the various service credentials.
    |
    */

    'postmark' => [
        'key' => env('POSTMARK_API_KEY'),
    ],

    'resend' => [
        'key' => env('RESEND_API_KEY'),
    ],

    'ses' => [
        'key' => env('AWS_ACCESS_KEY_ID'),
        'secret' => env('AWS_SECRET_ACCESS_KEY'),
        'region' => env('AWS_DEFAULT_REGION', 'us-east-1'),
    ],

    'slack' => [
        'notifications' => [
            'bot_user_oauth_token' => env('SLACK_BOT_USER_OAUTH_TOKEN'),
            'channel' => env('SLACK_BOT_USER_DEFAULT_CHANNEL'),
        ],
    ],

    /*
    |--------------------------------------------------------------------------
    | Telegram Bot
    |--------------------------------------------------------------------------
    */
    'telegram' => [
        'bot_username' => env('TELEGRAM_BOT_USERNAME', 'auralithaccessbot'),
        'bot_token'    => env('TELEGRAM_BOT_TOKEN', ''),
    ],

    /*
    |--------------------------------------------------------------------------
    | Auralith Core API
    |--------------------------------------------------------------------------
    | BASE_URL — адрес Python/FastAPI сервиса
    | ADMIN_KEY — X-Admin-Key для админских эндпоинтов
    */
    'core' => [
        'url'            => env('CORE_API_URL', ''),
        'admin_key'      => env('CORE_ADMIN_KEY', ''),
        'bot_token'      => env('CORE_BOT_TOKEN', 'a64995ea8abba75880267355e2b4ae1c4e776119e0c98b81'),
        'webhook_secret' => env('CORE_WEBHOOK_SECRET', env('CORE_ADMIN_KEY', '')),
    ],

    /*
    |--------------------------------------------------------------------------
    | Node Monitoring API
    |--------------------------------------------------------------------------
    */
    'monitor' => [
        'url'   => env('MONITOR_API_URL', ''),
        'token' => env('MONITOR_API_TOKEN', ''),
    ],

    /*
    |--------------------------------------------------------------------------
    | Freekassa Payment Gateway
    |--------------------------------------------------------------------------
    | Set FREEKASSA_MERCHANT_ID, FREEKASSA_SECRET1, FREEKASSA_SECRET2 in .env
    */
    'freekassa' => [
        'merchant_id'  => env('FREEKASSA_MERCHANT_ID', ''),
        'secret_word1' => env('FREEKASSA_SECRET1', ''),
        'secret_word2' => env('FREEKASSA_SECRET2', ''),
    ],

    /*
    |--------------------------------------------------------------------------
    | CloudPayments
    |--------------------------------------------------------------------------
    | CP_PUBLIC_ID  — публичный ключ (pk_xxxx), используется в JS виджете
    | CP_API_SECRET — секретный ключ для верификации webhook подписи
    */
    'cloudpayments' => [
        'public_id' => env('CP_PUBLIC_ID', ''),
        'api_secret' => env('CP_API_SECRET', ''),
        'receipt' => [
            'enabled' => env('CP_RECEIPT_ENABLED', true),
            'taxation_system' => (int) env('CP_RECEIPT_TAXATION_SYSTEM', 0),
            'vat' => (int) env('CP_RECEIPT_VAT', 0),
            'method' => (int) env('CP_RECEIPT_METHOD', 0),
            'object' => (int) env('CP_RECEIPT_OBJECT', 4),
            'calculation_place' => env('CP_RECEIPT_CALCULATION_PLACE', env('APP_URL')),
        ],
    ],

    /*
    |--------------------------------------------------------------------------
    | Web Push (VAPID)
    |--------------------------------------------------------------------------
    | Generate keys with: php artisan push:generate-vapid-keys
    | VAPID_PUBLIC_KEY  — base64url-encoded uncompressed EC public key (87 chars)
    | VAPID_PRIVATE_KEY — base64url-encoded EC private key (43 chars)
    | VAPID_SUBJECT     — mailto: or https: URL identifying the sender
    */
    'vapid' => [
        'public_key'  => env('VAPID_PUBLIC_KEY', ''),
        'private_key' => env('VAPID_PRIVATE_KEY', ''),
        'subject'     => env('VAPID_SUBJECT', 'mailto:admin@auralith.ru'),
    ],

];
