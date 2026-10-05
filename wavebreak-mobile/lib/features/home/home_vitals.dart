import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/language_controller.dart';
import '../../services/vpn/connection_manager.dart';
import '../../services/vpn/live_metrics.dart';
import '../immersive/immersive_colors.dart';
import '../immersive/tinted_glass.dart';

// Layout rule for everything here: nothing may change size when a value
// appears or changes. Fixed slot widths, fixed font sizes (no FittedBox
// shrinking), tabular digits, units in their own fixed place, single-line
// texts. Values glide (AnimatedValue) and a dash cross-fades into the
// first value instead of popping.

const _tabular = [FontFeature.tabularFigures()];

String formatMbps(double? mbps) {
  if (mbps == null) return '—';
  if (mbps < 0.05) return '0';
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

/// A number that glides to its new value (~0.9 s) instead of jumping.
/// Null shows a dash; dash ⇄ number cross-fades.
class AnimatedValue extends StatelessWidget {
  const AnimatedValue({
    super.key,
    required this.value,
    required this.format,
    required this.style,
    this.alignment = Alignment.centerLeft,
  });

  final double? value;
  final String Function(double) format;
  final TextStyle style;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    final child = value == null
        ? Text('—', key: const ValueKey('dash'), style: style)
        : TweenAnimationBuilder<double>(
            key: const ValueKey('value'),
            tween: Tween(end: value),
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeOutCubic,
            builder: (_, v, __) =>
                Text(format(v), style: style, maxLines: 1, softWrap: false),
          );
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 400),
      layoutBuilder: (current, previous) => Stack(
        alignment: alignment,
        children: [...previous, if (current != null) current],
      ),
      child: child,
    );
  }
}

/// A measured value beside the connect core: number, unit, caption — in a
/// fixed-width slot.
class SideVital extends StatelessWidget {
  const SideVital({
    super.key,
    required this.value,
    required this.format,
    required this.unit,
    required this.caption,
    this.alignEnd = false,
  });

  final double? value;
  final String Function(double) format;
  final String unit;
  final String caption;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final align = alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    return SizedBox(
      width: 68,
      child: Column(
        crossAxisAlignment: align,
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 30,
            width: 68,
            child: AnimatedValue(
              value: value,
              format: format,
              alignment:
                  alignEnd ? Alignment.centerRight : Alignment.centerLeft,
              style: const TextStyle(
                color: Ic.text,
                fontSize: 22,
                height: 1.2,
                fontWeight: FontWeight.w600,
                fontFeatures: _tabular,
              ),
            ),
          ),
          Text(unit,
              maxLines: 1,
              style: const TextStyle(color: Ic.textSecondary, fontSize: 12)),
          const SizedBox(height: 2),
          Text(caption,
              maxLines: 1,
              overflow: TextOverflow.fade,
              softWrap: false,
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
          value: live ? m.pingMs?.toDouble() : null,
          format: (v) => v.round().toString(),
          unit: 'мс',
          caption: 'Задержка',
        ),
        Expanded(child: Center(child: core)),
        SideVital(
          value: live ? m.downMbps : null,
          format: formatMbps,
          unit: 'Mbps',
          caption: 'Загрузка',
          alignEnd: true,
        ),
      ],
    );
  }
}

/// "Protection" row and the session card under the status. Both keep the
/// same height in every state.
class SessionPanel extends ConsumerWidget {
  const SessionPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(connectionManagerProvider.select((c) => c.status));
    final s = ref.watch(stringsProvider);
    final connectedAt =
        ref.watch(connectionManagerProvider.select((c) => c.connectedAt));
    final m = ref.watch(liveMetricsProvider);
    final connected = status == ConnectionStatus.connected;
    final busy = status == ConnectionStatus.requestingProfile ||
        status == ConnectionStatus.connecting ||
        status == ConnectionStatus.configPending;
    final (protectIcon, protectColor, protectText) = switch (status) {
      ConnectionStatus.connected => (
          Icons.verified_user_rounded,
          Ic.arctic,
          s.protectOn
        ),
      ConnectionStatus.disconnecting => (
          Icons.shield_outlined,
          Ic.textSecondary,
          s.protectDisconnecting
        ),
      _ when busy => (
          Icons.shield_outlined,
          Ic.textSecondary,
          s.protectConnecting
        ),
      ConnectionStatus.error => (Icons.gpp_bad_rounded, Ic.amber, s.protectOff),
      _ => (Icons.gpp_maybe_outlined, Ic.crimson, s.protectOff),
    };
    return Column(
      children: [
        _GlassCard(
          child: SizedBox(
            height: 24,
            child: Row(
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: busy
                      ? const SizedBox(
                          key: ValueKey('busy'),
                          width: 22,
                          height: 22,
                          child: Padding(
                            padding: EdgeInsets.all(3),
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Ic.arctic),
                          ),
                        )
                      : Icon(protectIcon,
                          key: ValueKey(protectIcon),
                          color: protectColor,
                          size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 300),
                    style: TextStyle(
                        color: protectColor,
                        fontSize: 15,
                        fontWeight: FontWeight.w600),
                    child: Text(protectText,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ),
                // Session time from the real start moment (wall clock).
                if (connected && connectedAt != null)
                  _SessionClock(since: connectedAt),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _GlassCard(
          child: SizedBox(
            height: 46,
            child: Row(
              children: [
                Expanded(
                  child: _Cell(
                    title: 'Сессия',
                    value:
                        m.sessionBytes > 0 ? m.sessionBytes.toDouble() : null,
                    format: (v) => formatBytes(v.round()),
                  ),
                ),
                Container(width: 1, color: Ic.glassBorder),
                Expanded(
                  child: _Cell(
                    title: '↓ Приём',
                    value: m.active ? m.downMbps : null,
                    format: (v) => "${formatMbps(v)} Mbps",
                    color: Ic.arctic,
                  ),
                ),
                Container(width: 1, color: Ic.glassBorder),
                Expanded(
                  child: _Cell(
                    title: '↑ Отдача',
                    value: m.active ? m.upMbps : null,
                    format: (v) => "${formatMbps(v)} Mbps",
                    color: Ic.crimson,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({
    required this.title,
    required this.value,
    required this.format,
    this.color = Ic.text,
  });

  final String title;
  final double? value;
  final String Function(double) format;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(title,
              maxLines: 1,
              overflow: TextOverflow.fade,
              softWrap: false,
              style: const TextStyle(color: Ic.textMuted, fontSize: 12)),
          const SizedBox(height: 4),
          SizedBox(
            height: 22,
            child: AnimatedValue(
              value: value,
              format: format,
              style: TextStyle(
                color: color,
                fontSize: 17,
                height: 1.2,
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
    return TintedGlass(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: child,
    );
  }
}

/// hh:mm:ss since [since], ticking once a second; tabular digits so the
/// row never shifts.
class _SessionClock extends StatefulWidget {
  const _SessionClock({required this.since});

  final DateTime since;

  @override
  State<_SessionClock> createState() => _SessionClockState();
}

class _SessionClockState extends State<_SessionClock> {
  late final Timer _timer =
      Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _timer; // start
    final d = DateTime.now().difference(widget.since);
    String two(int v) => v.toString().padLeft(2, '0');
    final text =
        '${two(d.inHours)}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
    return Text(
      text,
      style: const TextStyle(
        color: Ic.textSecondary,
        fontSize: 14,
        fontFeatures: _tabular,
      ),
    );
  }
}
