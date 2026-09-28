import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';

/// Downloads a large file (the update APK) over a path that stalls: Russian
/// mobile carriers freeze or throttle long TCP flows to foreign servers,
/// and the app is excluded from its own tunnel, so a plain one-shot
/// download of ~100 MB often never finishes. This one:
///  - treats [stallTimeout] without a single byte as a dead connection
///    (instead of waiting forever) and reconnects;
///  - resumes from what is already on disk (HTTP Range) instead of starting
///    over, so every reconnect keeps its progress;
///  - moves on to the next URL (e.g. the Moscow mirror, then the main site)
///    when one keeps failing without progress.
class ResumableDownloader {
  ResumableDownloader({
    Dio? dio,
    this.stallTimeout = const Duration(seconds: 15),
    this.maxFailuresPerUrl = 4,
    this.maxAttemptsPerUrl = 40,
    this.retryDelay = const Duration(seconds: 1),
  }) : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 12),
              // Dio applies this between received chunks, not to the whole
              // transfer — exactly a stall detector.
              receiveTimeout: stallTimeout,
            ));

  final Dio _dio;
  final Duration stallTimeout;

  /// Consecutive attempts on one URL that made no progress at all before
  /// giving up on it. An attempt that got any bytes resets the count.
  final int maxFailuresPerUrl;

  /// Connections to one URL in total — a carrier that lets every new
  /// connection through for a few KB and then freezes it would otherwise
  /// keep this "making progress" forever; the next URL may not be throttled.
  final int maxAttemptsPerUrl;
  final Duration retryDelay;

  /// Downloads the first URL of [urls] that works into [path]. [onProgress]
  /// gets (bytes on disk, total or 0 when unknown). Throws the last error
  /// when every URL failed.
  Future<void> download(
    List<String> urls,
    String path, {
    void Function(int received, int total)? onProgress,
  }) async {
    if (urls.isEmpty) throw ArgumentError('no download URLs');
    Object? lastError;
    for (final url in urls) {
      // A partial file from a different URL may be a different file
      // (per-architecture vs universal APK): never resume across URLs.
      final part = File(partPathFor(path, url));
      try {
        await _downloadOne(url, part, onProgress);
        final target = File(path);
        if (await target.exists()) await target.delete();
        await part.rename(path);
        return;
      } catch (error) {
        lastError = error;
        // Kept: tapping "retry" later resumes it. Only a response that
        // can't be trusted to extend it throws it away.
        if (error is _Fatal && await part.exists()) await part.delete();
      }
    }
    throw lastError ?? StateError('download failed');
  }

  Future<void> _downloadOne(
    String url,
    File part,
    void Function(int received, int total)? onProgress,
  ) async {
    var failures = 0;
    var attempts = 0;
    while (true) {
      final before = await part.exists() ? await part.length() : 0;
      try {
        final done = await _attempt(url, part, before, onProgress);
        if (done) return;
      } catch (error) {
        final after = await part.exists() ? await part.length() : 0;
        if (error is _Fatal) rethrow;
        failures = after > before ? 0 : failures + 1;
        if (failures >= maxFailuresPerUrl || ++attempts >= maxAttemptsPerUrl) {
          rethrow;
        }
        await Future<void>.delayed(retryDelay);
      }
    }
  }

  /// One connection. Returns true when the file is complete.
  Future<bool> _attempt(
    String url,
    File part,
    int offset,
    void Function(int received, int total)? onProgress,
  ) async {
    final response = await _dio.get<ResponseBody>(
      url,
      options: Options(
        responseType: ResponseType.stream,
        headers: {if (offset > 0) 'Range': 'bytes=$offset-'},
        // 416 = the partial file is already the whole file (or larger).
        validateStatus: (s) => s != null && (s < 300 || s == 416),
      ),
    );
    final status = response.statusCode ?? 0;
    if (status == 416) {
      await response.data?.stream.drain<void>();
      // Can't tell complete from bogus without a length: start over once.
      await part.delete();
      throw _Retry();
    }
    var start = offset;
    var total = 0;
    if (status == 206) {
      final range = response.headers.value('content-range') ?? '';
      final m = RegExp(r'bytes (\d+)-\d+/(\d+)').firstMatch(range);
      if (m == null || int.parse(m.group(1)!) != offset) {
        throw _Fatal('bad Content-Range: $range');
      }
      total = int.parse(m.group(2)!);
    } else {
      // Server ignored Range: this body is the whole file from byte 0.
      start = 0;
      final length =
          int.tryParse(response.headers.value('content-length') ?? '');
      total = length ?? 0;
    }
    final sink =
        part.openWrite(mode: start == 0 ? FileMode.write : FileMode.append);
    var received = start;
    try {
      await for (final chunk in response.data!.stream) {
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(received, total);
      }
    } finally {
      await sink.flush();
      await sink.close();
    }
    if (total > 0 && received < total) throw _Retry(); // closed early
    if (total > 0 && received > total) throw _Fatal('longer than announced');
    return true;
  }

  /// Where the unfinished download of [url] into [path] is kept.
  static String partPathFor(String path, String url) =>
      '$path.${_key(url)}.part';

  /// Stable across app restarts (String.hashCode isn't guaranteed to be),
  /// so a download interrupted by closing the app resumes next time.
  static String _key(String url) {
    var h = 0x811c9dc5; // FNV-1a, 32-bit
    for (final unit in url.codeUnits) {
      h = ((h ^ unit) * 0x01000193) & 0xffffffff;
    }
    return h.toRadixString(36);
  }
}

class _Retry implements Exception {}

class _Fatal implements Exception {
  _Fatal(this.message);
  final String message;
  @override
  String toString() => 'ResumableDownloader: $message';
}
