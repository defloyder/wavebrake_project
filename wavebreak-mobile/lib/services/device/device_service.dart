import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

import '../../core/logging/app_logger.dart';
import '../../core/storage/secure_store.dart';
import '../core_api/core_gateway.dart';
import '../core_api/models.dart';

class DeviceService {
  DeviceService(this._gateway);

  final CoreGateway _gateway;

  /// Core's server-assigned device id — this is the `device_id` an access
  /// grant is created with. Registers the device with Core on first call
  /// and caches the id afterward, so repeat app launches never create a
  /// duplicate device row (Core has no idempotent "upsert by client id"
  /// path; the client only finds out the id after Core creates it).
  Future<String> deviceId() async {
    final existing = await SecureStore.read(SecureStore.deviceId);
    if (existing != null && existing.isNotEmpty) return existing;
    final device = await _register();
    return device.id;
  }

  Future<void> ensureRegistered() async {
    final existing = await SecureStore.read(SecureStore.deviceId);
    if (existing != null && existing.isNotEmpty) return;
    try {
      await _register();
    } catch (_) {
      AppLogger.debug('Device registration skipped');
    }
  }

  Future<DeviceItem> _register() async {
    final (platform, name) = await _platformInfo();
    final device =
        await _gateway.registerDevice(platform: platform, name: name);
    await SecureStore.write(SecureStore.deviceId, device.id);
    await SecureStore.write(SecureStore.devicePublicId, device.publicId);
    return device;
  }

  // Real bug this timeout exists to fix: a login that visibly succeeds
  // (the server call itself returns) but then spins forever with no way
  // out — confirmed cross-platform (both Windows and Android), with the
  // server itself independently confirmed healthy/fast. device_info_plus'
  // platform-channel call (windowsInfo/androidInfo/...) sits in this
  // login->onAuthenticated->ensureRegistered->_platformInfo chain with no
  // timeout anywhere above it — only a try/catch for a call that actually
  // THROWS, which does nothing for one that simply never completes. A
  // hung platform channel call (a real, if uncommon, native-plugin
  // failure mode — no exception, no result, just silence) would explain
  // exactly this symptom on any platform, since this exact code path
  // runs identically on all of them. This is best-effort device
  // registration to begin with (ensureRegistered's own caller already
  // swallows failures) — a slow/hung native call has no business ever
  // blocking sign-in.
  static const _platformInfoTimeout = Duration(seconds: 5);

  Future<(String, String)> _platformInfo() async {
    final info = DeviceInfoPlugin();
    try {
      return await _rawPlatformInfo(info).timeout(_platformInfoTimeout);
    } catch (_) {
      return ('android', 'WAVEBREAK device');
    }
  }

  Future<(String, String)> _rawPlatformInfo(DeviceInfoPlugin info) async {
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        final ios = await info.iosInfo;
        return ('ios', ios.name);
      case TargetPlatform.android:
        final android = await info.androidInfo;
        return ('android', '${android.brand} ${android.model}'.trim());
      case TargetPlatform.windows:
        final windows = await info.windowsInfo;
        return (
          'windows',
          windows.computerName.isNotEmpty
              ? windows.computerName
              : 'Windows device'
        );
      case TargetPlatform.macOS:
        final mac = await info.macOsInfo;
        return (
          'macos',
          mac.computerName.isNotEmpty ? mac.computerName : 'Mac'
        );
      case TargetPlatform.linux:
        final linux = await info.linuxInfo;
        return (
          'linux',
          linux.prettyName.isNotEmpty ? linux.prettyName : 'Linux device'
        );
      case TargetPlatform.fuchsia:
        return ('linux', 'WAVEBREAK device');
    }
  }
}
