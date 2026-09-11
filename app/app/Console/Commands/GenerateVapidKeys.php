<?php

namespace App\Console\Commands;

use Illuminate\Console\Command;

class GenerateVapidKeys extends Command
{
    protected $signature   = 'push:generate-vapid-keys';
    protected $description = 'Generate VAPID key pair for Web Push notifications';

    public function handle(): int
    {
        $key = openssl_pkey_new([
            'curve_name'       => 'prime256v1',
            'private_key_type' => OPENSSL_KEYTYPE_EC,
        ]);

        if (! $key) {
            $this->error('Failed to generate EC key pair. Make sure OpenSSL is available.');
            return self::FAILURE;
        }

        $details = openssl_pkey_get_details($key);

        // Public key: uncompressed point (0x04 || x || y), 65 bytes
        $x = str_pad($details['ec']['x'], 32, "\x00", STR_PAD_LEFT);
        $y = str_pad($details['ec']['y'], 32, "\x00", STR_PAD_LEFT);
        $publicKeyRaw = "\x04" . $x . $y;

        // Private key: raw d value, 32 bytes
        $privateKeyRaw = str_pad($details['ec']['d'], 32, "\x00", STR_PAD_LEFT);

        $publicKey  = $this->base64UrlEncode($publicKeyRaw);
        $privateKey = $this->base64UrlEncode($privateKeyRaw);

        $this->info('VAPID keys generated successfully!');
        $this->newLine();
        $this->line('Add these to your <comment>.env</comment> file:');
        $this->newLine();
        $this->line("VAPID_PUBLIC_KEY={$publicKey}");
        $this->line("VAPID_PRIVATE_KEY={$privateKey}");
        $this->line('VAPID_SUBJECT=mailto:admin@auralith.ru');
        $this->newLine();
        $this->comment('Public key length: ' . strlen($publicKey) . ' chars (should be 87)');
        $this->comment('Private key length: ' . strlen($privateKey) . ' chars (should be 43)');

        return self::SUCCESS;
    }

    private function base64UrlEncode(string $data): string
    {
        return rtrim(strtr(base64_encode($data), '+/', '-_'), '=');
    }
}
