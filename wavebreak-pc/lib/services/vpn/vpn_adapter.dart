import 'dart:async';
import 'dart:math';

import '../../core/logging/app_logger.dart';
import '../core_api/models.dart';

enum VpnNativeState {
  idle,
  connecting,
  connected,
  disconnecting,
  // Windows-only so far (see WindowsVpnAdapter): an automatic recovery
  // attempt (Clash API reload or a full sing-box relaunch) is in flight
  // after a network change or a failed health probe, without the user
  // having asked to disconnect. Kept distinct from `failed` so
  // ConnectionManager can leave the UI on its current "connected" read
  // instead of flashing a disconnected/error state while recovery is
  // still trying — a real `failed` still follows if recovery is
  // eventually exhausted.
  reconnecting,
  failed,
}

abstract class VpnAdapter {
  Stream<VpnNativeState> get states;
  Future<void> connect(ConnectionProfile profile);
  Future<void> disconnect();

  /// A real, on-demand round-trip measurement through the current tunnel —
  /// null when there's nothing to measure yet (not connected) or this
  /// adapter has no way to measure it (see each implementation).
  Future<int?> pingMs();
}

/// Local tunnel stand-in until native VPN modules consume the Core profile.
/// The profile is accepted but never logged.
class SimulatedVpnAdapter implements VpnAdapter {
  SimulatedVpnAdapter({this.delay = const Duration(milliseconds: 900)});

  final Duration delay;
  final _controller = StreamController<VpnNativeState>.broadcast();
  VpnNativeState _state = VpnNativeState.idle;

  @override
  Stream<VpnNativeState> get states => _controller.stream;

  @override
  Future<void> connect(ConnectionProfile profile) async {
    if (profile.rawJson.isEmpty) {
      _emit(VpnNativeState.failed);
      throw StateError('empty profile');
    }
    _emit(VpnNativeState.connecting);
    AppLogger.debug('VPN adapter connecting');
    await Future<void>.delayed(delay);
    _emit(VpnNativeState.connected);
  }

  @override
  Future<void> disconnect() async {
    _emit(VpnNativeState.disconnecting);
    await Future<void>.delayed(const Duration(milliseconds: 280));
    _emit(VpnNativeState.idle);
  }

  final _random = Random();

  @override
  Future<int?> pingMs() async {
    if (_state != VpnNativeState.connected) return null;
    await Future<void>.delayed(const Duration(milliseconds: 350));
    return 18 + _random.nextInt(45);
  }

  void _emit(VpnNativeState state) {
    _state = state;
    _controller.add(_state);
  }
}
