import 'dart:async';
import 'dart:io';

/// The app's log on disk: %LOCALAPPDATA%\WAVEBREAK\logs\wavebreak-YYYYMMDD.log
/// (one file per day, a week kept). Written synchronously from the first
/// line of main(), before Flutter or any plugin runs — so a start that
/// fails (a white window on someone's machine) still leaves a trace the
/// user can send. No plugins (path_provider needs the engine).
class FileLog {
  FileLog._();

  static File? _file;

  /// %LOCALAPPDATA%\WAVEBREAK\logs (or a temp dir if that is unknown).
  static String get directory {
    final base = Platform.environment['LOCALAPPDATA'] ??
        Platform.environment['APPDATA'] ??
        Directory.systemTemp.path;
    return '$base${Platform.pathSeparator}WAVEBREAK${Platform.pathSeparator}logs';
  }

  static String? get path => _file?.path;

  static void init() {
    if (_file != null) return;
    try {
      final dir = Directory(directory)..createSync(recursive: true);
      final now = DateTime.now();
      final day = '${now.year}${_two(now.month)}${_two(now.day)}';
      _file = File('${dir.path}${Platform.pathSeparator}wavebreak-$day.log');
      _prune(dir, now);
    } catch (_) {
      _file = null;
    }
  }

  static final _pending = StringBuffer();
  static Timer? _flushTimer;
  static bool _buffered = false;

  /// From the first frame on: lines are collected and written twice a
  /// second, not one synchronous, flushed write each on the UI thread —
  /// with the VPN on that was hundreds a minute and made every button and
  /// page switch sluggish (owner, 15.10). Start-up lines before it stay
  /// immediate, so a start that hangs still leaves its trace.
  static void startBuffering() => _buffered = true;

  static void write(String line) {
    if (_file == null) return;
    final text = '${DateTime.now().toIso8601String()} $line\n';
    if (!_buffered) {
      _append(text, flush: true);
      return;
    }
    _pending.write(text);
    _flushTimer ??= Timer(const Duration(milliseconds: 500), flush);
  }

  /// At once, with whatever is still pending (errors and crashes).
  static void writeNow(String line) {
    if (_file == null) return;
    _pending.write('${DateTime.now().toIso8601String()} $line\n');
    flush(sync: true);
  }

  static void flush({bool sync = false}) {
    _flushTimer?.cancel();
    _flushTimer = null;
    if (_pending.isEmpty) return;
    final text = _pending.toString();
    _pending.clear();
    _append(text, flush: sync);
  }

  static void _append(String text, {required bool flush}) {
    final f = _file;
    if (f == null) return;
    try {
      f.writeAsStringSync(text, mode: FileMode.append, flush: flush);
    } catch (_) {
      // A log that can't be written must never break the app.
    }
  }

  static void _prune(Directory dir, DateTime now) {
    for (final e in dir.listSync()) {
      if (e is! File || !e.path.endsWith('.log')) continue;
      try {
        if (now.difference(e.lastModifiedSync()).inDays > 7) e.deleteSync();
      } catch (_) {}
    }
  }

  static String _two(int v) => v.toString().padLeft(2, '0');
}
