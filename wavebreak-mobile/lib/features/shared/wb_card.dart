import 'package:flutter/material.dart';

import '../immersive/tinted_glass.dart';

/// The app's card: since V5 the shared [TintedGlass] surface — dark glass
/// with blur and a gradient leaning towards the selected location's flag
/// accent, so every screen that uses cards follows the new design and the
/// current flag tint without each call site threading it through.
class WbCard extends StatelessWidget {
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

  /// Accent override; defaults to the current location-accent tint.
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    // Personalization: compact density trims the default padding.
    final compact = Theme.of(context).visualDensity.vertical < 0;
    return TintedGlass(
      padding: compact && padding == const EdgeInsets.all(16)
          ? const EdgeInsets.all(12)
          : padding,
      radius: 18,
      onTap: onTap,
      tint: tint,
      child: child,
    );
  }
}
