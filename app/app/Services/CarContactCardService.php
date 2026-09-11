<?php

namespace App\Services;

use App\Models\CarContactCard;
use chillerlan\QRCode\QRCode;
use chillerlan\QRCode\QROptions;
use chillerlan\QRCode\Output\QROutputInterface;
use Illuminate\Support\Facades\File;
use Illuminate\Support\Str;
use RuntimeException;

class CarContactCardService
{
    private const OUTPUT_DIR = 'qr/generated';
    private const BRAND_START = [46, 160, 255];
    private const BRAND_MIDDLE = [162, 89, 255];
    private const BRAND_END = [225, 72, 255];

    public const ACCENTS = [
        'aurora' => [
            'name' => 'Aurora',
            'start' => [46, 160, 255],
            'middle' => [162, 89, 255],
            'end' => [225, 72, 255],
        ],
        'amber' => [
            'name' => 'Amber',
            'start' => [243, 188, 85],
            'middle' => [162, 89, 255],
            'end' => [46, 160, 255],
        ],
        'cyan' => [
            'name' => 'Cyan',
            'start' => [0, 212, 255],
            'middle' => [74, 158, 255],
            'end' => [89, 214, 155],
        ],
        'violet' => [
            'name' => 'Violet',
            'start' => [162, 89, 255],
            'middle' => [225, 72, 255],
            'end' => [46, 160, 255],
        ],
    ];

    public function normalizePhone(string $phone): array
    {
        $digits = preg_replace('/\D+/', '', $phone) ?: '';

        if (strlen($digits) === 10) {
            $digits = '7'.$digits;
        }

        if (strlen($digits) === 11 && str_starts_with($digits, '8')) {
            $digits = '7'.substr($digits, 1);
        }

        if (strlen($digits) < 10 || strlen($digits) > 15) {
            throw new RuntimeException('Некорректный номер телефона.');
        }

        return [
            'digits' => $digits,
            'e164' => '+'.$digits,
            'pretty' => $this->prettyPhone($digits),
        ];
    }

    public function createFromPayload(array $payload): CarContactCard
    {
        $phone = $this->normalizePhone((string) $payload['phone']);
        $whatsappPhone = $payload['whatsapp_phone'] ?? null;
        $whatsapp = $whatsappPhone ? $this->normalizePhone((string) $whatsappPhone)['digits'] : $phone['digits'];

        $card = CarContactCard::query()->create([
            'slug' => $this->uniqueSlug($phone['digits']),
            'phone' => $phone['digits'],
            'phone_e164' => $phone['e164'],
            'phone_pretty' => $phone['pretty'],
            'whatsapp_phone' => $whatsapp,
            'telegram' => $this->normalizeTelegram($payload['telegram'] ?? null),
            'email' => $payload['email'] ?: null,
            'accent_scheme' => 'aurora',
            'message' => $payload['message'] ?: 'Здравствуйте! Я по поводу вашей машины.',
            'is_active' => true,
        ]);

        $this->generateAssets($card);

        return $card->refresh();
    }

    public function generateAssets(CarContactCard $card): void
    {
        if (! extension_loaded('gd')) {
            throw new RuntimeException('На сервере не включено PHP-расширение GD. Установите php8.3-gd и перезапустите PHP-FPM/веб-сервер.');
        }

        $this->ensureOutputDir();
        $qrPath = self::OUTPUT_DIR.'/car-'.$card->slug.'.png';
        $cardPath = self::OUTPUT_DIR.'/car-card-'.$card->slug.'.png';

        $this->generateQr($card->pageUrl(), public_path($qrPath));
        $this->drawCard($card, public_path($qrPath), public_path($cardPath));

        $card->forceFill([
            'qr_path' => $qrPath,
            'card_path' => $cardPath,
        ])->save();
    }

