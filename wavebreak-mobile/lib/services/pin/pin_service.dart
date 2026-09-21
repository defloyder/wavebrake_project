import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import '../../core/storage/prefs_store.dart';
import '../../core/storage/secure_store.dart';

/// A local app-lock PIN — never sent anywhere, never recoverable. Only a
/// salted hash is persisted (Keystore/Keychain-backed [SecureStore]);
/// [PrefsStore.pinEnabled] just mirrors "is one set" as a fast sync flag
/// so the lock gate can decide whether to show a PIN pad without an
/// async round trip on every app launch.
class PinService {
  const PinService();

  static const _hashKey = 'pin_hash';
  static const _saltKey = 'pin_salt';

  bool get isSet => PrefsStore.getBool(PrefsStore.pinEnabled);

  Future<void> setPin(String pin) async {
    final salt = _randomSalt();
    await SecureStore.write(_saltKey, salt);
    await SecureStore.write(_hashKey, _hash(pin, salt));
    await PrefsStore.setBool(PrefsStore.pinEnabled, true);
  }

  Future<bool> verify(String pin) async {
    final salt = await SecureStore.read(_saltKey);
    final hash = await SecureStore.read(_hashKey);
    if (salt == null || hash == null) return false;
    return _hash(pin, salt) == hash;
  }

  Future<void> clear() async {
    await SecureStore.delete(_saltKey);
    await SecureStore.delete(_hashKey);
    await PrefsStore.setBool(PrefsStore.pinEnabled, false);
  }

  String _randomSalt() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return base64UrlEncode(bytes);
  }

  String _hash(String pin, String salt) =>
      sha256.convert(utf8.encode('$salt:$pin')).toString();
}
