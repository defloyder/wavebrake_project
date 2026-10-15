import 'dart:io';

import 'package:flutter/services.dart';

/// The WAVEBREAK tile in the phone's Quick Settings (QuickTileService.kt):
/// on Android 13+ the app can ask the system to add it.
class QuickTile {
  const QuickTile._();

  static const _channel = MethodChannel('app.wavebreak/vpn_state');

  static bool get available => Platform.isAndroid;

  /// The system's answer: added, already there, not added — or
  /// [manual] when this Android can't ask (below 13): the user drags the
  /// tile in from the shade's edit screen.
  static Future<QuickTileResult> requestAdd() async {
    try {
      final code = await _channel.invokeMethod<int>('requestAddTile') ?? -1;
      return switch (code) {
        2 => QuickTileResult.added,
        1 => QuickTileResult.alreadyAdded,
        0 => QuickTileResult.notAdded,
        _ => QuickTileResult.manual,
      };
    } catch (_) {
      return QuickTileResult.manual;
    }
  }
}

enum QuickTileResult { added, alreadyAdded, notAdded, manual }
