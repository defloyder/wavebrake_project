import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
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

  static final _email = RegExp(r'[\w.+-]+@[\w-]+\.[\w.]+');
  static final _link =
      RegExp(r'\b(vless|vmess|trojan|ss|hysteria2|hy2|tuic)://\S+');
  static final _uuid = RegExp(
      r'\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b');
  static final _secret = RegExp(r'\b[A-Za-z0-9_\-]{32,}\b');

  /// The last [n] lines for the in-app "Logs" tab, newest last, with
  /// emails, connection links, ids and long tokens masked — this is shown
  /// on screen, not exported.
  static List<String> recent([int n = 80]) {
    final lines =
        _buffer.length > n ? _buffer.skip(_buffer.length - n) : _buffer;
    return [
      for (final l in lines)
        l
            .replaceAll(_link, '<link>')
            .replaceAll(_email, '<email>')
            .replaceAll(_uuid, '<id>')
            .replaceAll(_secret, '<…>'),
    ];
  }

  /// Writes the current buffer to a plain text file in the app's cache
  /// dir and returns it, ready to hand to a share sheet — see
  /// features/settings/diagnostics.dart. Overwrites the same filename
  /// each time rather than accumulating one file per export; this is
  /// meant to be shared immediately, not kept as a history.
  static Future<File> exportToFile() async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/wavebreak-diagnostic-log.txt');
    // Real version+build (bug 1): the flavor alone always read
    // "production" and never said which release produced the log.
    var version = 'unknown';
    try {
      final info = await PackageInfo.fromPlatform();
      version = '${info.version}+${info.buildNumber}';
    } catch (_) {}
    final header =
        'WAVEBREAK diagnostic log — exported ${DateTime.now().toIso8601String()}\n'
        'App version: $version (${AppEnv.flavor})\n'
        '${'-' * 60}\n';
    // The VPN service keeps its own log on disk (network changes, screen
    // off/on, health checks, reconnects) — it survives the app being
    // closed, unlike the buffer above.
    var engine = '';
    if (Platform.isAndroid) {
      try {
        engine = await const MethodChannel('app.wavebreak/vpn_state')
                .invokeMethod<String>('engineLog') ??
            '';
      } catch (_) {}
    }
    await file.writeAsString(header +
        _buffer.join('\n') +
        (engine.isEmpty
            ? ''
            : '\n\n${'-' * 60}\nVPN service log\n${'-' * 60}\n$engine'));
    return file;
  }
}
