import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Fade through, shared by every pushed route: the old screen fades out
/// quickly and the new one fades and settles in right behind it, so the
/// two screens' texts and fields never sit on top of each other (owner,
/// 14.10: switching to "sign in with a code" looked sluggish and messy —
/// the old screen stayed fully visible under the new one fading in).
CustomTransitionPage<void> fadeThroughPage(GoRouterState state, Widget child) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 240),
    reverseTransitionDuration: const Duration(milliseconds: 200),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final fadeIn = CurvedAnimation(
          parent: animation,
          curve: const Interval(0.2, 1, curve: Curves.easeOutCubic));
      final fadeOut = CurvedAnimation(
          parent: secondaryAnimation,
          curve: const Interval(0, 0.35, curve: Curves.easeIn));
      return FadeTransition(
        opacity: Tween(begin: 1.0, end: 0.0).animate(fadeOut),
        child: FadeTransition(
          opacity: fadeIn,
          child: ScaleTransition(
            scale: Tween(begin: 0.985, end: 1.0).animate(fadeIn),
            child: child,
          ),
        ),
      );
    },
  );
}
