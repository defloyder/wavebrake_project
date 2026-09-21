import 'package:flutter_secure_storage/flutter_secure_storage.dart';

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
  }

  static Future<void> write(String key, String? value) async {
    if (value == null) {
      await _storage.delete(key: key);
      return;
    }
    await _storage.write(key: key, value: value);
  }

  static Future<String?> read(String key) => _storage.read(key: key);

  static Future<void> delete(String key) => _storage.delete(key: key);

  static Future<void> clearSession() async {
    await _storage.delete(key: accessToken);
    await _storage.delete(key: refreshToken);
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
