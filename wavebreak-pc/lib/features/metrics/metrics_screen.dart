import '../../core/i18n/language_controller.dart';
import '../../core/theme/wb_theme.dart';
import 'package:flutter/scheduler.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/vpn/connection_manager.dart';
import '../../services/vpn/live_metrics.dart';
import '../home/home_vitals.dart';
import '../home/location_bar.dart';
import '../immersive/immersive_colors.dart';
import '../immersive/tinted_glass.dart';
import '../shared/wave_params.dart';
import '../immersive/wave_field.dart';
import '../shared/flag_icon.dart';
import '../shell/app_shell.dart';
import 'metrics_chart.dart';
import 'metrics_tabs.dart';

/// Connection metrics: measured throughput over the last 1 / 5 minutes and
/// quality cards (latency, jitter, loss, session traffic). Only real
/// samples from [liveMetricsProvider]; before the first session there's an
/// honest empty state, after a session ends its numbers stay, labelled.
class MetricsScreen extends ConsumerStatefulWidget {
  const MetricsScreen({super.key});

  @override
  ConsumerState<MetricsScreen> createState() => _MetricsScreenState();
}

class _MetricsScreenState extends ConsumerState<MetricsScreen>
    with SingleTickerProviderStateMixin {
  Duration _window = const Duration(minutes: 1);
  int _tab = 0;
  double? _touchX;

  // Smooth chart state, advanced every frame (~30 fps) by [_ticker]: the
  // render time trails real time by [_lag] so samples (one a second) are
  // already in the past when the line reaches them — the wave flows out
  // continuously instead of jumping; window width and axis scale ease
  // towards their targets instead of snapping. TickerMode stops the
  // ticker while this tab is off screen.
  static const _lag = 1500.0;
  late final Ticker _ticker = createTicker(_onTick);
  Duration _lastFrame = Duration.zero;
  double _renderNowMs = DateTime.now().millisecondsSinceEpoch - _lag;
  double _windowMs = 60000;
  double _maxMbps = 1;

  @override
  void initState() {
    super.initState();
    _ticker.start();
  }

  void _onTick(Duration elapsed) {
    // Only the chart tab animates; other tabs don't rebuild per frame.
    if (_tab != 0) return;
    if (elapsed - _lastFrame < const Duration(milliseconds: 33)) return;
    _lastFrame = elapsed;
    final rates = ref.read(liveMetricsProvider).rates;
    final targetWindow = _window.inMilliseconds.toDouble();
    final renderNow = DateTime.now().millisecondsSinceEpoch - _lag;
    final windowMs = _windowMs + (targetWindow - _windowMs) * 0.14;
    final peak = ThroughputChartPainter.peakMbps(rates, renderNow, windowMs);
    final targetMax = niceMaxMbps(peak * 1.1);
    setState(() {
      _renderNowMs = renderNow;
      _windowMs =
          (windowMs - targetWindow).abs() < 50 ? targetWindow : windowMs;
      _maxMbps += (targetMax - _maxMbps) * 0.10;
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  RateSample? _sampleAt(List<RateSample> rates, double x) {
    if (rates.isEmpty) return null;
    final t = DateTime.fromMillisecondsSinceEpoch(
        (_renderNowMs - _windowMs + _windowMs * x).round());
    RateSample? best;
    var bestD = 1 << 62;
    for (final s in rates) {
      final d = (s.at.difference(t).inMilliseconds).abs();
      if (d < bestD) {
        bestD = d;
        best = s;
      }
    }
    return bestD < 3000 ? best : null;
  }

  @override
  Widget build(BuildContext context) {
    final connection = ref.watch(connectionManagerProvider);
    final m = ref.watch(liveMetricsProvider);
    final s = ref.watch(stringsProvider);
    final hasData = m.rates.isNotEmpty || m.pings.isNotEmpty;
    final loc = connection.location;
    final touched = _touchX == null ? null : _sampleAt(m.rates, _touchX!);

    return Stack(
      children: [
        Positioned.fill(
          child: WaveField(
            intensity: 0.45,
            layers: 14,
            tint: ref.watch(appWaveParamsProvider).tint,
          ),
        ),
        GlassGroup(
          child: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                  20, 16, 20, kMobileBottomBarReserve + 16),
              children: [
                Text(
                  s.mTitle,
                  style: const TextStyle(
                    color: Ic.text,
                    fontSize: 30,
                    fontFamily: Ic.fontSerif,
                  ),
                ),
                const SizedBox(height: 16),
                _Glass(
                  child: Row(
                    children: [
                      if (!loc.isAuto && loc.countryCode.isNotEmpty) ...[
                        FlagIcon(countryCode: loc.countryCode, width: 28),
                        const SizedBox(width: 12),
                      ],
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              splitPlaceAndProtocol(loc.city).$1.isNotEmpty
                                  ? splitPlaceAndProtocol(loc.city).$1
                                  : loc.country,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Ic.text,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w600),
                            ),
                            Text(
                              [
                                loc.country,
                                if (protocolLabel(loc) != null)
                                  protocolLabel(loc)!
                              ].join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Ic.textMuted, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                      _Badge(
                        text: m.active
                            ? s.mLive
                            : hasData
                                ? s.mLastSession
                                : s.mNoData,
                        color: m.active ? Ic.arctic : Ic.textMuted,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                _Tabs(
                  value: _tab,
                  labels: [s.navMetrics, s.mTabInfo, s.mTabRoute],
                  onChanged: (i) => setState(() => _tab = i),
                ),
                const SizedBox(height: 14),
                if (_tab == 0) ...[
                  _Glass(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(s.mSpeed,
                                  style: const TextStyle(
                                      color: Ic.text,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600)),
                            ),
                            _PeriodToggle(
                              unitMin: s.unitMin,
                              value: _window,
                              onChanged: (w) => setState(() => _window = w),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _Legend(
                                arrow: '↓',
                                label: s.trafficDown,
                                color: Ic.arctic,
                                mbps: touched != null
                                    ? touched.downBps / 1e6
                                    : (m.active ? m.downMbps : null),
                              ),
                            ),
                            Expanded(
                              child: _Legend(
                                arrow: '↑',
                                label: s.trafficUp,
                                color: context.brand,
                                mbps: touched != null
                                    ? touched.upBps / 1e6
                                    : (m.active ? m.upMbps : null),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          height: 190,
                          child: hasData
                              ? LayoutBuilder(
                                  builder: (context, c) => GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onPanDown: (d) => setState(() => _touchX =
                                        ((d.localPosition.dx - 34) /
                                                (c.maxWidth - 34))
                                            .clamp(0.0, 1.0)),
                                    onPanUpdate: (d) => setState(() => _touchX =
                                        ((d.localPosition.dx - 34) /
                                                (c.maxWidth - 34))
                                            .clamp(0.0, 1.0)),
                                    onPanEnd: (_) =>
                                        setState(() => _touchX = null),
                                    onPanCancel: () =>
                                        setState(() => _touchX = null),
                                    child: CustomPaint(
                                      size: Size(c.maxWidth, 190),
                                      painter: ThroughputChartPainter(
                                        samples: m.rates,
                                        upColor: context.brand,
                                        windowMs: _windowMs,
                                        renderNowMs: _renderNowMs,
                                        maxMbps: _maxMbps,
                                        minutesLabel: _window.inMinutes,
                                        unitMin: s.unitMin,
                                        nowLabel: s.mNow,
                                        touchX: _touchX,
                                      ),
                                    ),
                                  ),
                                )
                              : Center(
                                  child: Text(
                                    s.mEmptyChart,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                        color: Ic.textMuted,
                                        fontSize: 14,
                                        height: 1.4),
                                  ),
                                ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 1.35,
                    children: [
                      _QualityCard(
                        title: s.speedTestLatency,
                        value: m.active ? m.pingMs?.toDouble() : null,
                        format: (v) => '${v.round()}',
                        unit: s.unitMs,
                        series: [
                          for (final p in m.pings)
                            if (p.ms != null) p.ms!.toDouble()
                        ],
                        color: Ic.arctic,
                      ),
                      _QualityCard(
                        title: s.mJitter,
                        value: m.jitterMs,
                        format: (v) => v.toStringAsFixed(v < 10 ? 1 : 0),
                        unit: s.unitMs,
                        series: _jitterSeries(m.pings),
                        color: Ic.textSecondary,
                      ),
                      _QualityCard(
                        title: s.mLoss,
                        value: m.lossPercent,
                        format: (v) => v.toStringAsFixed(v < 10 ? 1 : 0),
                        unit: '%',
                        series: [
                          for (final p in m.pings) p.ms == null ? 100.0 : 0.0
                        ],
                        color: Ic.amber,
                        dashed: true,
                      ),
                      _QualityCard(
                        title: s.mSessionTraffic,
                        value: m.sessionBytes > 0
                            ? m.sessionBytes.toDouble()
                            : null,
                        format: (v) => formatBytes(v.round()),
                        unit: '',
                        series: [for (final r in m.rates) r.downBps + r.upBps],
                        color: context.brand,
                      ),
                    ],
                  ),
                ] else if (_tab == 1)
                  InfoTab(connection: connection, metrics: m, s: s)
                else
                  RouteTab(connection: connection, metrics: m, s: s),
              ],
            ),
          ),
        ),
      ],
    );
  }

  static List<double> _jitterSeries(List<PingSample> pings) {
    final ok = [
      for (final p in pings)
        if (p.ms != null) p.ms!.toDouble()
    ];
    return [for (var i = 1; i < ok.length; i++) (ok[i] - ok[i - 1]).abs()];
  }
}

class _QualityCard extends StatelessWidget {
  const _QualityCard({
    required this.title,
    required this.value,
    required this.format,
    required this.unit,
    required this.series,
    required this.color,
    this.dashed = false,
  });

  final String title;
  final double? value;
  final String Function(double) format;
  final String unit;
  final List<double> series;
  final Color color;
  final bool dashed;

  @override
  Widget build(BuildContext context) {
    return _Glass(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              maxLines: 1,
              style: const TextStyle(color: Ic.textMuted, fontSize: 12)),
          const SizedBox(height: 4),
          // Unit right after the number (part of the same text), in a
          // full-width fixed-height slot — nothing around it moves.
          SizedBox(
            height: 28,
            width: double.infinity,
            child: AnimatedValue(
              value: value,
              format: (v) => unit.isEmpty ? format(v) : '${format(v)} $unit',
              style: const TextStyle(
                color: Ic.text,
                fontSize: 22,
                height: 1.2,
                fontWeight: FontWeight.w600,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const Spacer(),
          SizedBox(
            height: 26,
            width: double.infinity,
            child: SmoothSpark(values: series, color: color, dashed: dashed),
          ),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({
    required this.arrow,
    required this.label,
    required this.color,
    required this.mbps,
  });

  final String arrow;
  final String label;
  final Color color;
  final double? mbps;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text('$arrow ',
                style: TextStyle(
                    color: color, fontSize: 20, fontWeight: FontWeight.w600)),
            Expanded(
              child: SizedBox(
                height: 30,
                child: AnimatedValue(
                  value: mbps,
                  format: (v) => '${formatRate(v)} ${rateUnit(v)}',
                  style: const TextStyle(
                    color: Ic.text,
                    fontSize: 22,
                    height: 1.2,
                    fontWeight: FontWeight.w600,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
          ],
        ),
        Text(label,
            style:
                TextStyle(color: color.withValues(alpha: 0.85), fontSize: 13)),
      ],
    );
  }
}

class _PeriodToggle extends StatelessWidget {
  const _PeriodToggle(
      {required this.value, required this.onChanged, required this.unitMin});

  final String unitMin;

  final Duration value;
  final ValueChanged<Duration> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget option(Duration d, String text) {
      final selected = value == d;
      return Semantics(
        selected: selected,
        button: true,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => onChanged(d),
          child: Container(
            constraints: const BoxConstraints(minHeight: 36, minWidth: 52),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: selected ? Ic.text.withValues(alpha: 0.10) : null,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(text,
                style: TextStyle(
                    color: selected ? Ic.text : Ic.textMuted, fontSize: 13)),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Ic.glassBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          option(const Duration(minutes: 1), '1 $unitMin'),
          option(const Duration(minutes: 5), '5 $unitMin'),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(text, style: TextStyle(color: color, fontSize: 12)),
        ],
      ),
    );
  }
}

class _Glass extends StatelessWidget {
  const _Glass({required this.child, this.padding});

  final Widget child;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    return TintedGlass(
      padding: padding ?? const EdgeInsets.all(16),
      child: child,
    );
  }
}

/// Metrics / Info / Route / Logs switch.
class _Tabs extends StatelessWidget {
  const _Tabs({
    required this.value,
    required this.labels,
    required this.onChanged,
  });

  final int value;
  final List<String> labels;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Ic.glassBorder),
        color: Ic.glassBottom.withValues(alpha: 0.6),
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: Semantics(
                selected: i == value,
                button: true,
                child: InkWell(
                  borderRadius: BorderRadius.circular(11),
                  onTap: () => onChanged(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(11),
                      color: i == value
                          ? Ic.text.withValues(alpha: 0.10)
                          : Colors.transparent,
                    ),
                    child: Text(
                      labels[i],
                      maxLines: 1,
                      overflow: TextOverflow.fade,
                      softWrap: false,
                      style: TextStyle(
                        color: i == value ? Ic.text : Ic.textMuted,
                        fontSize: 13,
                        fontWeight:
                            i == value ? FontWeight.w600 : FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
