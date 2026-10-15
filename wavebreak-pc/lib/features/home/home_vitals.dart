import '../../core/theme/wb_theme.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/language_controller.dart';
import '../../services/vpn/connection_manager.dart';
import '../../services/vpn/live_metrics.dart';
import '../immersive/immersive_clock.dart';
import '../immersive/immersive_colors.dart';
import '../immersive/tinted_glass.dart';

// Layout rule for everything here: nothing may change size when a value
// appears or changes. Fixed slot widths, fixed font sizes (no FittedBox
// shrinking), tabular digits, units in their own fixed place, single-line
// texts. Values roll in (AnimatedValue) and a dash cross-fades into the
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

/// A readout that changes like a good odometer: the new number replaces the
/// old one straight away — no counting through the values in between — and
/// only the characters that differ roll (old ones slide out and fade, new
/// ones slide in; up when the value grows, down when it falls). One change
/// at most every [_hold]: readings that come in faster wait and the latest
/// one wins, so the digits don't flicker. Null shows a dash; dash ⇄ number
/// cross-fades.
///
/// Owner (06.10): the previous glide "ran through all the digits" and
/// jumped; asked for a change without the run.
///
/// Driven by the shared ImmersiveClock (30 fps), and only while a change is
/// rolling or waiting: own tickers on five readouts kept Home drawing ~60
/// frames a second while connected (P5). Frozen clock (reduce motion,
/// hidden tab) — the value just swaps.
class AnimatedValue extends StatefulWidget {
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
  State<AnimatedValue> createState() => _AnimatedValueState();
}

class _AnimatedValueState extends State<AnimatedValue> {
  /// One roll, seconds.
  static const _roll = 0.38;

  /// Shortest time a value stays on screen (the service measures speed
  /// once a second).
  static const _hold = 0.9;

  String? _text; // on screen (the target of the last change)
  double? _value;
  String? _from; // the previous text while rolling
  int _dir = 1;
  double? _changedAt; // clock time the last change started
  double? _pending;

  ValueListenable<double>? _clock;
  bool _frozen = true;
  bool _listening = false;

  @override
  void initState() {
    super.initState();
    _value = widget.value;
    _text = _value == null ? null : widget.format(_value!);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final clock = ImmersiveClock.of(context);
    _frozen = ImmersiveClock.frozen(context);
    if (!identical(clock, _clock)) {
      final wasListening = _listening;
      _unlisten();
      _clock = clock;
      _changedAt = null; // a different time base
      if (wasListening) _listen();
    }
    if (_frozen) _settle();
  }

  @override
  void didUpdateWidget(covariant AnimatedValue old) {
    super.didUpdateWidget(old);
    final v = widget.value;
    if (v == null) {
      _text = _value = _from = _pending = null;
      _unlisten();
      return;
    }
    if (_value == null || _frozen) {
      // Dash -> number, or no animation: show it as is.
      _pending = null;
      _from = null;
      _value = v;
      _text = widget.format(v);
      return;
    }
    if (widget.format(v) == _text) {
      _pending = null;
      _value = v;
      return;
    }
    _pending = v;
    _listen();
  }

  /// Applies whatever is waiting, without a roll.
  void _settle() {
    final p = _pending;
    if (p != null) {
      _value = p;
      _text = widget.format(p);
    }
    _pending = _from = null;
    _unlisten();
  }

  void _listen() {
    if (_listening || _clock == null) return;
    _listening = true;
    _clock!.addListener(_tick);
  }

  void _unlisten() {
    if (!_listening) return;
    _listening = false;
    _clock?.removeListener(_tick);
  }

  void _tick() {
    final t = _clock!.value;
    final since = _changedAt == null ? double.infinity : t - _changedAt!;
    final p = _pending;
    if (p != null && since >= _hold) {
      _from = _text;
      _text = widget.format(p);
      _dir = p >= (_value ?? p) ? 1 : -1;
      _value = p;
      _pending = null;
      _changedAt = t;
    } else if (_from != null && since >= _roll) {
      _from = null;
    } else if (_from == null && p == null) {
      _unlisten();
      return;
    }
    setState(() {});
  }

  @override
  void dispose() {
    _unlisten();
    super.dispose();
  }

