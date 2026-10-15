import '../../core/theme/wb_theme.dart';
import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import '../../core/env/app_env.dart';
import '../../core/i18n/app_strings.dart';
import '../../services/vpn/connection_manager.dart';
import '../../services/vpn/live_metrics.dart';
import '../home/home_vitals.dart';
import '../home/location_bar.dart';
import '../immersive/immersive_clock.dart';
import '../immersive/immersive_colors.dart';
import '../immersive/tinted_glass.dart';
import '../shared/flag_icon.dart';

const _vpnState = MethodChannel('app.wavebreak/vpn_state');

/// "Wi-Fi", "LTE", … of the phone's own network (native NetworkLabel).
/// Cached for 10 s: the metrics screen rebuilds every frame (smooth chart),
/// this must not hit the platform channel each time.
Future<String?>? _networkCache;
DateTime _networkAt = DateTime(0);

Future<String?> _networkLabel() {
  final now = DateTime.now();
  if (_networkCache == null || now.difference(_networkAt).inSeconds > 10) {
    _networkAt = now;
    _networkCache = Platform.isAndroid
        ? _vpnState
            .invokeMethod<String>('networkLabel')
            .catchError((Object _) => null)
        : _desktopNetworkLabel();
  }
  return _networkCache!;
}

/// Windows: the kind of connection (no carrier name there).
Future<String?> _desktopNetworkLabel() async {
  try {
    final kinds = await Connectivity().checkConnectivity();
    if (kinds.contains(ConnectivityResult.ethernet)) return 'Ethernet';
    if (kinds.contains(ConnectivityResult.wifi)) return 'Wi-Fi';
    if (kinds.contains(ConnectivityResult.mobile)) return 'LTE';
  } catch (_) {}
  return null;
}

/// "Phone network" only on a phone; a TV or a PC has just "Network"
/// (owner, 14.10).
String _networkTitle(AppStrings s) =>
    Platform.isAndroid && !AppEnv.isTv ? s.mPhoneNetwork : s.mDeviceNetwork;

String _statusText(ConnectionStatus status, AppStrings s) => switch (status) {
      ConnectionStatus.connected => s.connected,
      ConnectionStatus.connecting ||
      ConnectionStatus.requestingProfile ||
      ConnectionStatus.configPending =>
        s.connecting,
      ConnectionStatus.disconnecting => s.disconnecting,
      ConnectionStatus.error => s.couldNotConnect,
      ConnectionStatus.idle => s.notConnected,
    };