    public function deleteAssets(CarContactCard $card): void
    {
        foreach ([$card->qr_path, $card->card_path] as $path) {
            if ($path && File::exists(public_path($path))) {
                File::delete(public_path($path));
            }
        }
    }

    private function generateQr(string $url, string $path): void
    {
        $options = new QROptions;
        $options->outputType = QROutputInterface::GDIMAGE_PNG;
        $options->outputBase64 = false;
        $options->scale = 24;

        File::put($path, (new QRCode($options))->render($url));
    }

    private function drawCard(CarContactCard $card, string $qrPath, string $outputPath): void
    {
        $template = $this->loadPng(public_path('qr/car-card-9332779343.png'));
        if ($template) {
            $this->drawCardFromTemplate($card, $qrPath, $outputPath, $template);
            return;
        }

        $width = 1500;
        $height = 800;
        $image = imagecreatetruecolor($width, $height);
        imagealphablending($image, true);
        imagesavealpha($image, true);

        $this->fill($image, [8, 11, 17]);
        $this->diagonalTexture($image, $width, $height);

        $accent = self::ACCENTS[$card->accent_scheme] ?? self::ACCENTS['aurora'];
        $leftAccent = $this->color($image, $accent['start']);
        $white = $this->color($image, [248, 251, 255]);
        $muted = $this->color($image, [196, 202, 213]);
        $panel = $this->color($image, [7, 10, 16]);
        $line = $this->color($image, [41, 48, 63]);

        $this->roundedStrokeAccentBrand($image, 42, 42, $width - 42, $height - 42, 28, 5, $leftAccent);

        $font = $this->fontPath('regular');
        $bold = $this->fontPath('bold');
        $extraBold = $this->fontPath('extra');

        $logo = $this->loadPng(public_path('images/logo-mark.png'));
        if ($logo) {
            $this->copyResampled($image, $logo, 250, 145, 90, 90);
            imagedestroy($logo);
        }

        $this->text($image, 'AURALITH', 76, 390, 208, $white, $font, 0, 12);
        $this->gradientBar($image, 245, 288, 868, 296, self::BRAND_START, self::BRAND_END);

        $this->centerTextFit($image, 'ЕСЛИ МОЯ МАШИНА МЕШАЕТ', 37, 245, 870, 376, $white, $font);
        $this->centerTextFit($image, 'ПОЗВОНИТЕ ИЛИ', 58, 245, 870, 458, $white, $extraBold);
        $this->centerTextFit($image, 'НАПИШИТЕ', 58, 245, 870, 526, $white, $extraBold);

        $phoneX1 = 78;
        $phoneY1 = 575;
        $phoneX2 = 1048;
        $phoneY2 = 728;
        $this->roundedStrokeAccentBrand($image, $phoneX1, $phoneY1, $phoneX2, $phoneY2, 26, 4, $leftAccent);
        $this->roundedFill($image, $phoneX1 + 4, $phoneY1 + 4, $phoneX2 - 4, $phoneY2 - 4, 23, $panel);
        $this->circleGradient($image, 168, 650, 56, self::BRAND_START, self::BRAND_END);
        $this->phoneIcon($image, 168, 650);
        imageline($image, 260, 604, 260, 696, $line);
        $this->fitText($image, $card->phone_pretty, 56, 304, 676, $phoneX2 - 344, $white, $extraBold);

        $qrAreaX1 = 1080;
        $qrAreaX2 = 1450;
        $this->centerTextFit($image, 'Отсканируйте QR-код', 21, $qrAreaX1, $qrAreaX2, 176, $muted, $bold);
        $this->centerTextFit($image, 'чтобы написать', 21, $qrAreaX1, $qrAreaX2, 206, $muted, $bold);
        $this->centerTextFit($image, 'владельцу', 21, $qrAreaX1, $qrAreaX2, 236, $muted, $bold);

        $qr = $this->loadPng($qrPath);
        if (! $qr) {
            throw new RuntimeException('QR-код не найден.');
        }

        $this->roundedFill($image, 1092, 264, 1448, 620, 28, $white);
        $this->copyResampled($image, $qr, 1126, 298, 288, 288);
        imagedestroy($qr);

        imagepng($image, $outputPath, 9);
        imagedestroy($image);
    }

