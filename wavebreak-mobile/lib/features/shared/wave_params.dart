import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/flag_colors.dart';
import '../../core/theme/personalization_controller.dart';
import '../../services/vpn/connection_manager.dart';

/// The wave speed/amplitude/tint the whole app currently animates and
/// tints with — every animated background (Home, secondary screens, the
/// nav rail, the mobile bottom bar) reads this same value, so they all
/// move and glow together instead of drifting out of sync.
class WaveParams {
  const WaveParams({this.speed = 1.0, this.amplitude = 1.0, this.tint});

  final double speed;
  final double amplitude;
  final Color? tint;
}

/// Derived directly from the current connection/location state — no
/// screen has to compute or push this itself, so it's always correct even
/// if Home was never visited this session. "Auto" carries no tint of its
/// own; only a specific server's flag color is gentle enough to wash the
/// UI without reading as arbitrary when nothing specific is chosen.
///
/// Waves stay calm at rest, pick up a little while negotiating a
/// connection, and — once connected — move a bit faster the lower the
/// selected server's ping is (never wildly, just enough to feel alive).
final appWaveParamsProvider = Provider<WaveParams>((ref) {
  final connection = ref.watch(connectionManagerProvider);
  final personalization = ref.watch(personalizationProvider);
  // The location actually in play right now — the concrete server Auto
  // resolved to, once it has, rather than the never-tinted Auto
  // placeholder itself (see WbConnectionState.effectiveLocation).
  final effective = connection.effectiveLocation;

  // A manually chosen accent always wins over the automatic per-server
  // flag color — that automatic tint is a nice default, not something a
  // user who picked their own accent wants overridden the moment they
  // connect somewhere.
  final autoTint = effective.isAuto ? null : accentColorFor(effective.countryCode);
  final tint = personalization.accent.color ?? autoTint;

  final raw = switch (connection.status) {
    ConnectionStatus.idle => const WaveParams(speed: 0.9, amplitude: 0.9),
    ConnectionStatus.requestingProfile ||
    ConnectionStatus.connecting =>
      const WaveParams(speed: 1.5, amplitude: 1.3),
    ConnectionStatus.configPending ||
    ConnectionStatus.disconnecting =>
      const WaveParams(speed: 1.1, amplitude: 1.0),
    ConnectionStatus.error => const WaveParams(speed: 0.6, amplitude: 0.7),
    ConnectionStatus.connected => _connectedWaveParams(effective.pingMs),
  };

  if (!personalization.reduceMotion) {
    return WaveParams(speed: raw.speed, amplitude: raw.amplitude, tint: tint);
  }
  // "Reduce motion" asks for calm, not frozen — still a faint drift
  // rather than a hard stop, which would just read as the animation
  // being broken.
  return WaveParams(speed: raw.speed * 0.18, amplitude: raw.amplitude * 0.35, tint: tint);
});

WaveParams _connectedWaveParams(int? pingMs) {
  if (pingMs == null) return const WaveParams(speed: 1.4, amplitude: 1.2);
  final normalized = (1 - (pingMs / 150)).clamp(0.0, 1.0);
  return WaveParams(
    speed: 1.1 + normalized * 0.9,
    amplitude: 1.1 + normalized * 0.5,
  );
}
