import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import '../../core/logging/app_logger.dart';
import '../../core/storage/prefs_store.dart';
import '../../core/storage/secure_store.dart';

/// Thrown by [PinService.verify] when the stored PIN can't be read at all
/// (Keystore hung past the timeout on an install that predates the
/// prefs copy) — the lock screen says so instead of silently waiting.
class PinUnavailableException implements Exception {
  const PinUnavailableException();
}

/// A local app-lock PIN — never sent anywhere, never recoverable. Only a
/// salted hash is persisted; [PrefsStore.pinEnabled] mirrors "is one set"
/// as a fast sync flag so the lock gate can decide whether to show a PIN
/// pad without an async round trip on every app launch.
///
/// Real-device bug this layout fixes: on some phones (the Xiaomi family
/// this app is tested on — see SecureStore's own note) a Keystore read can
/// hang with no result and no error. The lock screen awaited that read on
/// every PIN attempt, so a correct PIN "did nothing". The hash now lives in
/// memory once loaded and in app-private prefs; Keystore is only a
/// migration source for older installs and is always read with a timeout.
class PinService {
  const PinService();

  static const _hashKey = 'pin_hash';
  static const _saltKey = 'pin_salt';
  static const _keystoreTimeout = Duration(seconds: 4);

  /// Shortest and longest PIN the setup screen accepts.
  static const minLength = 4;
  static const maxLength = 6;

  static String? _salt;
  static String? _hash;

  bool get isSet => PrefsStore.getBool(PrefsStore.pinEnabled);

  /// The set PIN's length, so the lock screen checks it the moment the
  /// last digit is typed. Null for a PIN set before this was recorded.
  int? get length => PrefsStore.getInt(PrefsStore.pinLength);

  Future<void> setPin(String pin) async {
    final salt = _randomSalt();
    final hash = _hashOf(pin, salt);
    _salt = salt;
    _hash = hash;
    await PrefsStore.setString(PrefsStore.pinSalt, salt);
    await PrefsStore.setString(PrefsStore.pinHash, hash);
    await PrefsStore.setInt(PrefsStore.pinLength, pin.length);
    await PrefsStore.setBool(PrefsStore.pinEnabled, true);
    // Older builds read Keystore; drop what they left so a stale hash
    // can't come back through the migration path below.
    unawaited(_deleteKeystoreCopy());
  }

  /// Throws [PinUnavailableException] when no stored PIN can be read.
  Future<bool> verify(String pin) async {
    if (!await _load()) {
      if (!isSet) return false;
      throw const PinUnavailableException();
    }
    return _hashOf(pin, _salt!) == _hash;
  }

  /// Loads the stored PIN ahead of the first attempt (called at startup).
  Future<void> warmUp() async {
    try {
      await _load();
    } catch (_) {}
  }

  Future<void> clear() async {
    _salt = null;
    _hash = null;
    await PrefsStore.setString(PrefsStore.pinSalt, null);
    await PrefsStore.setString(PrefsStore.pinHash, null);
    await PrefsStore.setInt(PrefsStore.pinLength, null);
    await PrefsStore.setBool(PrefsStore.pinEnabled, false);
    await _deleteKeystoreCopy();
  }

  /// True once salt and hash are in memory: from memory, prefs, or (for a
  /// PIN set by an older build) Keystore, copied to prefs on success.
  Future<bool> _load() async {
    if (_salt != null && _hash != null) return true;
    final salt = PrefsStore.getString(PrefsStore.pinSalt);
    final hash = PrefsStore.getString(PrefsStore.pinHash);
    if (salt != null && hash != null) {
      _salt = salt;
      _hash = hash;
      return true;
    }
    try {
      final keySalt = await SecureStore.read(_saltKey).timeout(_keystoreTimeout);
      final keyHash = await SecureStore.read(_hashKey).timeout(_keystoreTimeout);
      if (keySalt == null || keyHash == null) return false;
      _salt = keySalt;
      _hash = keyHash;
      await PrefsStore.setString(PrefsStore.pinSalt, keySalt);
      await PrefsStore.setString(PrefsStore.pinHash, keyHash);
      return true;
    } on TimeoutException {
      AppLogger.warn('PIN: Keystore read timed out');
      return false;
    }
  }

  Future<void> _deleteKeystoreCopy() async {
    try {
      await SecureStore.delete(_saltKey).timeout(_keystoreTimeout);
      await SecureStore.delete(_hashKey).timeout(_keystoreTimeout);
    } catch (_) {}
  }

  String _randomSalt() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return base64UrlEncode(bytes);
  }

  String _hashOf(String pin, String salt) =>
      sha256.convert(utf8.encode('$salt:$pin')).toString();
}
