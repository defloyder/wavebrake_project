import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/env/app_env.dart';

/// PC and TV: a short plain fade (owner, 16.10: pages and blocks still
/// appeared "with a drag" on a PC, in economy mode too). The scale-in was
/// the costly part — it renders the whole incoming page (animated
/// background and all) off screen every frame of the transition.
final bool _quick = AppEnv.isTv || Platform.isWindows;

/// Fade through, shared by every pushed route: the old screen fades out
/// quickly and the new one fades and settles in right behind it, so the
/// two screens' texts and fields never sit on top of each other (owner,
/// 14.10: switching to "sign in with a code" looked sluggish and messy —
/// the old screen stayed fully visible under the new one fading in).
CustomTransitionPage<void> fadeThroughPage(GoRouterState state, Widget child) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: Duration(milliseconds: _quick ? 140 : 240),
    reverseTransitionDuration: Duration(milliseconds: _quick ? 120 : 200),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final fadeIn = CurvedAnimation(
          parent: animation,
          curve: Interval(_quick ? 0.15 : 0.2, 1, curve: Curves.easeOutCubic));
      final fadeOut = CurvedAnimation(
          parent: secondaryAnimation,
          curve: Interval(0, _quick ? 0.4 : 0.35, curve: Curves.easeIn));
      final incoming = FadeTransition(
        opacity: fadeIn,
        child: _quick
            ? child
            : ScaleTransition(
                scale: Tween(begin: 0.985, end: 1.0).animate(fadeIn),
                child: child,
              ),
      );
      return FadeTransition(
        opacity: Tween(begin: 1.0, end: 0.0).animate(fadeOut),
        child: incoming,
      );
    },
  );
}
