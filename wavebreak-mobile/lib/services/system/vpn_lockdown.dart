import 'dart:io';

import 'package:flutter/services.dart';

/// Android's own kill switch: "Always-on VPN" + "Block connections without
/// VPN" for this app. Only the user can turn it on (an app can't), so the
/// best the app can do is open that system screen.
class VpnLockdown {
  const VpnLockdown._();

  static const _channel = MethodChannel('app.wavebreak/vpn_state');

  static bool get available => Platform.isAndroid;

  static Future<void> openSystemSettings() async {
    if (!available) return;
    try {
      await _channel.invokeMethod('openVpnSettings');
    } catch (_) {
      // Nothing to open on this ROM — leave the user where they are.
    }
  }
}