  Widget _rolling(TextStyle style, String text) {
    final from = _from;
    final at = _changedAt;
    final progress = from == null || at == null || _clock == null
        ? 1.0
        : ((_clock!.value - at) / _roll).clamp(0.0, 1.0);
    if (from == null || progress >= 1) {
      return Text(text, style: style, maxLines: 1, softWrap: false);
    }
    // Only the middle that differs rolls; the same start and end stay put
    // ("28 Kbps" -> "31 Kbps" rolls "28" -> "31", the unit doesn't move).
    var pre = 0;
    while (pre < from.length && pre < text.length && from[pre] == text[pre]) {
      pre++;
    }
    var suf = 0;
    while (suf < from.length - pre &&
        suf < text.length - pre &&
        from[from.length - 1 - suf] == text[text.length - 1 - suf]) {
      suf++;
    }
    final oldMid = from.substring(pre, from.length - suf);
    final newMid = text.substring(pre, text.length - suf);
    final e = Curves.easeOutCubic.transform(progress);
    final shift = (style.fontSize ?? 14) * 0.55;
    final color = style.color ?? DefaultTextStyle.of(context).style.color;
    TextStyle faded(double a) => color == null
        ? style
        : style.copyWith(color: color.withValues(alpha: color.a * a));
    Text plain(String s) => Text(s, style: style, maxLines: 1, softWrap: false);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (pre > 0) plain(text.substring(0, pre)),
        Stack(
          clipBehavior: Clip.none,
          alignment: widget.alignment.x > 0
              ? Alignment.centerRight
              : Alignment.centerLeft,
          children: [
            Transform.translate(
              offset: Offset(0, _dir * shift * (1 - e)),
              child:
                  Text(newMid, style: faded(e), maxLines: 1, softWrap: false),
            ),
            Positioned(
              left: widget.alignment.x > 0 ? null : 0,
              right: widget.alignment.x > 0 ? 0 : null,
              child: Transform.translate(
                offset: Offset(0, -_dir * shift * e),
                child: Text(oldMid,
                    style: faded((1 - e * 1.5).clamp(0.0, 1.0)),
                    maxLines: 1,
                    softWrap: false),
              ),
            ),
          ],
        ),
        if (suf > 0) plain(text.substring(text.length - suf)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = _text;
    // Equal-width digits: a changing number doesn't shift sideways.
    final style = widget.style
        .copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
    final child = text == null
        ? Text('—', key: const ValueKey('dash'), style: style)
        : KeyedSubtree(
            key: const ValueKey('value'),
            // Wider than its slot: overflow like a plain Text did, no
            // layout error.
            child: OverflowBox(
              alignment: widget.alignment,
              maxWidth: double.infinity,
              child: _rolling(style, text),
            ),
          );
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 400),
      layoutBuilder: (current, previous) => Stack(
        alignment: widget.alignment,
        children: [...previous, if (current != null) current],
      ),
      child: child,
    );
  }
}

/// Rate under 1 Mbps in Kbps: light traffic used to read "0 Mbps" (owner:
/// "the download beside the sphere is always 0").
bool rateInKbps(double mbps) => mbps < 1;

/// Two significant digits, like formatMbps: from 100 Kbps up in tens —
/// the last digit only flickered with noise.
String formatRate(double mbps) {
  if (!rateInKbps(mbps)) return formatMbps(mbps);
  final kbps = mbps * 1000;
  if (kbps < 100) return kbps.round().toString();
  final tens = (kbps / 10).round() * 10;
  return (tens > 990 ? 990 : tens).toString();
}

String rateUnit(double? mbps) =>
    mbps != null && rateInKbps(mbps) ? 'Kbps' : 'Mbps';

/// A measured value beside the connect core: number, unit, caption — in a
/// fixed-width slot. Unit and caption shrink rather than clip (a narrow
/// phone or a large text size used to cut "Загрузка").
class SideVital extends StatelessWidget {
  const SideVital({
    super.key,
    required this.value,
    required this.format,
    required this.unit,
    required this.caption,
    this.alignEnd = false,
  });

  /// The slot width (home_screen keeps the sphere clear of two of these).
  static const width = 64.0;

