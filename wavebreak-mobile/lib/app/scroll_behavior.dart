import 'package:flutter/material.dart';

/// No scrollbars anywhere (owner, 16.10: on the PC and TV the bar looked
/// out of place, stuck to a section's edge). Lists still scroll with the
/// wheel, touch, keys and the remote; mouse dragging works as on a phone.
class WbScrollBehavior extends MaterialScrollBehavior {
  const WbScrollBehavior();

  @override
  Widget buildScrollbar(
          BuildContext context, Widget child, ScrollableDetails details) =>
      child;
}
