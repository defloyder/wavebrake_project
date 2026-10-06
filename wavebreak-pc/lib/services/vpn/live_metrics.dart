import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'connection_manager.dart';
import 'windows_vpn_adapter.dart';

/// One throughput sample, bits per second.
class RateSample {
  const RateSample(this.at, this.downBps, this.upBps);
  final DateTime at;
  final double downBps;
  final double upBps;
}

/// One latency probe through the tunnel; [ms] is null when it failed.
class PingSample {
  const PingSample(this.at, this.ms);
  final DateTime at;
  final int? ms;
}

/// Real, measured numbers for the home and metrics screens. Everything is
/// null/empty until there's been a connected session — the UI shows dashes
/// then, never invented figures. Values of the last session stay after it
/// ends (until the next one starts), like the spec asks.
class LiveMetricsState {
  const LiveMetricsState({
    this.active = false,
    this.downBps,
    this.upBps,
    this.pingMs,
    this.sessionBytes = 0,
    this.rates = const [],
    this.pings = const [],
  });

  final bool active;
  final double? downBps;
  final double? upBps;
  final int? pingMs;

  /// Down + up bytes since the session connected.
  final int sessionBytes;

  /// Last 5 minutes, oldest first.
  final List<RateSample> rates;
  final List<PingSample> pings;

  double? get downMbps => downBps == null ? null : downBps! / 1e6;
  double? get upMbps => upBps == null ? null : upBps! / 1e6;

  /// Mean absolute difference between consecutive successful probes.
  double? get jitterMs {
    final ok = [
      for (final p in pings)
        if (p.ms != null) p.ms!
    ];
    if (ok.length < 3) return null;
    var sum = 0.0;
    for (var i = 1; i < ok.length; i++) {
      sum += (ok[i] - ok[i - 1]).abs();
    }
    return sum / (ok.length - 1);
  }

  /// Share of failed probes, percent.
  double? get lossPercent {
    if (pings.length < 3) return null;
    final failed = pings.where((p) => p.ms == null).length;
    return failed * 100 / pings.length;
  }

  LiveMetricsState copyWith({
    bool? active,
    double? downBps,
    double? upBps,
    int? pingMs,
    bool clearPing = false,
    int? sessionBytes,
    List<RateSample>? rates,
    List<PingSample>? pings,
  }) =>
      LiveMetricsState(
        active: active ?? this.active,
        downBps: downBps ?? this.downBps,
        upBps: upBps ?? this.upBps,
        pingMs: clearPing ? null : (pingMs ?? this.pingMs),
        sessionBytes: sessionBytes ?? this.sessionBytes,
        rates: rates ?? this.rates,
        pings: pings ?? this.pings,
      );
}

final liveMetricsProvider =
    NotifierProvider<LiveMetrics, LiveMetricsState>(LiveMetrics.new);

class LiveMetrics extends Notifier<LiveMetricsState> {
  static const _channel = MethodChannel('app.wavebreak/metrics');
  static const _window = Duration(minutes: 5);

  Timer? _rateTimer;
  Timer? _pingTimer;

  DateTime? _lastAt;

  @override
  LiveMetricsState build() {
    ref.onDispose(_stop);
    ref.listen<ConnectionStatus>(
      connectionManagerProvider.select((s) => s.status),
      (prev, next) {
        if (next == ConnectionStatus.connected &&
            prev != ConnectionStatus.connected) {
          _start();
        } else if (next != ConnectionStatus.connected &&
            prev == ConnectionStatus.connected) {
          _stop();
          state = state.copyWith(active: false);
        }
      },
      fireImmediately: true,
    );
    // Created while already connected (e.g. the VPN was turned on from the
    // Quick Settings tile before the app was opened): fireImmediately has
    // just started the timers — returning a blank state here would mark
    // the running session inactive (dashes on Home, "last session").
    return _rateTimer != null
        ? const LiveMetricsState(active: true)
        : const LiveMetricsState();
  }

