import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/wb_colors.dart';
import '../shared/wave_params.dart';
import 'effects_quality.dart';
import 'immersive_colors.dart';

/// The V5 surface for every section/card in the app: dark glass with a
/// background blur, a top-to-bottom gradient and a hairline border — all
/// leaning towards the selected location's flag accent (the same tint the
/// rest of the app follows, see [appWaveParamsProvider]), with a faint
/// reflex line along the top edge.
///
/// [blur] is a real backdrop blur; keep it for surfaces that sit over the
/// animated background (cards, sections). Long lists of tiny rows can pass
/// false to save GPU on older phones.
class TintedGlass extends ConsumerWidget {
  const TintedGlass({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 16,
    this.onTap,
    this.tint,
    this.blur = true,
    this.strength = 1.0,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final VoidCallback? onTap;

  /// Overrides the location accent (e.g. amber for an error card).
  final Color? tint;
  final bool blur;

  /// 0..1 — how strongly the accent colors the glass.
  final double strength;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accent = tint ?? ref.watch(appWaveParamsProvider).tint;
    Color lean(Color base, double amount) => accent == null
        ? base
        : Color.lerp(base, accent, amount * strength) ?? base;

    final shape = BorderRadius.circular(radius);
    final decorated = AnimatedContainer(
      duration: const Duration(milliseconds: 500),
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: shape,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            lean(Ic.glassTop, WbColors.surfaceLean),
            lean(Ic.glassMid, WbColors.surfaceLean * 0.35),
            lean(Ic.glassBottom, WbColors.surfaceLean * 0.15),
          ],
        ),
        border: Border.all(color: lean(Ic.glassBorder, WbColors.surfaceBorderLean)),
      ),
      child: child,
    );

    Widget surface = Stack(
      children: [
        decorated,
        // Top reflex.
        Positioned(
          left: radius,
          right: radius,
          top: 0,
          child: IgnorePointer(
            child: Container(
              height: 1,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [
                  Colors.transparent,
                  lean(const Color(0x30D4F7F0), 0.1),
                  Colors.transparent,
                ]),
              ),
            ),
          ),
        ),
      ],
    );

    if (blur && !ref.watch(effectsEconomyProvider)) {
      surface = ClipRRect(
        borderRadius: shape,
        // Grouped: the cards of a page share one backdrop blur pass
        // (BackdropGroup in OceanBackground) instead of one each — a
        // separate blur per card cost ~3 ms of GPU per frame on a phone.
        // Outside a group this is a plain BackdropFilter.
        child: BackdropFilter.grouped(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: surface,
        ),
      );
    }
    if (onTap == null) return surface;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: shape,
        onTap: onTap,
        child: surface,
      ),
    );
  }
}

/// Wraps a screen's content so all its [TintedGlass] cards share one
/// backdrop blur pass. Keeps the same [BackdropKey] across rebuilds — a
/// bare `BackdropGroup(...)` makes a new key on every build, which would
/// rebuild every card on screens that rebuild each frame (metrics).
/// Cards inside one group must not overlap each other.
class GlassGroup extends StatefulWidget {
  const GlassGroup({super.key, required this.child});

  final Widget child;

  @override
  State<GlassGroup> createState() => _GlassGroupState();
}

class _GlassGroupState extends State<GlassGroup> {
  final _key = BackdropKey();

  @override
  Widget build(BuildContext context) =>
      BackdropGroup(backdropKey: _key, child: widget.child);
}