    private function drawCardFromTemplate(CarContactCard $card, string $qrPath, string $outputPath, $image): void
    {
        $textWhite = $this->color($image, [248, 251, 255]);
        $panel = $this->color($image, [7, 10, 16]);
        $extraBold = $this->fontPath('extra');

        imagefilledrectangle($image, 286, 596, 1030, 705, $panel);
        $this->fitText($image, $card->phone_pretty, 57, 304, 676, 690, $textWhite, $extraBold);

        $qr = $this->loadPng($qrPath);
        if (! $qr) {
            imagedestroy($image);
            throw new RuntimeException('QR-код не найден.');
        }

        $qrWhite = $this->color($image, [255, 255, 255]);
        imagefilledrectangle($image, 1138, 330, 1436, 620, $qrWhite);
        $this->copyQrResampled($image, $qr, 1185, 354, 238, 238);
        imagedestroy($qr);

        imagepng($image, $outputPath, 9);
        imagedestroy($image);
    }

    private function uniqueSlug(string $phone): string
    {
        do {
            $slug = $phone.'-'.Str::lower(Str::random(6));
        } while (CarContactCard::query()->where('slug', $slug)->exists());

        return $slug;
    }

    private function normalizeTelegram(?string $value): ?string
    {
        $value = trim((string) $value);
        $value = ltrim($value, '@');

        return $value !== '' ? $value : null;
    }

    private function prettyPhone(string $digits): string
    {
        if (strlen($digits) === 11 && str_starts_with($digits, '7')) {
            return '+7 '.substr($digits, 1, 3).' '.substr($digits, 4, 3).' '.substr($digits, 7, 2).' '.substr($digits, 9, 2);
        }

        return '+'.$digits;
    }

    private function ensureOutputDir(): void
    {
        File::ensureDirectoryExists(public_path(self::OUTPUT_DIR));
    }

    private function fontPath(string $weight): string
    {
        $candidates = match ($weight) {
            'extra' => [
                public_path('qr/fonts/Manrope-ExtraBold.ttf'),
                public_path('qr/fonts/Manrope.ttf'),
                '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf',
                '/usr/share/fonts/truetype/freefont/FreeSansBold.ttf',
                'C:\Windows\Fonts\segoeuib.ttf',
                'C:\Windows\Fonts\arialbd.ttf',
            ],
            'bold' => [
                public_path('qr/fonts/Manrope-Bold.ttf'),
                public_path('qr/fonts/Manrope.ttf'),
                '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf',
                '/usr/share/fonts/truetype/freefont/FreeSansBold.ttf',
                'C:\Windows\Fonts\segoeuib.ttf',
                'C:\Windows\Fonts\arialbd.ttf',
            ],
            default => [
                public_path('qr/fonts/Manrope-Regular.ttf'),
                public_path('qr/fonts/Manrope.ttf'),
                '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
                '/usr/share/fonts/truetype/freefont/FreeSans.ttf',
                'C:\Windows\Fonts\segoeui.ttf',
                'C:\Windows\Fonts\arial.ttf',
            ],
        };

        foreach ($candidates as $font) {
            if (File::exists($font) && is_readable($font) && File::size($font) > 1024) {
                return $font;
            }
        }

        throw new RuntimeException('Не найден читаемый TTF-шрифт для генерации макета. Проверьте public/qr/fonts/Manrope.ttf или установите fonts-dejavu-core.');
    }

    private function fill($image, array $rgb): void
    {
        imagefill($image, 0, 0, $this->color($image, $rgb));
    }