  void _start() {
    _stop();

    _lastAt = null;
    _winAt = _winUp = _winDown = null;
    _winSession = 0;
    _winDownBps = _winUpBps = null;
    state = const LiveMetricsState(active: true);
    unawaited(_sampleRates());
    // First probe after a short settle: one taken the very moment the
    // tunnel reports up often fails and showed as packet loss.
    Future<void>.delayed(const Duration(seconds: 2), () {
      if (_pingTimer != null) unawaited(_samplePing());
    });
    _rateTimer = Timer.periodic(
        const Duration(milliseconds: 500), (_) => _sampleRates());
    _pingTimer =
        Timer.periodic(const Duration(seconds: 3), (_) => _samplePing());
  }

  void _stop() {
    _rateTimer?.cancel();
    _pingTimer?.cancel();
    _rateTimer = _pingTimer = null;
  }

  /// Reads what the VPN service measured (TUN bridge counters, smoothed,
  /// session totals since the tunnel came up — see WaveEngineVpnService
  /// sampleTunnelSpeed). Polled twice a second so a new value shows up
  /// right after the service writes it.
  // Windows: sing-box's byte totals (Clash API), turned into rates here —
  // Android's VPN service hands over ready, smoothed rates instead.
  DateTime? _winAt;
  int? _winUp, _winDown;
  int _winSession = 0;
  double? _winDownBps, _winUpBps;

  Future<void> _sampleWindows() async {
    final adapter = ref.read(vpnAdapterProvider);
    if (adapter is! WindowsVpnAdapter) return;
    final now = DateTime.now();
    final prevAt = _winAt;
    // About once a second: half-second deltas jump too much.
    if (prevAt != null && now.difference(prevAt).inMilliseconds < 900) return;
    final totals = await adapter.trafficTotals();
    if (totals == null || _rateTimer == null) return;
    final prevUp = _winUp, prevDown = _winDown;
    _winAt = now;
    _winUp = totals.up;
    _winDown = totals.down;
    if (prevAt == null || prevUp == null || prevDown == null) return;
    // sing-box restarted (recovery): its counters start over.
    final dUp = totals.up >= prevUp ? totals.up - prevUp : totals.up;
    final dDown =
        totals.down >= prevDown ? totals.down - prevDown : totals.down;
    _winSession += dUp + dDown;
    final secs = now.difference(prevAt).inMilliseconds / 1000;
    if (secs <= 0) return;
    double smooth(double? last, double next) =>
        last == null ? next : last * 0.5 + next * 0.5;
    final down = _winDownBps = smooth(_winDownBps, dDown * 8 / secs);
    final up = _winUpBps = smooth(_winUpBps, dUp * 8 / secs);
    final cutoff = now.subtract(_window);
    state = state.copyWith(
      downBps: down,
      upBps: up,
      sessionBytes: _winSession,
      rates: [
        for (final s in state.rates)
          if (s.at.isAfter(cutoff)) s,
        RateSample(now, down, up),
      ],
    );
  }

  Future<void> _sampleRates() async {
    if (Platform.isWindows) return _sampleWindows();
    if (!Platform.isAndroid) return;
    String? raw;
    try {
      raw = await _channel.invokeMethod<String>('liveTraffic');
    } catch (_) {
      return;
    }
    if (raw == null || _rateTimer == null) return;
    final Map<String, dynamic> j;
    try {
      j = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    final at = DateTime.fromMillisecondsSinceEpoch((j['at'] as num).toInt());
    if (_lastAt != null && !at.isAfter(_lastAt!)) return; // not a new sample
    _lastAt = at;
    final down = (j['downBps'] as num).toDouble();
    final up = (j['upBps'] as num).toDouble();
    final cutoff = at.subtract(_window);
    state = state.copyWith(
      downBps: down,
      upBps: up,
      sessionBytes:
          (j['sessionUp'] as num).toInt() + (j['sessionDown'] as num).toInt(),
      rates: [
        for (final s in state.rates)
          if (s.at.isAfter(cutoff)) s,
        RateSample(at, down, up),
      ],
    );
  }

  Future<void> _samplePing() async {
    final ms = await ref.read(vpnAdapterProvider).pingMs();
    if (_pingTimer == null) return;
    final now = DateTime.now();
    final cutoff = now.subtract(_window);
    state = state.copyWith(
      pingMs: ms,
      clearPing: ms == null,
      pings: [
        for (final p in state.pings)
          if (p.at.isAfter(cutoff)) p,
        PingSample(now, ms),
      ],
    );
  }
}
