import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

import '../../core/errors/app_exception.dart';
import '../../core/logging/app_logger.dart';
import '../core_api/models.dart';
import 'share_link_config.dart';
import 'vpn_adapter.dart';

/// Real system-level VPN tunnel for every protocol WAVEBREAK supports on
/// Android — VLESS/VMess/Trojan/Shadowsocks/REALITY via an embedded
/// Xray-core, and Hysteria2 via an embedded apernet/hysteria client, both
/// in the ONE native binding built at native/hysteria_bridge (see
/// WaveEngineVpnService.kt for why that matters: two separately
/// gomobile-bound engines — the old setup, flutter_v2ray's Xray-core plus
/// this module's Hysteria bridge — turned out not to be binary-compatible
/// sharing one Android process, confirmed by a native crash on a real
/// device).
///
/// Share-link parsing and Xray JSON config generation for the non-Hysteria
/// schemes is [parseShareLink] (share_link_config.dart) — copied from
/// flutter_v2ray's own Dart-side classes rather than depending on that
/// package at all now that its native Android code isn't used.
class NativeVpnAdapter implements VpnAdapter {
  static const _method = MethodChannel('app.wavebreak/vpn_engine');
  static const _events = EventChannel('app.wavebreak/vpn_engine/status');
  static const _vpnStateMethod = MethodChannel('app.wavebreak/vpn_state');

  final _controller = StreamController<VpnNativeState>.broadcast();
  StreamSubscription<dynamic>? _eventSub;
  Completer<void>? _connectCompleter;

  NativeVpnAdapter() {
    _eventSub =
        _events.receiveBroadcastStream().listen(_onStatus, onError: (Object e) {
      AppLogger.warn('VPN engine status stream error: $e');
    });
  }

  @override
  Stream<VpnNativeState> get states => _controller.stream;

  @override
  Future<void> connect(ConnectionProfile profile) async {
    final url = _extractUrl(profile.rawJson);
    if (url == null || url.isEmpty) {
      _emit(VpnNativeState.failed);
      throw StateError('profile has no usable share link');
    }
    final scheme = Uri.tryParse(url)?.scheme;

    // A previous connect() that hasn't resolved yet means its native
    // "connect" call and the Kotlin-side thread it spawned
    // (WaveEngineVpnService.connectXray/connectHysteria) are still live —
    // firing a SECOND "connect" on top of that starts a second overlapping
    // thread fighting the first over the same Xray-core/Hysteria instance
    // and TUN interface. Confirmed on-device: rapidly switching locations
    // (or just impatiently re-tapping connect while a slow attempt was
    // still in flight) this way sent the whole app into a crash loop
    // (ForegroundServiceDidNotStartInTimeException, repeated process
    // restarts). An explicit disconnect first serializes this — cheap
    // when there's nothing to actually tear down, and it's exactly what's
    // needed when there is.
    if (_connectCompleter != null && !_connectCompleter!.isCompleted) {
      try {
        await _method.invokeMethod('disconnect');
      } catch (_) {}
      _connectCompleter = null;
    }

    final granted =
        await _method.invokeMethod<bool>('requestPermission') ?? false;
    if (!granted) {
      _emit(VpnNativeState.failed);
      throw StateError('VPN permission denied by the user');
    }

    _emit(VpnNativeState.connecting);
    final completer = Completer<void>();
    _connectCompleter = completer;

    if (scheme == 'hysteria2' || scheme == 'hy2') {
      await _method.invokeMethod('connect', {'link': url});
    } else {
      final String config;
      try {
        final parsed = parseShareLink(url);
        // Current Xray-core hard-rejects "allowInsecure" outright (a
        // time-gated removal in its own JSON parser, effective
        // 2026-06-01 — see share_link_config.dart's comment), so a
        // custom/BYO server with a self-signed or otherwise
        // CA-unverifiable certificate would connect at the TUN/SOCKS
        // layer but silently pass no traffic once the real TLS handshake
        // fails (confirmed: a previously-working server regressed exactly
        // this way when allowInsecure was simply dropped). Xray-core's
        // own recommended replacement is pinnedPeerCertSha256 — pinning
        // the exact certificate rather than skipping validation entirely
        // — so this fetches whatever certificate the server actually
        // presents right now (TOFU: trust on first use) and pins that,
        // which is a strictly narrower trust decision than the old
        // blanket "skip validation" default ever was.
        AppLogger.debug(
            'xray security=${parsed.streamSetting['security']} address=${parsed.address} port=${parsed.port}');
        applySmartRoutingPolicy(parsed, _extractRoutingPolicy(profile.rawJson));
        if (parsed.streamSetting['security'] == 'tls') {
          final pin = await _probeCertSha256(parsed.address, parsed.port);
          AppLogger.debug('xray cert pin=$pin');
          if (pin != null) {
            (parsed.streamSetting['tlsSettings']
                as Map<String, dynamic>?)?['pinnedPeerCertSha256'] = pin;
          }
        }
        config = parsed.getFullConfiguration();
      } catch (e) {
        _connectCompleter = null;
        _emit(VpnNativeState.failed);
        throw StateError('unsupported or malformed share link: $e');
      }
      await _method.invokeMethod('connect', {'xrayConfig': config});
    }

    try {
      await completer.future.timeout(const Duration(seconds: 20));
    } on TimeoutException {
      // Backgrounding the app mid-connect can apparently delay or drop the
      // CONNECTING->CONNECTED broadcast reaching this EventChannel listener
      // (confirmed: the native side had actually connected fine — a
      // manual retry right after a reported "failed" succeeded instantly
      // rather than needing a real fresh handshake). Before declaring
      // failure, check Android's own view of whether a VPN transport is
      // up at all — the same system-level signal
      // ConnectionManager.reconcileWithSystem() already trusts for "is
      // some VPN active" on a cold start.
      final reallyConnected = await _isSystemVpnActive();
      if (reallyConnected) {
        _emit(VpnNativeState.connected);
        return;
      }
      unawaited(_method.invokeMethod('disconnect'));
      _emit(VpnNativeState.failed);
      throw StateError('VPN tunnel did not come up in time');
    } finally {
      if (identical(_connectCompleter, completer)) _connectCompleter = null;
    }
  }