    private function color($image, array $rgb): int
    {
        return imagecolorallocate($image, $rgb[0], $rgb[1], $rgb[2]);
    }

    private function diagonalTexture($image, int $width, int $height): void
    {
        $line = imagecolorallocatealpha($image, 255, 255, 255, 122);
        for ($x = -$height; $x < $width; $x += 18) {
            imageline($image, $x, $height, $x + $height, 0, $line);
        }
    }

    private function gradientBar($image, int $x1, int $y1, int $x2, int $y2, array $start, array $end): void
    {
        $width = max(1, $x2 - $x1);
        for ($x = $x1; $x <= $x2; $x++) {
            $t = ($x - $x1) / $width;
            $rgb = [
                (int) round($start[0] + ($end[0] - $start[0]) * $t),
                (int) round($start[1] + ($end[1] - $start[1]) * $t),
                (int) round($start[2] + ($end[2] - $start[2]) * $t),
            ];
            imageline($image, $x, $y1, $x, $y2, $this->color($image, $rgb));
        }
    }

    private function roundedFill($image, int $x1, int $y1, int $x2, int $y2, int $radius, int $color): void
    {
        imagefilledrectangle($image, $x1 + $radius, $y1, $x2 - $radius, $y2, $color);
        imagefilledrectangle($image, $x1, $y1 + $radius, $x2, $y2 - $radius, $color);
        imagefilledellipse($image, $x1 + $radius, $y1 + $radius, $radius * 2, $radius * 2, $color);
        imagefilledellipse($image, $x2 - $radius, $y1 + $radius, $radius * 2, $radius * 2, $color);
        imagefilledellipse($image, $x1 + $radius, $y2 - $radius, $radius * 2, $radius * 2, $color);
        imagefilledellipse($image, $x2 - $radius, $y2 - $radius, $radius * 2, $radius * 2, $color);
    }

    private function roundedStroke($image, int $x1, int $y1, int $x2, int $y2, int $radius, int $thickness, int $startColor, int $endColor): void
    {
        imagesetthickness($image, $thickness);
        imageline($image, $x1 + $radius, $y1, $x2 - $radius, $y1, $startColor);
        imageline($image, $x1 + $radius, $y2, $x2 - $radius, $y2, $endColor);
        imageline($image, $x1, $y1 + $radius, $x1, $y2 - $radius, $startColor);
        imageline($image, $x2, $y1 + $radius, $x2, $y2 - $radius, $endColor);
        imagearc($image, $x1 + $radius, $y1 + $radius, $radius * 2, $radius * 2, 180, 270, $startColor);
        imagearc($image, $x2 - $radius, $y1 + $radius, $radius * 2, $radius * 2, 270, 360, $endColor);
        imagearc($image, $x1 + $radius, $y2 - $radius, $radius * 2, $radius * 2, 90, 180, $startColor);
        imagearc($image, $x2 - $radius, $y2 - $radius, $radius * 2, $radius * 2, 0, 90, $endColor);
        imagesetthickness($image, 1);
    }

    private function roundedStrokeAccentBrand($image, int $x1, int $y1, int $x2, int $y2, int $radius, int $thickness, int $leftColor): void
    {
        $brandPink = $this->color($image, self::BRAND_END);
        $half = max(1, (int) floor($thickness / 2));

        $this->gradientBar($image, $x1 + $radius, $y1 - $half, $x2 - $radius, $y1 + $half, self::BRAND_START, self::BRAND_END);
        $this->gradientBar($image, $x1 + $radius, $y2 - $half, $x2 - $radius, $y2 + $half, self::BRAND_START, self::BRAND_END);

        imagesetthickness($image, $thickness);
        imageline($image, $x1, $y1 + $radius, $x1, $y2 - $radius, $leftColor);
        imageline($image, $x2, $y1 + $radius, $x2, $y2 - $radius, $brandPink);
        imagearc($image, $x1 + $radius, $y1 + $radius, $radius * 2, $radius * 2, 180, 270, $leftColor);
        imagearc($image, $x2 - $radius, $y1 + $radius, $radius * 2, $radius * 2, 270, 360, $brandPink);
        imagearc($image, $x1 + $radius, $y2 - $radius, $radius * 2, $radius * 2, 90, 180, $leftColor);
        imagearc($image, $x2 - $radius, $y2 - $radius, $radius * 2, $radius * 2, 0, 90, $brandPink);
        imagesetthickness($image, 1);
    }

