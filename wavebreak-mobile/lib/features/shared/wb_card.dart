import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/wb_colors.dart';
import 'wave_params.dart';

/// A translucent card: alpha-blended rather than a flat opaque fill, so the
/// ocean background (and its current flag tint) reads through every
/// surface instead of stopping at the card's edge. Deliberately NOT a live
/// [BackdropFilter] blur — this type is instantiated many times per screen
/// (every settings row, every device, every plan), and a real-time blur
/// pass per instance is the kind of cost that reads fine on a desktop/
/// emulator but turns visibly janky on real mid-range phones once several
/// are on screen at once. Save blur for the few chrome surfaces that only
/// ever have one instance on screen (nav bar, sheets, connect button).
class WbCard extends ConsumerWidget {
  const WbCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(16),
    this.tint,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets padding;

  /// Accent tinting the border a little instead of the flat default.
  /// Defaults to the app's current location-accent tint (see
  /// [appWaveParamsProvider]) when not given explicitly, so every card
  /// picks it up without each call site having to thread it through.
  final Color? tint;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final effectiveTint = tint ?? ref.watch(appWaveParamsProvider).tint;
    final borderColor =
        effectiveTint == null ? WbColors.ice08 : effectiveTint.withValues(alpha: 0.28);
    final body = Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: WbColors.card.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor),
      ),
      child: child,
    );
    if (onTap == null) return body;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: body,
      ),
    );
  }
}
