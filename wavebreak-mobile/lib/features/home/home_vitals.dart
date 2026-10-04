import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/vpn/connection_manager.dart';
import '../../services/vpn/live_metrics.dart';
import '../immersive/immersive_colors.dart';

const _tabular = [FontFeature.tabularFigures()];

String formatMbps(double? mbps) {
  if (mbps == null) return '—';
  if (mbps < 0.1) return mbps == 0 ? '0' : '<0.1';
  if (mbps < 10) return mbps.toStringAsFixed(1);
  return mbps.round().toString();
}

String formatBytes(int bytes) {
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

/// A measured value beside the connect core: big number, unit, caption.
/// Shows a dash until there's a real measurement.
class SideVital extends StatelessWidget {
  const SideVital({
    super.key,
    required this.value,
    required this.unit,
    required this.caption,
    this.alignEnd = false,
    this.color = Ic.text,
  });

  final String value;
  final String unit;
  final String caption;
  final bool alignEnd;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final align = alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    return SizedBox(
      width: 64,
      child: Column(
        crossAxisAlignment: align,
        mainAxisSize: MainAxisSize.min,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: alignEnd ? Alignment.centerRight : Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 24,
                fontWeight: FontWeight.w600,
                fontFeatures: _tabular,
              ),
            ),
          ),
          Text(unit,
              style: const TextStyle(color: Ic.textSecondary, fontSize: 12)),
          const SizedBox(height: 2),
          Text(caption,
              style: const TextStyle(color: Ic.textMuted, fontSize: 12)),
        ],
      ),
    );
  }
}

/// Ping on the left, download on the right, the connect core between.
class CoreWithVitals extends ConsumerWidget {
  const CoreWithVitals({super.key, required this.core});

  final Widget core;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final m = ref.watch(liveMetricsProvider);
    final live = m.active;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SideVital(
          value: live && m.pingMs != null ? '${m.pingMs}' : '—',
          unit: 'мс',
          caption: 'Задержка',
        ),
        Expanded(child: Center(child: core)),
        SideVital(
          value: live ? formatMbps(m.downMbps) : '—',
          unit: 'Mbps',
          caption: 'Загрузка',
          alignEnd: true,
        ),
      ],
    );
  }
}

/// "Protection" row and the session card under the status.
class SessionPanel extends ConsumerWidget {
  const SessionPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status =
        ref.watch(connectionManagerProvider.select((c) => c.status));
    final m = ref.watch(liveMetricsProvider);
    final connected = status == ConnectionStatus.connected;
    final error = status == ConnectionStatus.error;
    final protectColor = connected
        ? Ic.arctic
        : error
            ? Ic.amber
            : Ic.textSecondary;
    return Column(
      children: [
        _GlassCard(
          child: Row(
            children: [
              Icon(
                connected
                    ? Icons.verified_user_rounded
                    : Icons.shield_outlined,
                color: protectColor,
                size: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  connected
                      ? 'Трафик идёт через защищённый туннель'
                      : error
                          ? 'Защита не активна — соединение не установлено'
                          : 'Защита начнётся после подключения',
                  style: TextStyle(color: protectColor, fontSize: 14),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _GlassCard(
          child: Row(
            children: [
              Expanded(
                child: _Cell(
                  title: 'Сессия',
                  value: m.sessionBytes > 0 ? formatBytes(m.sessionBytes) : '—',
                ),
              ),
              Container(width: 1, height: 44, color: Ic.glassBorder),
              Expanded(
                child: _Cell(
                  title: '↓ Приём',
                  value: m.active ? '${formatMbps(m.downMbps)} Mbps' : '—',
                  color: Ic.arctic,
                ),
              ),
              Container(width: 1, height: 44, color: Ic.glassBorder),
              Expanded(
                child: _Cell(
                  title: '↑ Отдача',
                  value: m.active ? '${formatMbps(m.upMbps)} Mbps' : '—',
                  color: Ic.crimson,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({required this.title, required this.value, this.color = Ic.text});

  final String title;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(color: Ic.textMuted, fontSize: 12)),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 16,
                fontWeight: FontWeight.w600,
                fontFeatures: _tabular,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GlassCard extends StatelessWidget {
  const _GlassCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: Ic.glass,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Ic.glassBorder),
      ),
      child: child,
    );
  }
}
