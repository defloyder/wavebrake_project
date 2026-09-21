import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// A gentle fade + scale transition shared by every pushed route, so
/// navigating never shows two full screens sliding past each other —
/// the old screen fades out just as the new one fades in and settles.
CustomTransitionPage<void> fadeThroughPage(GoRouterState state, Widget child) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 260),
    reverseTransitionDuration: const Duration(milliseconds: 220),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween(begin: 0.98, end: 1.0).animate(curved),
          child: child,
        ),
      );
    },
  );
}
