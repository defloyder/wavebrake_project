<?php

namespace App\Http\Controllers;

use App\Models\User;
use App\Models\UserWebAuthnCredential;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\Log;

class UserWebAuthnController extends Controller
{
    private string $rpId;
    private string $rpName = 'Auralith';

    public function __construct()
    {
        $appUrl = config('app.url', 'localhost');
        $host = parse_url($appUrl, PHP_URL_HOST) ?? $appUrl;
        $this->rpId = explode(':', $host)[0];
    }

    public function registerChallenge(Request $request): JsonResponse
    {
        $user = Auth::user();
        if (! $user) {
            return response()->json(['error' => 'Unauthorized'], 401);
        }

        $challenge = base64_encode(random_bytes(32));
        $request->session()->put('user_webauthn_register_challenge', $challenge);

        return response()->json([
            'challenge' => $challenge,
            'rp' => ['id' => $this->rpId, 'name' => $this->rpName],
            'user' => [
                'id' => base64_encode((string) $user->id),
                'name' => $user->username,
                'displayName' => $user->name ?? $user->username,
            ],
            'pubKeyCredParams' => [
                ['type' => 'public-key', 'alg' => -7],
                ['type' => 'public-key', 'alg' => -257],
            ],
            'timeout' => 60000,
            'authenticatorSelection' => [
                'authenticatorAttachment' => 'platform',
                'userVerification' => 'required',
            ],
            'attestation' => 'none',
        ]);
    }

    public function registerVerify(Request $request): JsonResponse
    {
        $user = Auth::user();
        if (! $user) {
            return response()->json(['error' => 'Unauthorized'], 401);
        }

        $data = $request->validate([
            'credential_id' => ['required', 'string'],
            'public_key' => ['required', 'string'],
            'device_name' => ['nullable', 'string', 'max:100'],
        ]);

        if (! $request->session()->has('user_webauthn_register_challenge')) {
            return response()->json(['error' => 'No challenge'], 400);
        }

        $existingCredential = UserWebAuthnCredential::query()
            ->where('credential_id', $data['credential_id'])
            ->first();

        if ($existingCredential && (int) $existingCredential->user_id !== (int) $user->id) {
            return response()->json(['error' => 'Credential already registered'], 409);
        }

        UserWebAuthnCredential::query()->updateOrCreate(
            ['credential_id' => $data['credential_id']],
            [
                'user_id' => $user->id,
                'public_key' => $data['public_key'],
                'device_name' => $data['device_name'] ?? 'Устройство',
                'sign_count' => 0,
            ],
        );

        $request->session()->forget('user_webauthn_register_challenge');

        return response()->json(['ok' => true]);
    }

    public function authChallenge(Request $request): JsonResponse
    {
        $challenge = base64_encode(random_bytes(32));
        $request->session()->put('user_webauthn_auth_challenge', $challenge);

        $credentialIds = UserWebAuthnCredential::query()
            ->pluck('credential_id')
            ->map(fn ($id) => ['type' => 'public-key', 'id' => $id])
            ->values();

        return response()->json([
            'challenge' => $challenge,
            'rpId' => $this->rpId,
            'timeout' => 60000,
            'userVerification' => 'required',
            'allowCredentials' => $credentialIds,
        ]);
    }

    public function authVerify(Request $request): JsonResponse
    {
        $data = $request->validate([
            'credential_id' => ['required', 'string'],
            'authenticator_data' => ['required', 'string'],
            'client_data_json' => ['required', 'string'],
            'signature' => ['required', 'string'],
        ]);

        $storedChallenge = $request->session()->get('user_webauthn_auth_challenge');
        if (! $storedChallenge) {
            return response()->json(['error' => 'No challenge'], 400);
        }

        $credential = UserWebAuthnCredential::query()
            ->where('credential_id', $data['credential_id'])
            ->first();

        if (! $credential) {
            return response()->json(['error' => 'Credential not found'], 404);
        }

        try {
            $clientData = json_decode(base64_decode(strtr($data['client_data_json'], '-_', '+/')), true);

            $receivedChallenge = $clientData['challenge'] ?? '';
            $normalizedStored = rtrim(strtr($storedChallenge, '+/', '-_'), '=');
            $normalizedReceived = rtrim(strtr($receivedChallenge, '+/', '-_'), '=');

            if (! hash_equals($normalizedStored, $normalizedReceived)) {
                return response()->json(['error' => 'Challenge mismatch'], 400);
            }

            if (($clientData['type'] ?? '') !== 'webauthn.get') {
                return response()->json(['error' => 'Invalid type'], 400);
            }
        } catch (\Throwable $e) {
            Log::error('User WebAuthn verify error: '.$e->getMessage());
            return response()->json(['error' => 'Verification failed'], 400);
        }

        $request->session()->forget('user_webauthn_auth_challenge');

        $user = User::query()->findOrFail($credential->user_id);
        Auth::login($user, true);
        $request->session()->regenerate();

        $credential->increment('sign_count');

        return response()->json(['ok' => true, 'redirect' => route('profile.index')]);
    }

    public function hasCredentials(): JsonResponse
    {
        return response()->json([
            'has_credentials' => UserWebAuthnCredential::query()->exists(),
        ]);
    }

    public function status(): JsonResponse
    {
        $user = Auth::user();
        $credential = $user
            ? UserWebAuthnCredential::query()
                ->where('user_id', $user->id)
                ->latest()
                ->first()
            : null;

        return response()->json([
            'ok' => true,
            'enabled' => (bool) $credential,
            'credential_id' => $credential?->id,
        ]);
    }

    public function delete(Request $request, int $id): JsonResponse
    {
        $user = Auth::user();
        if (! $user) {
            return response()->json(['error' => 'Unauthorized'], 401);
        }

        UserWebAuthnCredential::query()
            ->where('id', $id)
            ->where('user_id', $user->id)
            ->delete();

        return response()->json(['ok' => true]);
    }

    public function deleteAll(Request $request): JsonResponse
    {
        $user = Auth::user();
        if (! $user) {
            return response()->json(['error' => 'Unauthorized'], 401);
        }

        UserWebAuthnCredential::query()
            ->where('user_id', $user->id)
            ->delete();

        return response()->json(['ok' => true]);
    }
}
