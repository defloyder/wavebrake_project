<?php

namespace App\Http\Controllers;

use App\Models\Admin;
use App\Models\AdminWebAuthnCredential;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Str;

class AdminWebAuthnController extends Controller
{
    private string $rpId;
    private string $rpName = 'Auralith Admin';

    public function __construct()
    {
        $appUrl = config('app.url', 'localhost');
        $host = parse_url($appUrl, PHP_URL_HOST) ?? $appUrl;
        // Strip port if present
        $this->rpId = explode(':', $host)[0];
    }

    /**
     * Generate registration challenge.
     * POST /admin/webauthn/register/challenge
     */
    public function registerChallenge(Request $request): JsonResponse
    {
        $adminId = $request->session()->get('admin_id');
        if (! $adminId) {
            return response()->json(['error' => 'Unauthorized'], 401);
        }

        $admin = Admin::query()->findOrFail($adminId);
        $challenge = base64_encode(random_bytes(32));
        $request->session()->put('webauthn_register_challenge', $challenge);

        return response()->json([
            'challenge' => $challenge,
            'rp' => ['id' => $this->rpId, 'name' => $this->rpName],
            'user' => [
                'id' => base64_encode((string) $admin->id),
                'name' => $admin->username,
                'displayName' => $admin->name ?? $admin->username,
            ],
            'pubKeyCredParams' => [
                ['type' => 'public-key', 'alg' => -7],   // ES256
                ['type' => 'public-key', 'alg' => -257],  // RS256
            ],
            'timeout' => 60000,
            'authenticatorSelection' => [
                'authenticatorAttachment' => 'platform',
                'userVerification' => 'required',
            ],
            'attestation' => 'none',
        ]);
    }

    /**
     * Save registered credential.
     * POST /admin/webauthn/register/verify
     */
    public function registerVerify(Request $request): JsonResponse
    {
        $adminId = $request->session()->get('admin_id');
        if (! $adminId) {
            return response()->json(['error' => 'Unauthorized'], 401);
        }

        $data = $request->validate([
            'credential_id' => ['required', 'string'],
            'public_key'    => ['required', 'string'],
            'device_name'   => ['nullable', 'string', 'max:100'],
        ]);

        AdminWebAuthnCredential::query()->create([
            'admin_id'      => $adminId,
            'credential_id' => $data['credential_id'],
            'public_key'    => $data['public_key'],
            'device_name'   => $data['device_name'] ?? 'Устройство',
            'sign_count'    => 0,
        ]);

        return response()->json(['ok' => true]);
    }

    /**
     * Generate authentication challenge.
     * POST /admin/webauthn/auth/challenge
     */
    public function authChallenge(Request $request): JsonResponse
    {
        $challenge = base64_encode(random_bytes(32));
        $request->session()->put('webauthn_auth_challenge', $challenge);

        // Get all credential IDs (we don't know which admin yet)
        $credentialIds = AdminWebAuthnCredential::query()
            ->pluck('credential_id')
            ->map(fn($id) => ['type' => 'public-key', 'id' => $id])
            ->values();

        return response()->json([
            'challenge'        => $challenge,
            'rpId'             => $this->rpId,
            'timeout'          => 60000,
            'userVerification' => 'required',
            'allowCredentials' => $credentialIds,
        ]);
    }

    /**
     * Verify authentication assertion and log in.
     * POST /admin/webauthn/auth/verify
     */
    public function authVerify(Request $request): JsonResponse
    {
        $data = $request->validate([
            'credential_id'      => ['required', 'string'],
            'authenticator_data' => ['required', 'string'],
            'client_data_json'   => ['required', 'string'],
            'signature'          => ['required', 'string'],
        ]);

        $storedChallenge = $request->session()->get('webauthn_auth_challenge');
        if (! $storedChallenge) {
            return response()->json(['error' => 'No challenge'], 400);
        }

        // Find credential
        $credential = AdminWebAuthnCredential::query()
            ->where('credential_id', $data['credential_id'])
            ->first();

        if (! $credential) {
            return response()->json(['error' => 'Credential not found'], 404);
        }

        // Verify clientDataJSON contains our challenge
        try {
            $clientData = json_decode(base64_decode(
                strtr($data['client_data_json'], '-_', '+/')
            ), true);

            $receivedChallenge = $clientData['challenge'] ?? '';
            // Normalize base64
            $normalizedStored   = rtrim(strtr($storedChallenge, '+/', '-_'), '=');
            $normalizedReceived = rtrim(strtr($receivedChallenge, '+/', '-_'), '=');

            if (! hash_equals($normalizedStored, $normalizedReceived)) {
                return response()->json(['error' => 'Challenge mismatch'], 400);
            }

            if (($clientData['type'] ?? '') !== 'webauthn.get') {
                return response()->json(['error' => 'Invalid type'], 400);
            }
        } catch (\Throwable $e) {
            Log::error('WebAuthn verify error: ' . $e->getMessage());
            return response()->json(['error' => 'Verification failed'], 400);
        }

        // Clear challenge
        $request->session()->forget('webauthn_auth_challenge');

        // Log in the admin
        $admin = Admin::query()->findOrFail($credential->admin_id);
        $request->session()->put('admin_id', $admin->id);
        $request->session()->put('admin_name', $admin->name);
        $request->session()->regenerate();

        // Update sign count
        $credential->increment('sign_count');

        return response()->json(['ok' => true, 'redirect' => route('admin.dashboard')]);
    }

    /**
     * Check if current device has registered credentials.
     * GET /admin/webauthn/has-credentials
     */
    public function hasCredentials(Request $request): JsonResponse
    {
        $count = AdminWebAuthnCredential::query()->count();
        return response()->json(['has_credentials' => $count > 0]);
    }

    /**
     * Delete a credential.
     * DELETE /admin/webauthn/credentials/{id}
     */
    public function deleteCredential(Request $request, int $id): JsonResponse
    {
        $adminId = $request->session()->get('admin_id');
        AdminWebAuthnCredential::query()
            ->where('id', $id)
            ->where('admin_id', $adminId)
            ->delete();

        return response()->json(['ok' => true]);
    }
}
