import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wavebreak/app/desktop_history.dart';

void main() {
  testWidgets('mouse side buttons and Alt+arrows walk the visited pages',
      (tester) async {
    Widget page(String name) => Scaffold(body: Center(child: Text(name)));
    final router = GoRouter(initialLocation: '/home', routes: [
      GoRoute(path: '/home', builder: (_, __) => page('home')),
      GoRoute(path: '/metrics', builder: (_, __) => page('metrics')),
      GoRoute(
        path: '/settings',
        builder: (_, __) => page('settings'),
        routes: [
          GoRoute(path: 'connection', builder: (_, __) => page('connection')),
        ],
      ),
      GoRoute(path: '/login', builder: (_, __) => page('login')),
    ]);
    await tester.pumpWidget(MaterialApp.router(
      routerConfig: router,
      builder: (context, child) =>
          DesktopHistory(router: router, child: child!),
    ));
    await tester.pumpAndSettle();
    String where() =>
        router.routerDelegate.currentConfiguration.uri.toString();

    router.go('/metrics');
    await tester.pumpAndSettle();
    router.go('/settings/connection');
    await tester.pumpAndSettle();

    Future<void> mouse(int buttons) async {
      final g = await tester.createGesture(
          kind: PointerDeviceKind.mouse, buttons: buttons);
      await g.down(const Offset(100, 100));
      await g.up();
      await tester.pumpAndSettle();
    }

    await mouse(kBackMouseButton);
    expect(where(), '/metrics');
    await mouse(kBackMouseButton);
    expect(where(), '/home');
    await mouse(kBackMouseButton);
    expect(where(), '/home', reason: 'nothing before the first page');

    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pumpAndSettle();
    expect(where(), '/metrics');
    await mouse(kForwardMouseButton);
    expect(where(), '/settings/connection');

    // A new visit drops what was ahead; sign-in is never recorded.
    await mouse(kBackMouseButton);
    router.go('/login');
    await tester.pumpAndSettle();
    router.go('/home');
    await tester.pumpAndSettle();
    await mouse(kForwardMouseButton);
    expect(where(), '/home');
    await mouse(kBackMouseButton);
    expect(where(), '/metrics');
  });
}
