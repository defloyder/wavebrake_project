import 'dart:io';

import 'package:flutter/services.dart';

import '../../core/i18n/app_strings.dart';
import '../../core/logging/app_logger.dart';
import '../../core/theme/flag_colors.dart';
import '../core_api/models.dart';
import 'connection_test_service.dart';

/// Feeds WaveEngineVpnService's status-bar notification the one thing it
/// has no way to know on its own: which location this is (name + flag) and
/// what the app's own current-language strings are (Kotlin has no access
/// to AppStrings). Sent once per connect/switch, right alongside the
/// "connect" call — see native_vpn_adapter.dart. Android-only; every call
/// is a no-op elsewhere.
class VpnNotificationMeta {
  const VpnNotificationMeta._();

  static const _channel = MethodChannel('app.wavebreak/vpn_engine');

  static Future<void> update(LocationItem location, AppStrings s) async {
    if (!Platform.isAndroid) return;
    final target = resolvePingTarget(location);
    final label = location.city.isNotEmpty
        ? (location.country.isNotEmpty ? '${location.country}, ${location.city}' : location.city)
        : (location.country.isNotEmpty ? location.country : 'WAVEBREAK');
    AppLogger.debug(
        'VpnNotificationMeta.update: label=$label flag=${location.countryCode} pingTarget=$target');
    try {
      await _channel.invokeMethod('updateNotificationMeta', {
        'locationLabel': label,
        'flagEmoji': location.countryCode.isNotEmpty ? flagEmoji(location.countryCode) : '',
        'pingHost': target?.$1,
        'pingPort': target?.$2,
        'labelConnected': s.connected,
        'labelConnecting': s.connecting,
        'labelFailed': s.errConnectionFailed,
        'labelDisconnect': s.notifDisconnectAction,
        'labelCheckPing': s.testPing,
        'labelPingUnavailable': s.pingUnavailable,
        'labelMeasuring': s.measuringPing,
      });
    } on PlatformException catch (e) {
      // Best-effort — a stale/not-yet-running service just means the next
      // startForeground() call renders with whatever it already had.
      AppLogger.warn('VpnNotificationMeta.update platform error: $e');
    } on MissingPluginException catch (e) {
      AppLogger.warn('VpnNotificationMeta.update missing plugin: $e');
    }
  }
}