    private function circleGradient($image, int $cx, int $cy, int $radius, array $start, array $end): void
    {
        for ($r = $radius; $r >= 1; $r--) {
            $t = 1 - ($r / $radius);
            $rgb = [
                (int) round($start[0] + ($end[0] - $start[0]) * $t),
                (int) round($start[1] + ($end[1] - $start[1]) * $t),
                (int) round($start[2] + ($end[2] - $start[2]) * $t),
            ];
            imagefilledellipse($image, $cx, $cy, $r * 2, $r * 2, $this->color($image, $rgb));
        }
    }

    private function phoneIcon($image, int $cx, int $cy): void
    {
        $scale = 4;
        $size = 96;
        $icon = imagecreatetruecolor($size * $scale, $size * $scale);
        imagealphablending($icon, false);
        imagesavealpha($icon, true);
        imagefill($icon, 0, 0, imagecolorallocatealpha($icon, 0, 0, 0, 127));
        imagealphablending($icon, true);
        imageantialias($icon, true);

        $black = imagecolorallocatealpha($icon, 5, 7, 11, 0);
        $points = [
            [34, 24],
            [41, 49],
            [55, 63],
            [75, 71],
        ];
        $thickness = 13 * $scale;

        imagesetthickness($icon, $thickness);
        for ($i = 0; $i < count($points) - 1; $i++) {
            [$x1, $y1] = $points[$i];
            [$x2, $y2] = $points[$i + 1];
            $this->thickLine($icon, $x1 * $scale, $y1 * $scale, $x2 * $scale, $y2 * $scale, $thickness, $black);
        }

        foreach ($points as [$x, $y]) {
            imagefilledellipse($icon, $x * $scale, $y * $scale, $thickness, $thickness, $black);
        }

        $this->copyResampled($image, $icon, $cx - 48, $cy - 48, 96, 96);
        imagedestroy($icon);
    }

    private function thickLine($image, int $x1, int $y1, int $x2, int $y2, int $thickness, int $color): void
    {
        $dx = $x2 - $x1;
        $dy = $y2 - $y1;
        $length = max(1, sqrt($dx * $dx + $dy * $dy));
        $offsetX = (int) round(-$dy / $length * $thickness / 2);
        $offsetY = (int) round($dx / $length * $thickness / 2);

        imagefilledpolygon($image, [
            $x1 + $offsetX, $y1 + $offsetY,
            $x1 - $offsetX, $y1 - $offsetY,
            $x2 - $offsetX, $y2 - $offsetY,
            $x2 + $offsetX, $y2 + $offsetY,
        ], $color);
    }

    private function text($image, string $text, int $size, int $x, int $y, int $color, string $font, float $angle = 0, int $letterSpacing = 0, int $weight = 1): void
    {
        if ($letterSpacing <= 0) {
            $this->weightedTtfText($image, $size, $angle, $x, $y, $color, $font, $text, $weight);
            return;
        }

        foreach (mb_str_split($text) as $char) {
            $this->weightedTtfText($image, $size, $angle, $x, $y, $color, $font, $char, $weight);
            $box = imagettfbbox($size, $angle, $font, $char);
            $x += (int) abs($box[2] - $box[0]) + $letterSpacing;
        }
    }

