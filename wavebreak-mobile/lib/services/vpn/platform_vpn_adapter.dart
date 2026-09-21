import 'dart:async';

import 'package:flutter/services.dart';

import '../../core/logging/app_logger.dart';
import '../core_api/models.dart';
import 'vpn_adapter.dart';

/// Talks to the real, native tunnel engine once one is wired up on each
/// platform, in place of [SimulatedVpnAdapter]. This class is the whole
/// Dart-side contract — swapping [vpnAdapterProvider] over to this is all
/// the app code needs to do once native support lands; nothing in
/// [ConnectionManager] or the UI has to change.
///
/// # Native contract
///
/// Method channel: `app.wavebreak/vpn`
///   - `connect(String profileJson) -> void`
///     `profileJson` is [ConnectionProfile.rawJson] verbatim — whatever the
///     Core server (or a pasted vless/vmess/trojan/ss/hysteria2 link) handed
///     back. This app never parses it; the native side owns understanding
///     the outbound config and handing it to whatever engine runs the
///     actual tunnel (e.g. sing-box/Xray core on Android/iOS/macOS, plus a
///     WinTun-backed userspace tunnel on Windows). Throw a `PlatformException`
///     on failure to start (bad config, permission denied, engine crash);
///     its `message` is surfaced to the user via [AppErrorKind.connectionFailed].
///   - `disconnect() -> void`
///     Tears the tunnel down and restores normal routing. Should not throw
///     for "already disconnected" — treat that as a no-op success.
///
/// Event channel: `app.wavebreak/vpn_state`
///   Emits one of the strings below every time the *native* tunnel's own
///   state changes (not in response to a method call — this is how the app
///   notices the OS killed the tunnel, a network change dropped it, etc.):
///   `"idle"`, `"connecting"`, `"connected"`, `"disconnecting"`, `"failed"`.
///   Unrecognized values are treated as `"failed"` rather than crashing.
///
/// # Per-platform native work still needed
///   - Android: a `VpnService` + bundled tunnel engine (e.g. libbox/Xray
///     AAR), registering the two channels above from `MainActivity`.
///   - iOS/macOS: a Network Extension (`NEPacketTunnelProvider`) target
///     running the same engine, with the host app relaying method/event
///     channel calls to it via `NEVPNManager` / app group IPC.
///   - Windows: no VPN-capable native code exists yet. Needs either a
///     bundled sing-box/Xray-core executable run as a child process with a
///     generated config plus a WinTun adapter, or an equivalent userspace
///     tunnel, driven from `windows/runner` and exposed through the same
///     two channels.
///   None of that is guessable from the Flutter side alone — it depends on
///   which engine/binary the real server's protocol calls for, which is why
///   this class only defines the contract rather than an implementation.
class PlatformVpnAdapter implements VpnAdapter {
  PlatformVpnAdapter({
    MethodChannel? methodChannel,
    EventChannel? eventChannel,
  })  : _method = methodChannel ?? const MethodChannel('app.wavebreak/vpn'),
        _events = eventChannel ?? const EventChannel('app.wavebreak/vpn_state') {
    _eventsSub = _events.receiveBroadcastStream().listen(
          _onNativeEvent,
          onError: (Object error, StackTrace _) {
            AppLogger.warn('VPN state channel error: $error');
            _controller.add(VpnNativeState.failed);
          },
        );
  }

  final MethodChannel _method;
  final EventChannel _events;
  late final StreamSubscription<dynamic> _eventsSub;
  final _controller = StreamController<VpnNativeState>.broadcast();

  @override
  Stream<VpnNativeState> get states => _controller.stream;

  @override
  Future<void> connect(ConnectionProfile profile) async {
    if (profile.rawJson.isEmpty) {
      _controller.add(VpnNativeState.failed);
      throw StateError('empty profile');
    }
    try {
      await _method.invokeMethod<void>('connect', profile.rawJson);
    } on PlatformException catch (e) {
      AppLogger.warn('Native connect() failed: ${e.code}');
      _controller.add(VpnNativeState.failed);
      rethrow;
    }
  }

  @override
  Future<void> disconnect() async {
    try {
      await _method.invokeMethod<void>('disconnect');
    } on PlatformException catch (e) {
      AppLogger.warn('Native disconnect() failed: ${e.code}');
      // Disconnect is best-effort from the caller's point of view —
      // ConnectionManager always moves local state to idle regardless.
    }
  }

  void _onNativeEvent(dynamic event) {
    final state = switch (event) {
      'idle' => VpnNativeState.idle,
      'connecting' => VpnNativeState.connecting,
      'connected' => VpnNativeState.connected,
      'disconnecting' => VpnNativeState.disconnecting,
      'failed' => VpnNativeState.failed,
      _ => VpnNativeState.failed,
    };
    _controller.add(state);
  }

  void dispose() {
    unawaited(_eventsSub.cancel());
    unawaited(_controller.close());
  }

  @override
  Future<int?> pingMs() async => null;
}
