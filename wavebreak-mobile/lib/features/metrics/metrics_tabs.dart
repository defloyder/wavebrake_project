import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/logging/app_logger.dart';
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

String _statusText(ConnectionStatus s) => switch (s) {
      ConnectionStatus.connected => 'Подключено',
      ConnectionStatus.connecting ||
      ConnectionStatus.requestingProfile ||
      ConnectionStatus.configPending =>
        'Подключение…',
      ConnectionStatus.disconnecting => 'Отключение…',
      ConnectionStatus.error => 'Ошибка подключения',
      ConnectionStatus.idle => 'Не подключено',
    };

String _hm(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// Connection facts — only what the app actually knows.
class InfoTab extends StatelessWidget {
  const InfoTab({super.key, required this.connection, required this.metrics});

  final WbConnectionState connection;
  final LiveMetricsState metrics;

  @override
  Widget build(BuildContext context) {
    final loc = connection.location;
    final (place, _) = splitPlaceAndProtocol(loc.city);
    final since = connection.connectedAt;
    final connected = connection.status == ConnectionStatus.connected;
    final rows = <(String, String)>[
      ('Локация', [if (place.isNotEmpty) place, loc.country].join(' · ')),
      ('Протокол', protocolLabel(loc) ?? '—'),
      ('Статус', _statusText(connection.status)),
      ('Начало сессии', connected && since != null ? _hm(since) : '—'),
      (
        'Трафик сессии',
        metrics.sessionBytes > 0 ? formatBytes(metrics.sessionBytes) : '—'
      ),
      (
        'Задержка',
        metrics.active && metrics.pingMs != null ? '${metrics.pingMs} мс' : '—'
      ),
      (
        'Джиттер',
        metrics.jitterMs != null
            ? '${metrics.jitterMs!.toStringAsFixed(1)} мс'
            : '—'
      ),
      (
        'Потери',
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
                _Row(label: 'Сеть телефона', value: snap.data ?? '—'),
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
  const RouteTab({super.key, required this.connection, required this.metrics});

  final WbConnectionState connection;
  final LiveMetricsState metrics;

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
              title: 'Это устройство',
              subtitle: snap.data ?? 'сеть телефона',
            ),
          ),
          _Link(
            active: connected,
            color: Ic.arctic,
            label: connected
                ? 'зашифрованный туннель'
                    '${metrics.pingMs != null ? ' · ${metrics.pingMs} мс' : ''}'
                : 'туннель не установлен',
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
            color: Ic.crimson,
            label: connected ? 'выход в интернет' : '',
          ),
          _Node(
            icon: const Icon(Icons.public_rounded, color: Ic.text),
            title: 'Интернет',
            subtitle: connected
                ? 'сайты видят адрес сервера (${loc.country})'
                : 'напрямую, без защиты',
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

/// The app's own recent log lines (emails, links, ids masked).
class LogsTab extends StatefulWidget {
  const LogsTab({super.key});

  @override
  State<LogsTab> createState() => _LogsTabState();
}

class _LogsTabState extends State<LogsTab> {
  late final Timer _refresh =
      Timer.periodic(const Duration(seconds: 2), (_) => setState(() {}));

  @override
  void initState() {
    super.initState();
    _refresh;
  }

  @override
  void dispose() {
    _refresh.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lines = AppLogger.recent(80).reversed.toList();
    return TintedGlass(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: lines.isEmpty
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text('Журнал пуст',
                    style: TextStyle(color: Ic.textMuted, fontSize: 14)),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final l in lines)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Text(
                      // Drop the date part of the ISO timestamp.
                      l.length > 11 ? l.substring(11) : l,
                      style: const TextStyle(
                        color: Ic.textSecondary,
                        fontSize: 11,
                        height: 1.3,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
