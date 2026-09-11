<?php

namespace App\Services;

use App\Models\ClientRelease;
use Illuminate\Database\Eloquent\Collection;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Str;

class ClientReleaseService
{
    public function __construct(private readonly CoreApiService $core) {}

    public function releases(): Collection
    {
        if (! Schema::hasTable('client_releases')) {
            return new Collection();
        }

        $releases = ClientRelease::defaults();

        $releases->each(function (ClientRelease $release): void {
            $this->applyLatestJson($release);
        });

        return $releases;
    }

    public function stableWindowsRelease(): array
    {
        $fallback = [
            'enabled' => true,
            'version' => null,
            'download_path' => '/downloads/windows/Auralith_Installer.exe',
            'latest_json_path' => $this->defaultLatestJsonPath('stable'),
        ];

        if (! Schema::hasTable('client_releases')) {
            $latest = $this->core->clientLatestJson($fallback['latest_json_path']);
            return $this->mergeLatestIntoArray($fallback, $latest);
        }

        $release = ClientRelease::query()
            ->where('channel', 'stable')
            ->first();

        if (! $release) {
            return $fallback;
        }

        $this->applyLatestJson($release);
        $downloadPath = $release->download_path ?: $fallback['download_path'];
        if (! $this->looksLikeInstallerUrl($downloadPath)) {
            $downloadPath = $fallback['download_path'];
        }

        return [
            'enabled' => (bool) $release->is_enabled,
            'version' => $release->version,
            'download_path' => $downloadPath,
            'latest_json_path' => $release->latest_json_path ?: $fallback['latest_json_path'],
        ];
    }

    private function applyLatestJson(ClientRelease $release): void
    {
        $latestJsonPath = $release->latest_json_path ?: $this->defaultLatestJsonPath($release->channel);
        if ($latestJsonPath && ! $release->latest_json_path) {
            $release->latest_json_path = $latestJsonPath;
        }

        $latest = $this->core->clientLatestJson($latestJsonPath);
        if (! $latest) {
            return;
        }

        $version = $this->latestValue($latest, ['version', 'data.version', 'release.version', 'latest.version']);
        if ($version !== null) {
            $release->version = $version;
            $release->setAttribute('version_source', 'latest.json');
        }

        $downloadPath = $this->latestDownloadPath($latest, $release->latest_json_path);
        if ($downloadPath !== null) {
            $release->download_path = $downloadPath;
        }

        $notes = $this->latestRawValue($latest, ['notes', 'data.notes', 'release.notes', 'latest.notes']);
        if ($notes !== null && $notes !== '') {
            $release->notes = is_array($notes)
                ? implode("\n", array_filter(array_map('strval', $notes)))
                : (string) $notes;
        }
    }

    private function mergeLatestIntoArray(array $release, ?array $latest): array
    {
        if (! $latest) {
            return $release;
        }

        $version = $this->latestValue($latest, ['version', 'data.version', 'release.version', 'latest.version']);
        if ($version !== null) {
            $release['version'] = $version;
        }

        $downloadPath = $this->latestDownloadPath($latest, $release['latest_json_path'] ?? null);
        if ($downloadPath !== null) {
            $release['download_path'] = $downloadPath;
        }

        return $release;
    }

    private function latestDownloadPath(array $latest, ?string $latestJsonPath): ?string
    {
        $fileName = $this->latestValue($latest, [
            'file_name',
            'fileName',
            'data.file_name',
            'data.fileName',
            'release.file_name',
            'release.fileName',
            'latest.file_name',
            'latest.fileName',
        ]);
        if ($fileName !== null && $latestJsonPath) {
            $path = $this->pathNextToLatestJson($latestJsonPath, $fileName);
            if ($path !== null) {
                return $path;
            }
        }

        $value = $this->latestValue($latest, [
            'download_url',
            'downloadUrl',
            'download_path',
            'downloadPath',
            'url',
            'data.download_url',
            'data.downloadUrl',
            'data.download_path',
            'data.downloadPath',
            'data.url',
            'release.download_url',
            'release.downloadUrl',
            'release.download_path',
            'release.downloadPath',
            'release.url',
            'latest.download_url',
            'latest.downloadUrl',
            'latest.download_path',
            'latest.downloadPath',
            'latest.url',
        ]);

        if ($value !== null && $this->looksLikeInstallerUrl($value)) {
            return $value;
        }

        return null;
    }

    private function pathNextToLatestJson(string $latestJsonPath, string $fileName): ?string
    {
        $basePath = preg_replace('~/[^/]*$~', '/', trim($latestJsonPath));
        if (! is_string($basePath) || $basePath === '') {
            return null;
        }

        if (Str::startsWith($basePath, ['http://', 'https://'])) {
            return rtrim($basePath, '/').'/'.ltrim($fileName, '/');
        }

        return rtrim($basePath, '/').'/'.ltrim($fileName, '/');
    }

    private function looksLikeInstallerUrl(string $value): bool
    {
        $path = parse_url($value, PHP_URL_PATH);
        if (! is_string($path) || $path === '') {
            $path = $value;
        }

        return (bool) preg_match('/\.(exe|msi|msix|zip|dmg|pkg|apk)(\?.*)?$/i', $path);
    }

    private function defaultLatestJsonPath(string $channel): ?string
    {
        return match ($channel) {
            'stable' => '/downloads/windows/latest.json',
            default => null,
        };
    }

    private function latestValue(array $latest, array $keys): ?string
    {
        $value = $this->latestRawValue($latest, $keys);
        if ($value === null || is_array($value)) {
            return null;
        }

        $value = trim((string) $value);
        return $value !== '' ? $value : null;
    }

    private function latestRawValue(array $latest, array $keys): mixed
    {
        foreach ($keys as $key) {
            $value = data_get($latest, $key);
            if ($value !== null && $value !== '') {
                return $value;
            }
        }

        return null;
    }
}
