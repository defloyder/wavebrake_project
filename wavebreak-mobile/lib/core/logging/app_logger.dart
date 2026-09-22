import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../env/app_env.dart';

/// Application logger. Never logs passwords, JWTs, refresh tokens, or
/// connection secrets.
///
/// Also keeps a small rolling in-memory buffer of everything it logs
/// (regardless of the console-only `_verbose` gate below, and regardless
/// of build flavor) — see [exportToFile]. Added specifically because a
/// real-device transport failure report (Hysteria2/REALITY/Direct-TLS)
/// can come from someone with no USB cable/adb access at all: this is
/// the one way to get real diagnostic data back without that. A plain
/// capped list is enough — this is a share-it-once diagnostic tool, not
/// a persistent audit log, so it deliberately does NOT survive an app
/// restart.
class AppLogger {
  AppLogger._();

  static bool _verbose = true;

  // Capped, not unbounded: this only needs to cover roughly "the last
  // thing the user did before reporting a problem," not the device's
  // entire session — an unbounded buffer in a long-lived VPN app that's
  // meant to stay connected for hours would just be a slow memory leak.
  static const _maxLines = 1000;
  static final Queue<String> _buffer = Queue<String>();

  static void init() {
    _verbose = !AppEnv.isProduction;
  }

  static void _record(String line) {
    _buffer.addLast('${DateTime.now().toIso8601String()} $line');
    while (_buffer.length > _maxLines) {
      _buffer.removeFirst();
    }
  }

  static void debug(String message) {
    _record('[WB] $message');
    if (_verbose) {
      debugPrint('[WB] $message');
    }
  }

  static void info(String message) {
    _record('[WB] $message');
    debugPrint('[WB] $message');
  }

  static void warn(String message) {
    _record('[WB][warn] $message');
    debugPrint('[WB][warn] $message');
  }

  static void error(String message) {
    _record('[WB][error] $message');
    debugPrint('[WB][error] $message');
  }

  /// Writes the current buffer to a plain text file in the app's cache
  /// dir and returns it, ready to hand to a share sheet — see
  /// features/settings/diagnostics.dart. Overwrites the same filename
  /// each time rather than accumulating one file per export; this is
  /// meant to be shared immediately, not kept as a history.
  static Future<File> exportToFile() async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/wavebreak-diagnostic-log.txt');
    final header =
        'WAVEBREAK diagnostic log — exported ${DateTime.now().toIso8601String()}\n'
        'App version: ${AppEnv.flavor}\n'
        '${'-' * 60}\n';
    await file.writeAsString(header + _buffer.join('\n'));
    return file;
  }
}
