import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/logging/app_logger.dart';
import 'connection_manager.dart';

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
    final ok = [for (final p in pings) if (p.ms != null) p.ms!];
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
  int? _lastRx, _lastTx, _baseRx, _baseTx;
  DateTime? _lastAt;
  bool _unsupported = false;

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
    return const LiveMetricsState();
  }

  void _start() {
    _stop();
    _lastRx = _lastTx = _baseRx = _baseTx = null;
    _lastAt = null;
    state = const LiveMetricsState(active: true);
    unawaited(_sampleRates());
    unawaited(_samplePing());
    _rateTimer = Timer.periodic(const Duration(seconds: 1), (_) => _sampleRates());
    _pingTimer = Timer.periodic(const Duration(seconds: 3), (_) => _samplePing());
  }

  void _stop() {
    _rateTimer?.cancel();
    _pingTimer?.cancel();
    _rateTimer = _pingTimer = null;
  }

  Future<List<int>?> _uidBytes() async {
    if (_unsupported || !Platform.isAndroid) return null;
    try {
      final r = await _channel.invokeListMethod<int>('uidBytes');
      if (r == null || r.length < 2 || r[0] < 0 || r[1] < 0) {
        _unsupported = true;
        AppLogger.info('Live metrics: per-UID traffic not accounted here');
        return null;
      }
      return r;
    } catch (_) {
      return null;
    }
  }

  Future<void> _sampleRates() async {
    final bytes = await _uidBytes();
    if (bytes == null || _rateTimer == null && _lastAt != null) return;
    final now = DateTime.now();
    final rx = bytes[0], tx = bytes[1];
    _baseRx ??= rx;
    _baseTx ??= tx;
    if (_lastAt != null) {
      final dt = now.difference(_lastAt!).inMicroseconds / 1e6;
      if (dt > 0.2) {
        final down = math.max(0, rx - _lastRx!) * 8 / dt;
        final up = math.max(0, tx - _lastTx!) * 8 / dt;
        final cutoff = now.subtract(_window);
        final rates = [
          for (final s in state.rates) if (s.at.isAfter(cutoff)) s,
          RateSample(now, down, up),
        ];
        state = state.copyWith(
          downBps: down,
          upBps: up,
          sessionBytes: (rx - _baseRx!) + (tx - _baseTx!),
          rates: rates,
        );
      }
    }
    _lastRx = rx;
    _lastTx = tx;
    _lastAt = now;
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
        for (final p in state.pings) if (p.at.isAfter(cutoff)) p,
        PingSample(now, ms),
      ],
    );
  }
}
