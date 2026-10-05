import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/logging/app_logger.dart';
import '../../core/storage/prefs_store.dart';

/// "Effects quality" (V5): Auto / High / Economy. Economy drops the live
/// backdrop blur on glass surfaces, thins the wave field, draws the
/// sphere without its shader and animates at 20 fps — for older phones.
/// Auto picks economy on low-end Android devices, or on any device that
/// turns out not to keep up (see [FrameBudgetWatcher]). Not related to
/// any network behaviour.
enum EffectsQuality { auto, high, economy }

const _key = 'effects_quality';
const _slowKey = 'effects_auto_slow';

final effectsQualityProvider =
    NotifierProvider<EffectsQualityController, EffectsQuality>(
        EffectsQualityController.new);

class EffectsQualityController extends Notifier<EffectsQuality> {
  @override
  EffectsQuality build() {
    final saved = PrefsStore.getString(_key);
    return EffectsQuality.values.firstWhere(
      (q) => q.name == saved,
      orElse: () => EffectsQuality.auto,
    );
  }

  Future<void> set(EffectsQuality q) async {
    state = q;
    await PrefsStore.setString(_key, q.name);
  }
}

/// Low-RAM devices (the system flag, or under ~3.5 GB — a 3 GB phone
/// reports about 2.8 GB) or Android older than 9 — a heuristic; the
/// measured one is [slowDeviceDetectedProvider].
final lowEndDeviceProvider = FutureProvider<bool>((ref) async {
  if (!Platform.isAndroid) return false;
  try {
    final info = await DeviceInfoPlugin().androidInfo;
    final ramMb = info.physicalRamSize;
    return info.isLowRamDevice ||
        info.version.sdkInt < 28 ||
        (ramMb > 0 && ramMb < 3500);
  } catch (_) {
    return false;
  }
});

/// Set (and remembered) when this phone couldn't hold 30 fps with the full
/// effects — measured, not guessed. Only consulted in Auto: an explicit
/// "High" still gets the full effects.
final slowDeviceDetectedProvider =
    NotifierProvider<SlowDeviceDetected, bool>(SlowDeviceDetected.new);

class SlowDeviceDetected extends Notifier<bool> {
  @override
  bool build() => PrefsStore.getBool(_slowKey);

  Future<void> mark() async {
    if (state) return;
    state = true;
    await PrefsStore.setBool(_slowKey, true);
  }
}

/// True when surfaces should skip blur and the wave field should be thin.
final effectsEconomyProvider = Provider<bool>((ref) {
  return switch (ref.watch(effectsQualityProvider)) {
    EffectsQuality.economy => true,
    EffectsQuality.high => false,
    EffectsQuality.auto => ref.watch(slowDeviceDetectedProvider) ||
        (ref.watch(lowEndDeviceProvider).valueOrNull ?? false),
  };
});

/// Watches real frame times while the full effects are on in Auto: two
/// windows in a row where a frame takes more than ~30 ms on the UI or GPU
/// thread (the phone can't even hold the 30 fps the animations run at)
/// switch Auto to economy for good on this phone. The first seconds after
/// start are skipped (start-up work isn't the steady state).
class FrameBudgetWatcher {
  FrameBudgetWatcher(this._ref);

  final Ref _ref;
  static const _window = 90;
  static const _slowMs = 30.0;
  final _ms = <double>[];
  int _badWindows = 0;
  bool _on = false;
  DateTime _startedAt = DateTime.now();

  void start() {
    if (_on) return;
    _on = true;
    _startedAt = DateTime.now();
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  void _stop() {
    if (!_on) return;
    _on = false;
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
  }

  void _onTimings(List<FrameTiming> timings) {
    if (_ref.read(effectsQualityProvider) != EffectsQuality.auto ||
        _ref.read(effectsEconomyProvider)) {
      _ms.clear();
      _badWindows = 0;
      if (_ref.read(slowDeviceDetectedProvider)) _stop();
      return;
    }
    if (DateTime.now().difference(_startedAt).inSeconds < 4) return;
    for (final t in timings) {
      final build = t.buildDuration.inMicroseconds / 1000;
      final raster = t.rasterDuration.inMicroseconds / 1000;
      _ms.add(build > raster ? build : raster);
    }
    if (_ms.length < _window) return;
    final avg = _ms.reduce((a, b) => a + b) / _ms.length;
    _ms.clear();
    _badWindows = avg > _slowMs ? _badWindows + 1 : 0;
    if (_badWindows >= 2) {
      AppLogger.info(
          'Effects: ${avg.toStringAsFixed(1)} ms per frame — switching Auto to economy');
      _ref.read(slowDeviceDetectedProvider.notifier).mark();
      _stop();
    }
  }
}

final frameBudgetWatcherProvider =
    Provider<FrameBudgetWatcher>((ref) => FrameBudgetWatcher(ref));
