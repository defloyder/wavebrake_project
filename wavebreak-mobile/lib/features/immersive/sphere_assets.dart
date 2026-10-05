import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The sphere shader (shaders/living_sphere.frag) and the Earth texture,
/// loaded once per app run and shared by the connect core and the sign-in
/// Earth. Null when the platform can't run fragment shaders — callers then
/// draw their gradient fallback.
///
/// Uniform layout: 0-1 uSize, 2 uTime, 3 uRot, 4 uEnergy, 5 uPulse,
/// 6 uMode (0 red core, 1 natural Earth), 7 uWarn; sampler 0 = texture.
class SphereAssets {
  SphereAssets._(this.program, this.texture);

  final ui.FragmentProgram program;
  final ui.Image texture;

  static Future<SphereAssets?>? _future;

  static Future<SphereAssets?> load() => _future ??= _load();

  static Future<SphereAssets?> _load() async {
    try {
      final program =
          await ui.FragmentProgram.fromAsset('shaders/living_sphere.frag');
      final data = await rootBundle.load('assets/textures/earth_surface.webp');
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      codec.dispose();
      return SphereAssets._(program, frame.image);
    } catch (e) {
      debugPrint('Sphere shader unavailable ($e)');
      return null;
    }
  }
}
