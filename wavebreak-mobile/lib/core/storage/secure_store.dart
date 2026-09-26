import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../logging/app_logger.dart';

/// Keystore / Keychain backed storage. Never used for connection secrets
/// in application logs.
class SecureStore {
  SecureStore._();

  static late FlutterSecureStorage _storage;

  static const accessToken = 'access_token';
  static const refreshToken = 'refresh_token';
  static const connectionProfile = 'connection_profile';
  static const devicePublicId = 'device_public_id';

  /// Core's server-assigned device id (the primary key, distinct from
  /// [devicePublicId]) — this is what `device_id` means in an access
  /// grant request. Cached after the first successful device
  /// registration so later app launches never re-register.
  static const deviceId = 'device_id';

  static void init(FlutterSecureStorage storage) {
    _storage = storage;
    _cache.clear();
  }

  // Bug 1: Core rotates the refresh token on every refresh, so a new pair
  // that only half-reached Keystore (a write that hangs, which this device
  // family is known to do) meant the next refresh re-sent the old token —
  // Core's reuse detection then revoked every session of the user. The
  // in-process copy is authoritative the moment a pair arrives; Keystore
  // persistence is bounded and best-effort on top of it.
  static const _cachedKeys = {accessToken, refreshToken};
  static final Map<String, String?> _cache = {};
  static const _persistTimeout = Duration(seconds: 5);

  static Future<void> write(String key, String? value) async {
    if (_cachedKeys.contains(key)) _cache[key] = value;
    final op = value == null
        ? _storage.delete(key: key)
        : _storage.write(key: key, value: value);
    if (!_cachedKeys.contains(key)) {
      await op;
      return;
    }
    try {
      await op.timeout(_persistTimeout);
    } catch (e) {
      AppLogger.warn('SecureStore persist of $key stalled/failed: $e');
    }
  }

  static Future<String?> read(String key) async {
    if (_cachedKeys.contains(key) && _cache.containsKey(key)) {
      return _cache[key];
    }
    final value = await _storage.read(key: key);
    if (_cachedKeys.contains(key)) _cache[key] = value;
    return value;
  }

  static Future<void> delete(String key) => write(key, null);

  static Future<void> clearSession() async {
    await delete(accessToken);
    await delete(refreshToken);
    await _storage.delete(key: connectionProfile);
    // Core's device id is per-account (registerDevice() creates a row
    // under whichever account's token is on the request) — leaving it
    // here after logout meant DeviceService.ensureRegistered() saw an
    // already-cached id on the NEXT sign-in and skipped registration
    // entirely, silently reusing a device id that belongs to a totally
    // different account. Confirmed on-device: a fresh account's own
    // Settings ▸ Devices showed nothing, because it had never actually
    // been registered — the app just kept reusing the previous account's
    // device id, which this new account's token can't see or manage.
    await _storage.delete(key: deviceId);
    await _storage.delete(key: devicePublicId);
  }
}