  Future<bool> _isSystemVpnActive() async {
    try {
      return await _vpnStateMethod.invokeMethod<bool>('isSystemVpnActive') ??
          false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> disconnect() async {
    await _method.invokeMethod('disconnect');
  }

  // Neither embedded engine exposes an internal "measure delay through the
  // live tunnel" call, so this times a raw TCP connect instead — same
  // technique as ConnectionTestService's pre-connect reachability check,
  // just aimed at a fast, always-up public target instead of the node
  // itself. While the tunnel is up, Android routes this app's own sockets
  // through it like any other traffic (that's what VpnService.Builder's
  // default "capture everything" behavior means), so the round trip really
  // does reflect the live connection, not just the phone's raw internet.
  @override
  Future<int?> pingMs() async {
    final stopwatch = Stopwatch()..start();
    Socket? socket;
    try {
      socket = await Socket.connect('1.1.1.1', 443,
          timeout: const Duration(seconds: 5));
      stopwatch.stop();
      return stopwatch.elapsedMilliseconds;
    } catch (_) {
      return null;
    } finally {
      unawaited(socket?.close());
    }
  }

  /// [ConnectionProfile.rawJson] is either a grant-based (WAVEBREAK-hosted)
  /// envelope — `{"vless": {"connection_url": "vless://..."}}`, built in
  /// ConnectionManager._finishConnecting — or, for a custom/BYO location,
  /// just the raw share-link text handed straight through.
  String? _extractUrl(String raw) {
    final trimmed = raw.trim();
    if (trimmed.contains('://') && !trimmed.startsWith('{')) {
      return trimmed;
    }
    try {
      final payload = jsonDecode(trimmed) as Map<String, dynamic>;
      final vless = payload['vless'] as Map<String, dynamic>?;
      final url = vless?['connection_url'] as String?;
      return (url != null && url.isNotEmpty) ? url : null;
    } catch (_) {
      return null;
    }
  }

  /// `routing_policy` sits alongside `vless` in the same grant-based
  /// envelope `_extractUrl` reads — absent entirely for a custom/BYO link
  /// (raw share-link text, not JSON) or when Core's grant response didn't
  /// include one.
  Map<String, dynamic>? _extractRoutingPolicy(String raw) {
    final trimmed = raw.trim();
    if (!trimmed.startsWith('{')) return null;
    try {
      final payload = jsonDecode(trimmed) as Map<String, dynamic>;
      final policy = payload['routing_policy'];
      return policy is Map ? policy.cast<String, dynamic>() : null;
    } catch (_) {
      return null;
    }
  }

  /// Connects with TLS to (host, port), accepting whatever certificate is
  /// presented (this is the ONLY place in the app that does that — the
  /// cert is inspected, never trusted for anything else), and returns its
  /// SHA-256 fingerprint as lowercase hex. Returns null on any failure
  /// (unreachable host, timeout, ...) — the caller falls back to
  /// connecting without a pin, which Xray-core will then reject or accept
  /// per its own normal CA validation.
  Future<String?> _probeCertSha256(String host, int port) async {
    SecureSocket? socket;
    try {
      X509Certificate? cert;
      socket = await SecureSocket.connect(
        host,
        port,
        onBadCertificate: (X509Certificate c) {
          cert = c;
          return true;
        },
        timeout: const Duration(seconds: 8),
      );
      cert ??= socket.peerCertificate;
      if (cert == null) return null;
      return sha256.convert(cert!.der).toString();
    } catch (e) {
      AppLogger.warn('cert probe failed for $host:$port: $e');
      return null;
    } finally {
      unawaited(socket?.close());
    }
  }

  void _onStatus(dynamic event) {
    // A Map (state + an optional real error detail), not a bare String —
    // see MainActivity.kt's EventChannel forwarding. The detail is the
    // one piece of "what actually went wrong" that previously only ever
    // reached Android's own logcat — logging it here is what makes the
    // diagnostic log export (settings > Export logs) actually useful for
    // a Hysteria2/REALITY/Direct-TLS failure report from a device with no
    // USB/adb access.
    final map = event is Map ? event : const {};
    final stateStr = map['state'] as String?;
    final detail = map['detail'] as String?;
    final state = switch (stateStr) {
      'CONNECTING' => VpnNativeState.connecting,
      'CONNECTED' => VpnNativeState.connected,
      'IDLE' => VpnNativeState.idle,
      'FAILED' => VpnNativeState.failed,
      _ => VpnNativeState.failed,
    };
    if (state == VpnNativeState.failed && detail != null) {
      AppLogger.error('native engine failure: $detail');
    }
    _emit(state);
    final completer = _connectCompleter;
    if (completer == null || completer.isCompleted) return;
    if (state == VpnNativeState.connected) {
      completer.complete();
    } else if (state == VpnNativeState.failed) {
      completer.completeError(AppException(AppErrorKind.connectionFailed));
    }
  }

  void _emit(VpnNativeState state) {
    if (!_controller.isClosed) _controller.add(state);
  }

  void dispose() {
    unawaited(_eventSub?.cancel());
    unawaited(_controller.close());
  }
}
