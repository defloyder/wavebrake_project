import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/prefs_store.dart';

/// "Effects quality" (V5): Auto / High / Economy. Economy drops the live
/// backdrop blur on glass surfaces and thins the wave field — for older
/// phones. Auto picks economy on low-end Android devices. Not related to
/// any network behaviour.
enum EffectsQuality { auto, high, economy }

const _key = 'effects_quality';

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

/// Low-RAM devices or Android older than 9 — a heuristic, not a measured
/// frame rate.
final lowEndDeviceProvider = FutureProvider<bool>((ref) async {
  if (!Platform.isAndroid) return false;
  try {
    final info = await DeviceInfoPlugin().androidInfo;
    return info.isLowRamDevice || info.version.sdkInt < 28;
  } catch (_) {
    return false;
  }
});

/// True when surfaces should skip blur and the wave field should be thin.
final effectsEconomyProvider = Provider<bool>((ref) {
  return switch (ref.watch(effectsQualityProvider)) {
    EffectsQuality.economy => true,
    EffectsQuality.high => false,
    EffectsQuality.auto => ref.watch(lowEndDeviceProvider).valueOrNull ?? false,
  };
});
