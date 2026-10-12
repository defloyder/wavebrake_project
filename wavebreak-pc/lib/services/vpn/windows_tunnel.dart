import 'dart:async';
import 'dart:convert';

import '../../core/storage/prefs_store.dart';
import '../core_api/models.dart';
import 'vpn_adapter.dart';
import 'windows_vpn_adapter.dart';
import 'windows_xray_adapter.dart';

/// What the app asks of a Windows tunnel beyond [VpnAdapter]: a latency
/// figure through it and its byte counters (Metrics, the traffic check
/// after connecting). Both engines answer: sing-box (Clash API) and Xray
/// (SOCKS probe + metrics).
abstract class WindowsTunnel implements VpnAdapter {
  Future<int?> measureTunnelLatency();
  Future<({int up, int down})?> trafficTotals();
}

/// The share link inside a connection profile (a bare link, or Core's
/// grant JSON with `vless.connection_url`).
String? windowsProfileUrl(String raw) {
  final trimmed = raw.trim();
  if (trimmed.contains('://') && !trimmed.startsWith('{')) return trimmed;
  try {
    final payload = jsonDecode(trimmed) as Map<String, dynamic>;
    final url = (payload['vless'] as Map?)?['connection_url'] as String?;
    return (url != null && url.isNotEmpty) ? url : null;
  } catch (_) {
    return null;
  }
}

/// Core's smart-routing policy next to the link (`routing_policy`), as the
/// Android adapter reads it; null for a user's own server.
Map<String, dynamic>? windowsProfileRoutingPolicy(String raw) {
  final trimmed = raw.trim();
  if (!trimmed.startsWith('{')) return null;
  try {
    final policy =
        (jsonDecode(trimmed) as Map<String, dynamic>)['routing_policy'];
    return policy is Map ? policy.cast<String, dynamic>() : null;
  } catch (_) {
    return null;
  }
}

/// Picks the engine per connection (handoff phase 1): Xray when the user
/// turned it on (Settings → Connection, "Xray engine (beta)") and Xray runs
/// the link as it is; sing-box otherwise — cloak links, TUIC, self-signed
/// third-party servers, and everything while the switch is off. With the
/// switch off this is the sing-box adapter, unchanged.
class WindowsEngineSwitch implements VpnAdapter, WindowsTunnel {
  WindowsEngineSwitch() {
    _singBoxSub = _singBox.states.listen((s) {
      if (identical(_active, _singBox)) _emit(s);
    });
    _xraySub = _xray.states.listen((s) {
      if (identical(_active, _xray)) _emit(s);
    });
  }

  final _singBox = WindowsVpnAdapter();
  final _xray = WindowsXrayAdapter();
  late VpnAdapter _active = _singBox;
  late final StreamSubscription<VpnNativeState> _singBoxSub;
  late final StreamSubscription<VpnNativeState> _xraySub;
  final _controller = StreamController<VpnNativeState>.broadcast();

  static bool get xrayEnabled => PrefsStore.getBool(PrefsStore.pcXrayEngine);

  /// Which engine the current/last connection uses (diagnostics).
  String get engineName => identical(_active, _xray) ? 'xray' : 'sing-box';

  @override
  Stream<VpnNativeState> get states => _controller.stream;

  @override
  Future<void> connect(ConnectionProfile profile) async {
    final url = windowsProfileUrl(profile.rawJson);
    final VpnAdapter next = xrayEnabled &&
            WindowsXrayAdapter.installed &&
            url != null &&
            WindowsXrayAdapter.supports(url)
        ? _xray
        : _singBox;
    if (!identical(next, _active)) {
      // Only one engine may hold the routes: stop the other first.
      await _active.disconnect();
      _active = next;
    }
    return _active.connect(profile);
  }

  @override
  Future<void> disconnect() async {
    await _xray.disconnect();
    await _singBox.disconnect();
  }

  @override
  Future<int?> pingMs() => _active.pingMs();

  @override
  Future<int?> measureTunnelLatency() =>
      (_active as WindowsTunnel).measureTunnelLatency();

  @override
  Future<({int up, int down})?> trafficTotals() =>
      (_active as WindowsTunnel).trafficTotals();

  void _emit(VpnNativeState s) {
    if (!_controller.isClosed) _controller.add(s);
  }

  void dispose() {
    _singBoxSub.cancel();
    _xraySub.cancel();
    _singBox.dispose();
    _xray.dispose();
    _controller.close();
  }
}
