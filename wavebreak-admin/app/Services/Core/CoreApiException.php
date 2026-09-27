<?php

namespace App\Services\Core;

use Illuminate\Http\Client\RequestException;
use RuntimeException;

/**
 * A failed Core call, normalized. Understands both Core error shapes:
 * the account-management model {"error": {"code", "message", "request_id"}}
 * and the legacy {"code": "...", "error": "..."}.
 */
final class CoreApiException extends RuntimeException
{
    public function __construct(
        public readonly string $errorCode,
        string $message,
        public readonly int $status,
        public readonly ?string $requestId = null,
        ?\Throwable $previous = null,
    ) {
        parent::__construct($message, $status, $previous);
    }

    public static function fromRequestException(RequestException $e): self
    {
        $body = $e->response->json();
        $status = $e->response->status();

        if (is_array($body) && is_array($body['error'] ?? null)) {
            $error = $body['error'];

            return new self(
                (string) ($error['code'] ?? 'CORE_ERROR'),
                (string) ($error['message'] ?? 'Core request failed.'),
                $status,
                isset($error['request_id']) ? (string) $error['request_id'] : null,
                $e,
            );
        }

        $code = is_array($body) ? ($body['code'] ?? $body['error'] ?? null) : null;

        return new self(
            is_string($code) && $code !== '' ? $code : 'CORE_ERROR',
            is_string($code) && $code !== '' ? $code : 'Core request failed.',
            $status,
            null,
            $e,
        );
    }

    public function isUnauthenticated(): bool
    {
        return $this->status === 401;
    }
}