    private function centerText($image, string $text, int $size, int $x1, int $x2, int $y, int $color, string $font, int $weight = 1): void
    {
        $box = imagettfbbox($size, 0, $font, $text);
        $width = abs($box[2] - $box[0]);
        $x = (int) ($x1 + (($x2 - $x1) - $width) / 2);
        $this->weightedTtfText($image, $size, 0, $x, $y, $color, $font, $text, $weight);
    }

    private function centerTextFit($image, string $text, int $maxSize, int $x1, int $x2, int $y, int $color, string $font, int $weight = 1): void
    {
        $size = $this->fitFontSize($text, $maxSize, $x2 - $x1, $font);
        $this->centerText($image, $text, $size, $x1, $x2, $y, $color, $font, $weight);
    }

    private function fitText($image, string $text, int $maxSize, int $x, int $y, int $maxWidth, int $color, string $font, int $weight = 1): void
    {
        $size = $this->fitFontSize($text, $maxSize, $maxWidth, $font);
        $this->weightedTtfText($image, $size, 0, $x, $y, $color, $font, $text, $weight);
    }

    private function fitFontSize(string $text, int $maxSize, int $maxWidth, string $font): int
    {
        for ($size = $maxSize; $size >= 24; $size--) {
            $box = imagettfbbox($size, 0, $font, $text);
            if (abs($box[2] - $box[0]) <= $maxWidth) {
                return $size;
            }
        }

        return 24;
    }

    private function weightedTtfText($image, int $size, float $angle, int $x, int $y, int $color, string $font, string $text, int $weight): void
    {
        $radius = max(0, min(3, $weight - 1));
        $offsets = [[0, 0]];

        for ($distance = 1; $distance <= $radius; $distance++) {
            for ($dx = -$distance; $dx <= $distance; $dx++) {
                for ($dy = -$distance; $dy <= $distance; $dy++) {
                    if (abs($dx) + abs($dy) === $distance) {
                        $offsets[] = [$dx, $dy];
                    }
                }
            }
        }

        foreach ($offsets as [$dx, $dy]) {
            imagettftext($image, $size, $angle, $x + $dx, $y + $dy, $color, $font, $text);
        }
    }

    private function loadPng(string $path)
    {
        return File::exists($path) ? imagecreatefrompng($path) : null;
    }

    private function copyResampled($dest, $src, int $x, int $y, int $w, int $h): void
    {
        imagealphablending($dest, true);
        imagesavealpha($dest, true);
        imagecopyresampled($dest, $src, $x, $y, 0, 0, $w, $h, imagesx($src), imagesy($src));
    }

    private function copyQrResampled($dest, $src, int $x, int $y, int $w, int $h): void
    {
        $bounds = $this->qrContentBounds($src);
        imagecopyresampled(
            $dest,
            $src,
            $x,
            $y,
            $bounds['x'],
            $bounds['y'],
            $w,
            $h,
            $bounds['w'],
            $bounds['h']
        );
    }

    private function qrContentBounds($image): array
    {
        $width = imagesx($image);
        $height = imagesy($image);
        $minX = $width;
        $minY = $height;
        $maxX = 0;
        $maxY = 0;

        for ($y = 0; $y < $height; $y++) {
            for ($x = 0; $x < $width; $x++) {
                $rgb = imagecolorat($image, $x, $y);
                $red = ($rgb >> 16) & 255;
                $green = ($rgb >> 8) & 255;
                $blue = $rgb & 255;

                if ($red < 96 && $green < 96 && $blue < 96) {
                    $minX = min($minX, $x);
                    $minY = min($minY, $y);
                    $maxX = max($maxX, $x);
                    $maxY = max($maxY, $y);
                }
            }
        }

        if ($maxX <= $minX || $maxY <= $minY) {
            return ['x' => 0, 'y' => 0, 'w' => $width, 'h' => $height];
        }

        return [
            'x' => $minX,
            'y' => $minY,
            'w' => $maxX - $minX + 1,
            'h' => $maxY - $minY + 1,
        ];
    }
}