String _hm(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// Connection facts — only what the app actually knows.
class InfoTab extends StatelessWidget {
  const InfoTab(
      {super.key,
      required this.connection,
      required this.metrics,
      required this.s});

  final WbConnectionState connection;
  final LiveMetricsState metrics;
  final AppStrings s;

  @override
  Widget build(BuildContext context) {
    final loc = connection.location;
    final (place, _) = splitPlaceAndProtocol(loc.city);
    final since = connection.connectedAt;
    final connected = connection.status == ConnectionStatus.connected;
    final rows = <(String, String)>[
      (s.mLocation, [if (place.isNotEmpty) place, loc.country].join(' · ')),
      (s.mProtocol, protocolLabel(loc) ?? '—'),
      (s.mStatus, _statusText(connection.status, s)),
      (s.mSessionStart, connected && since != null ? _hm(since) : '—'),
      (
        s.mSessionTraffic,
        metrics.sessionBytes > 0 ? formatBytes(metrics.sessionBytes) : '—'
      ),
      (
        s.speedTestLatency,
        metrics.active && metrics.pingMs != null
            ? '${metrics.pingMs} ${s.unitMs}'
            : '—'
      ),
      (
        s.mJitter,
        metrics.jitterMs != null
            ? '${metrics.jitterMs!.toStringAsFixed(1)} ${s.unitMs}'
            : '—'
      ),
      (
        s.mLoss,
        metrics.lossPercent != null
            ? '${metrics.lossPercent!.toStringAsFixed(1)} %'
            : '—'
      ),
    ];
    return TintedGlass(
      child: Column(
        children: [
          FutureBuilder<String?>(
            future: _networkLabel(),
            builder: (_, snap) =>
                _Row(label: _networkTitle(s), value: snap.data ?? '—'),
          ),
          for (final (l, v) in rows) _Row(label: l, value: v),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: const TextStyle(color: Ic.textMuted, fontSize: 14)),
          ),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Ic.text,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Device → WAVEBREAK server → Internet, with the tunnel's real latency.
/// A scheme, not a traceroute.
class RouteTab extends StatelessWidget {
  const RouteTab(
      {super.key,
      required this.connection,
      required this.metrics,
      required this.s});

  final WbConnectionState connection;
  final LiveMetricsState metrics;
  final AppStrings s;

  @override
  Widget build(BuildContext context) {
    final loc = connection.location;
    final (place, _) = splitPlaceAndProtocol(loc.city);
    final connected = connection.status == ConnectionStatus.connected;
    // Connected, but probes through the tunnel get no answer: the route is
    // shown broken, not flowing.
    final silent = connected && metrics.tunnelSilent;
    final flowing = connected && !silent;
    return TintedGlass(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
      child: Column(
        children: [
          FutureBuilder<String?>(
            future: _networkLabel(),
            builder: (_, snap) => _Node(
              icon: const Icon(Icons.smartphone_rounded, color: Ic.text),
              title: s.mThisDevice,
              subtitle: snap.data ?? _networkTitle(s),
            ),
          ),
          _Link(
            active: flowing,
            broken: silent,
            color: Ic.arctic,
            label: silent
                ? s.mTunnelNoAnswer
                : connected
                    ? '${s.mTunnel}'
                        '${metrics.pingMs != null ? ' · ${metrics.pingMs} ${s.unitMs}' : ''}'
                    : s.mNoTunnel,
          ),
          _Node(
            icon: loc.countryCode.isNotEmpty
                ? FlagIcon(countryCode: loc.countryCode, width: 26)
                : const Icon(Icons.dns_rounded, color: Ic.text),
            title: 'WAVEBREAK · ${place.isNotEmpty ? place : loc.country}',
            subtitle: protocolLabel(loc) ?? '',
          ),
          _Link(
            active: flowing,
            broken: silent,
            color: context.brand,
            label: flowing ? s.mExit : '',
          ),
          _Node(
            icon: const Icon(Icons.public_rounded, color: Ic.text),
            title: s.mInternet,
            subtitle: silent
                ? s.mNoConnection
                : connected
                    ? s.mSitesSeeServer.replaceAll('{country}', loc.country)
                    : s.mDirect,
            warn: silent,
          ),
        ],
      ),
    );
  }
}

class _Node extends StatelessWidget {
  const _Node(
      {required this.icon,
      required this.title,
      required this.subtitle,
      this.warn = false});

  final Widget icon;
  final String title;
  final String subtitle;

  /// The subtitle in amber: this hop is not reached.
  final bool warn;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Ic.text.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Ic.glassBorder),
          ),
          child: icon,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Ic.text,
                      fontSize: 15,
                      fontWeight: FontWeight.w600)),
              if (subtitle.isNotEmpty)
                Text(subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: warn ? Ic.amber : Ic.textMuted, fontSize: 13)),
            ],
          ),
        ),
      ],
    );
  }
}

/// Vertical connector; dots flow along it while the tunnel is up.
class _Link extends StatelessWidget {
  const _Link(
      {required this.active,
      required this.color,
      required this.label,
      this.broken = false});

  final bool active;

  /// Connected but silent: an amber dashed line with a gap, no flow.
  final bool broken;
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: Row(
        children: [
          SizedBox(
            width: 44,
            child: CustomPaint(
              size: const Size(44, 54),
              painter: _FlowPainter(
                time: ImmersiveClock.of(context),
                active: active,
                broken: broken,
                color: color,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label,
                style: TextStyle(
                    color: broken ? Ic.amber : (active ? color : Ic.textMuted),
                    fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

class _FlowPainter extends CustomPainter {
  _FlowPainter(
      {required this.time,
      required this.active,
      required this.color,
      this.broken = false})
      : super(repaint: active ? time : null);

  final ValueListenable<double> time;
  final bool active;
  final bool broken;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final x = size.width / 2;
    if (broken) {
      // Dashes to a gap in the middle, where the link breaks.
      final dash = Paint()
        ..strokeWidth = 1.5
        ..color = Ic.amber.withValues(alpha: 0.7);
      final mid = size.height / 2;
      for (var y = 2.0; y < size.height - 2; y += 7) {
        if ((y - mid).abs() < 7) continue;
        canvas.drawLine(
            Offset(x, y), Offset(x, math.min(y + 4, size.height - 2)), dash);
      }
      canvas.drawLine(Offset(x - 4, mid - 4), Offset(x + 4, mid + 4), dash);
      canvas.drawLine(Offset(x + 4, mid - 4), Offset(x - 4, mid + 4), dash);
      return;
    }
    final line = Paint()
      ..strokeWidth = 1.5
      ..color = (active ? color : Ic.glassBorder).withValues(alpha: 0.6);
    canvas.drawLine(Offset(x, 2), Offset(x, size.height - 2), line);
    if (!active) return;
    final t = time.value;
    final dot = Paint()..color = color;
    for (var i = 0; i < 3; i++) {
      final k = (t * 0.8 + i / 3) % 1.0;
      canvas.drawCircle(Offset(x, 2 + k * (size.height - 4)), 2.4,
          dot..color = color.withValues(alpha: 0.9 * (1 - (k - 0.5).abs())));
    }
  }

  @override
  bool shouldRepaint(_FlowPainter old) =>
      old.active != active || old.broken != broken || old.color != color;
}
