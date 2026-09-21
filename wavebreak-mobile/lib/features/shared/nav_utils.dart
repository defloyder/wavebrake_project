import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// Pops the current route, or navigates to [fallback] when there is nothing
/// to pop (e.g. the screen was reached via a deep link with an empty stack).
void safePop(BuildContext context, {String fallback = '/home'}) {
  if (context.canPop()) {
    context.pop();
  } else {
    context.go(fallback);
  }
}
