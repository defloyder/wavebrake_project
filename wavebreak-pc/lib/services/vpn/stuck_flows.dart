/// Connections an app waits on in vain — Windows' counterpart of the
/// Android bridge's stuckflows.go (owner, 14.10: on the PC the VPN "just
/// stops loading" after a while, and only restarting it helps; phones got
/// this fix on 13.10). sing-box accepts an app's connection before its own
/// upstream answers; one whose request goes nowhere hangs until an idle
/// timeout minutes later. Read from the Clash API's `/connections` every
/// few seconds and closed with `DELETE /connections/{id}`: the app sees
/// the connection end and opens a new one at once; the rest stay.
///
/// "Waiting" is strict so quiet healthy connections are never cut:
///   - opened, the app spoke first and not one byte came back for
///     [openWait]; or
///   - two or more separate sends with no reply, the first [silent] ago,
///     the last at least [lastQuiet] ago.
/// More than [maxSent] sent while waiting (an upload) is left alone.
class StuckFlows {
  StuckFlows({
    this.openWait = const Duration(seconds: 15),
    this.silent = const Duration(seconds: 20),
    this.lastQuiet = const Duration(seconds: 10),
    this.maxSent = 32 * 1024,
  });

  final Duration openWait;
  final Duration silent;
  final Duration lastQuiet;
  final int maxSent;

  static const _burstGap = Duration(seconds: 3);

  final Map<String, _Seen> _seen = {};

  /// Takes the Clash API's `connections` list; returns the ids to close
  /// with a short description each ("149.154.167.51:443 31s").
  Map<String, String> observe(List<dynamic> connections, DateTime now) {
    final stuck = <String, String>{};
    final alive = <String>{};
    for (final c in connections) {
      if (c is! Map) continue;
      final meta = c['metadata'];
      if (meta is! Map || '${meta['network']}'.toLowerCase() != 'tcp') {
        continue;
      }
      final id = '${c['id']}';
      alive.add(id);
      final up = (c['upload'] as num? ?? 0).toInt();
      final down = (c['download'] as num? ?? 0).toInt();
      var f = _seen[id];
      final first = f == null;
      f ??= _seen[id] = _Seen();
      if (down > f.down) {
        f
          ..waitSince = null
          ..lastUp = null
          ..bursts = 0
          ..sentWait = 0;
      } else if (up > f.up) {
        if (f.waitSince == null) {
          f
            ..waitSince = now
            ..bursts = 1;
          // Seen for the first time with nothing back: waiting since open.
          if (first && down == 0) {
            f.waitSince = DateTime.tryParse('${c['start']}')?.toLocal() ?? now;
          }
        } else if (f.lastUp != null && now.difference(f.lastUp!) >= _burstGap) {
          f.bursts++;
        }
        f
          ..lastUp = now
          ..sentWait += up - f.up;
      }
      f
        ..up = up
        ..down = down;
      final since = f.waitSince;
      if (since == null || f.sentWait > maxSent) continue;
      final waited = now.difference(since);
      final neverAnswered = down == 0 && waited >= openWait;
      final retriedInVain = f.bursts >= 2 &&
          waited >= silent &&
          f.lastUp != null &&
          now.difference(f.lastUp!) >= lastQuiet;
      if (!neverAnswered && !retriedInVain) continue;
      final host = (meta['host'] as String?)?.isNotEmpty == true
          ? meta['host']
          : meta['destinationIP'];
      stuck[id] = '$host:${meta['destinationPort']} ${waited.inSeconds}s';
      _seen.remove(id);
    }
    _seen.removeWhere((id, _) => !alive.contains(id));
    return stuck;
  }

  void reset() => _seen.clear();
}

class _Seen {
  int up = 0;
  int down = 0;
  DateTime? waitSince;
  DateTime? lastUp;
  int bursts = 0;
  int sentWait = 0;
}
