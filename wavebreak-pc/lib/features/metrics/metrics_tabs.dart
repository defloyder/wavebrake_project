import '../../core/theme/wb_theme.dart';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
    _networkCache = _vpnState
        .invokeMethod<String>('networkLabel')
        .catchError((Object _) => null);
  }
  return _networkCache!;
}

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
                _Row(label: s.mPhoneNetwork, value: snap.data ?? '—'),
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
    return TintedGlass(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
      child: Column(
        children: [
          FutureBuilder<String?>(
            future: _networkLabel(),
            builder: (_, snap) => _Node(
              icon: const Icon(Icons.smartphone_rounded, color: Ic.text),
              title: s.mThisDevice,
              subtitle: snap.data ?? s.mPhoneNetwork,
            ),
          ),
          _Link(
            active: connected,
            color: Ic.arctic,
            label: connected
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
            active: connected,
            color: context.brand,
            label: connected ? s.mExit : '',
          ),
          _Node(
            icon: const Icon(Icons.public_rounded, color: Ic.text),
            title: s.mInternet,
            subtitle: connected
                ? s.mSitesSeeServer.replaceAll('{country}', loc.country)
                : s.mDirect,
          ),
        ],
      ),
    );
  }
}

class _Node extends StatelessWidget {
  const _Node(
      {required this.icon, required this.title, required this.subtitle});

  final Widget icon;
  final String title;
  final String subtitle;

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
                    style: const TextStyle(color: Ic.textMuted, fontSize: 13)),
            ],
          ),
        ),
      ],
    );
  }
}

/// Vertical connector; dots flow along it while the tunnel is up.
class _Link extends StatelessWidget {
  const _Link({required this.active, required this.color, required this.label});

  final bool active;
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
                color: color,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label,
                style: TextStyle(
                    color: active ? color : Ic.textMuted, fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

class _FlowPainter extends CustomPainter {
  _FlowPainter({required this.time, required this.active, required this.color})
      : super(repaint: active ? time : null);

  final ValueListenable<double> time;
  final bool active;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final x = size.width / 2;
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
      old.active != active || old.color != color;
}

