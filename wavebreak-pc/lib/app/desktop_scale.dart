import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../features/tv/tv_scale.dart';

/// Windows, a big window or full screen (owner, 17.10: "full screen looks
/// awful" — the layout is drawn for a window of about [_design], so on a
/// 2K screen it sat as a small island in the middle). Above that size the
/// whole app is laid out on a [_design]-sized canvas and drawn scaled up
/// to fill the window, the way [TvScale] draws the TV one scaled down.
/// Up to [_maxScale]; a normal window is untouched.
class DesktopScale extends StatelessWidget {
  const DesktopScale({super.key, required this.child});

  final Widget child;

  static const _design = Size(1366, 820);
  static const _maxScale = 1.6;

  /// How much a window of [size] is scaled up: 1 up to [_design].
  static double scaleFor(Size size) => math
      .min(size.width / _design.width, size.height / _design.height)
      .clamp(1.0, _maxScale);

  @override
  Widget build(BuildContext context) {
    final scale = scaleFor(MediaQuery.sizeOf(context));
    // Below 1 % it isn't worth the transform.
    if (scale < 1.01) return child;
    return TvScale(scale: scale, child: child);
  }
}