  final double? value;
  final String Function(double) format;
  final String unit;
  final String caption;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final align = alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final along = alignEnd ? Alignment.centerRight : Alignment.centerLeft;
    Widget fit(Widget child) => SizedBox(
          width: width,
          child:
              FittedBox(fit: BoxFit.scaleDown, alignment: along, child: child),
        );
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: align,
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 30,
            width: width,
            child: AnimatedValue(
              value: value,
              format: format,
              alignment: along,
              style: const TextStyle(
                color: Ic.text,
                fontSize: 22,
                height: 1.2,
                fontWeight: FontWeight.w600,
                fontFeatures: _tabular,
              ),
            ),
          ),
          fit(Text(unit,
              maxLines: 1,
              style: const TextStyle(color: Ic.textSecondary, fontSize: 12))),
          const SizedBox(height: 2),
          fit(Text(caption,
              maxLines: 1,
              style: const TextStyle(color: Ic.textMuted, fontSize: 12))),
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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const _PingVital(),
        Expanded(child: Center(child: core)),
        const _DownVital(),
      ],
    );
  }
}

/// The same two readouts in a row under the sphere — for phones too narrow
/// to keep them beside it without covering it.
class VitalsRow extends StatelessWidget {
  const VitalsRow({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [_PingVital(), _DownVital()],
      ),
    );
  }
}

class _PingVital extends ConsumerWidget {
  const _PingVital();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final m = ref.watch(liveMetricsProvider);
    final s = ref.watch(stringsProvider);
    return SideVital(
      value: m.active ? m.pingMs?.toDouble() : null,
      format: (v) => v.round().toString(),
      unit: s.unitMs,
      caption: s.speedTestLatency,
    );
  }
}

class _DownVital extends ConsumerWidget {
  const _DownVital();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final m = ref.watch(liveMetricsProvider);
    final s = ref.watch(stringsProvider);
    final mbps = m.active ? m.downMbps : null;
    return SideVital(
      value: mbps,
      format: formatRate,
      unit: rateUnit(mbps),
      caption: s.speedTestDownload,
      alignEnd: true,
    );
  }
}

/// One card under the status: the "protection" line with the session
/// clock, the session readouts, and [footer] (Home puts the subscription
/// line there). Owner, 06.10: two separate cards plus the subscription
/// card made Home scroll. Rows keep their height in every state.
class SessionPanel extends ConsumerWidget {
  const SessionPanel({super.key, this.footer});

  final Widget? footer;

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
    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            // Fixed (values never resize the card), but scaled with the
            // app text size — at 1.3 a fixed 24/46 overflowed.
            height: MediaQuery.textScalerOf(context).scale(24),
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
                    // From the theme: a bare TextStyle here replaced the
                    // app font (Inter) with the system one.
                    style: DefaultTextStyle.of(context).style.copyWith(
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
          const SizedBox(height: 10),
          Container(height: 1, color: Ic.glassBorder),
          const SizedBox(height: 10),
          SizedBox(
            height: MediaQuery.textScalerOf(context).scale(46),
            child: Row(
              children: [
                Expanded(
                  child: _Cell(
                    title: s.sessionTitle,
                    value:
                        m.sessionBytes > 0 ? m.sessionBytes.toDouble() : null,
                    format: (v) => formatBytes(v.round()),
                  ),
                ),
                Container(width: 1, color: Ic.glassBorder),
                Expanded(
                  child: _Cell(
                    title: '↓ ${s.trafficDown}',
                    value: m.active ? m.downMbps : null,
                    format: (v) => '${formatRate(v)} ${rateUnit(v)}',
                    color: Ic.arctic,
                  ),
                ),
                Container(width: 1, color: Ic.glassBorder),
                Expanded(
                  child: _Cell(
                    title: '↑ ${s.trafficUp}',
                    value: m.active ? m.upMbps : null,
                    format: (v) => '${formatRate(v)} ${rateUnit(v)}',
                    color: context.brand,
                  ),
                ),
              ],
            ),
          ),
          if (footer != null) ...[
            const SizedBox(height: 10),
            Container(height: 1, color: Ic.glassBorder),
            const SizedBox(height: 10),
            footer!,
          ],
        ],
      ),
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
            height: MediaQuery.textScalerOf(context).scale(22),
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
