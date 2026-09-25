import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../core_api/models.dart';

/// Resolves the `host:port` a raw TCP reachability probe should dial for
/// [location], or null when there's nothing to dial — no address could be
/// determined, or the transport is Hysteria2 (QUIC-over-UDP; the declared
/// port has no TCP listener at all, or — worse — something else on the
/// host answers TCP on that same port and this would silently measure a
/// completely unrelated service's latency instead). Confirmed on-device: a
/// Direct-TLS (real TCP) and a Hysteria2 node on the same box showed the
/// exact same "ping", which isn't possible for two different transports —
/// that coincidence was this test hitting the same TCP path for both. No
/// good lightweight UDP/QUIC reachability probe exists here, so this is
/// honest-null rather than a plausible-looking wrong number. Shared by
/// [ConnectionTestService] and the Android status notification's own
/// "check ping" (see vpn_notification_meta.dart) so both agree on exactly
/// which locations are TCP-testable at all.
(String, int)? resolvePingTarget(LocationItem location) {
  final test = location.connectionTest;
  if (test != null && test.host.isNotEmpty && test.port > 0) {
    if (test.protocol?.toLowerCase() == 'hysteria2') return null;
    return (test.host, test.port);
  }
  final scheme = (location.rawLink ?? '').split('://').first.toLowerCase();
  if (scheme == 'hysteria2' || scheme == 'hy2') return null;
  return _hostPortFromRawLink(location.rawLink);
}

/// Tests whether a specific location's node is actually reachable — a raw
/// TCP connect to `host:port`, timed, with no VPN tunnel involved. This is
/// what makes a real "test this server" action possible *before* ever
/// creating an access grant, which is the only way Core exposes anything
/// resembling per-location latency (it doesn't track that server-side).
class ConnectionTestService {
  const ConnectionTestService();

  static const _engineChannel = MethodChannel('app.wavebreak/vpn_engine');

  /// Returns the round-trip time to open a TCP connection, in
  /// milliseconds, or null if no target could be determined for
  /// [location] or the connection attempt failed/timed out.
  ///
  /// Real WAVEBREAK locations carry Core's own [ConnectionTest] recipe;
  /// custom/BYO servers don't (Core never saw that link), so the host and
  /// port are pulled straight out of the pasted share link instead —
  /// still a real reachability check, just without a Core-picked target
  /// domain or timeout.
  Future<int?> testLocation(LocationItem location) async {
    final target = resolvePingTarget(location);
    if (target == null) return null;
    final host = target.$1;
    final port = target.$2;
    // Capped, not just defaulted: this same test now also runs while a
    // tunnel is up (Home's sphere ping) and gets routed through it like
    // any other unprotected socket from this process, meaning it goes
    // through the SAME native protect() handshake every Xray-core/
    // Hysteria dial does. A generous 8s timeout, multiplied across
    // repeated taps and the location list's own 25s background sweep
    // (see subscription_accordion.dart), meant a slow/hanging attempt
    // could sit open far longer than any of this is worth — confirmed
    // on-device this contributed to the native protect socket server
    // eventually hitting EMFILE, at which point it can't accept any
    // *new* protect requests, which reads as "connects but no
    // internet" for whatever tries to connect next. A short, hard cap
    // keeps a stuck attempt from ever running that long regardless of
    // what Core reports.
    final timeoutMs = (location.connectionTest?.timeoutMs ?? 4000).clamp(1000, 4000);

    // On Android, while a tunnel is up, a plain dart:io socket to the
    // node's own host:port gets captured into that SAME tunnel (Android's
    // VpnService.Builder default is to capture all of this app's own
    // traffic too) — and since Xray-core/Hysteria already hold an open,
    // multiplexed session to that exact server, what comes back measures
    // that session handing out a new local stream, not a real round trip.
    // Confirmed on-device: this read as an implausible 2-4ms even for a
    // server physically nowhere near the phone. WaveEngineVpnService.
    // pingHost() calls VpnService.protect() on the test socket first —
    // same mechanism every real engine dial already uses — routing it
    // around the tunnel onto the phone's real interface for a genuine
    // external RTT. When no tunnel is running there's nothing to protect
    // against, so MainActivity returns a `no_service` error and this falls
    // through to the plain socket below, unchanged from before.
    if (Platform.isAndroid) {
      try {
        return await _engineChannel.invokeMethod<int>('pingHost', {
          'host': host,
          'port': port,
          'timeoutMs': timeoutMs,
        });
      } on PlatformException catch (e) {
        if (e.code != 'no_service') return null;
      } on MissingPluginException {
        // Fall through — treat exactly like the pre-native-ping behavior.
      }
    }

    final stopwatch = Stopwatch()..start();
    Socket? socket;
    try {
      socket = await Socket.connect(host, port, timeout: Duration(milliseconds: timeoutMs));
      stopwatch.stop();
      return stopwatch.elapsedMilliseconds;
    } catch (_) {
      return null;
    } finally {
      // destroy(), not close(): close() is a graceful shutdown that waits
      // on the underlying stream, and firing it with `unawaited` here
      // meant this function could return (and the caller move on) before
      // the fd was actually released — for a throwaway ping-test socket
      // there's nothing to flush or wait for, and an immediate, fully
      // synchronous release is exactly what matters when many of these
      // run back to back.
      socket?.destroy();
    }
  }

  /// Pulls `host`/`port` out of a pasted share link without pulling in the
  /// full sing-box config generation from `windows_vpn_adapter.dart`'s
  /// `ShareLink` — this only needs the address, not a runnable outbound.
}

/// Pulls `host`/`port` out of a pasted share link without pulling in the
/// full sing-box config generation from `windows_vpn_adapter.dart`'s
/// `ShareLink` — this only needs the address, not a runnable outbound.
(String, int)? _hostPortFromRawLink(String? rawLink) {
  if (rawLink == null || rawLink.isEmpty) return null;
  final trimmed = rawLink.trim();
  final scheme = trimmed.split('://').first.toLowerCase();
  try {
    if (scheme == 'vmess') {
      final b64 = trimmed.substring('vmess://'.length).split('#').first;
      final json = jsonDecode(utf8.decode(base64.decode(base64.normalize(b64)))) as Map<String, dynamic>;
      final host = json['add'] as String?;
      final port = int.tryParse('${json['port']}');
      if (host == null || host.isEmpty || port == null || port <= 0) return null;
      return (host, port);
    }
    final uri = Uri.parse(trimmed);
    if (uri.host.isEmpty) return null;
    final port = uri.hasPort
        ? uri.port
        : switch (scheme) {
            'ss' => 8388,
            _ => 443,
          };
    return (uri.host, port);
  } catch (_) {
    return null;
  }
}
