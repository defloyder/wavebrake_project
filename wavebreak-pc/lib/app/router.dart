import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/auth/session_controller.dart';
import '../core/storage/prefs_store.dart';
import '../features/auth/forgot_password_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/register_screen.dart';
import '../features/auth/welcome_screen.dart';
import '../features/home/home_screen.dart';
import '../features/locations/locations_screen.dart';
import '../features/settings/about_screen.dart';
import '../features/settings/account_screen.dart';
import '../features/settings/connection_settings_screen.dart';
import '../features/settings/devices_screen.dart';
import '../features/settings/notifications_screen.dart';
import '../features/settings/personalization_screen.dart';
import '../features/settings/security_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/settings/support_screen.dart';
import '../features/shell/app_shell.dart';
import '../features/speedtest/speed_test_screen.dart';
import '../features/splash/splash_screen.dart';
import '../features/subscription/subscription_screen.dart';
import '../features/update/maintenance_screen.dart';
import '../features/update/update_required_screen.dart';
import 'transitions.dart';

final _rootKey = GlobalKey<NavigatorState>();
final _shellKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref.listen(sessionControllerProvider, (_, __) {
    refresh.value++;
  });
  ref.onDispose(refresh.dispose);

  return GoRouter(
    navigatorKey: _rootKey,
    initialLocation: '/splash',
    refreshListenable: refresh,
    redirect: (context, state) {
      final session = ref.read(sessionControllerProvider);
      final loc = state.matchedLocation;
      final isSplash = loc == '/splash';
      final isWelcome = loc == '/welcome';
      final isAuth = loc == '/login' || loc == '/register' || loc == '/forgot';
      final isUpdate = loc == '/update-required';
      final isMaintenance = loc == '/maintenance';

      if (session.phase == SessionPhase.booting) {
        return isSplash ? null : '/splash';
      }
      if (session.phase == SessionPhase.maintenance) {
        return isMaintenance ? null : '/maintenance';
      }
      if (session.phase == SessionPhase.updateRequired) {
        return isUpdate ? null : '/update-required';
      }
      if (session.phase == SessionPhase.unauthenticated) {
        // A fresh install (or first time back at "no session") lands on
        // the guest-vs-account choice before ever seeing a login form —
        // once that choice is made once, later visits go straight to
        // /login instead of asking again.
        final choiceMade = PrefsStore.getBool(PrefsStore.onboardingChoiceMade);
        if (!choiceMade) {
          return isWelcome ? null : '/welcome';
        }
        return isAuth ? null : '/login';
      }
      if (session.phase == SessionPhase.authenticated ||
          session.phase == SessionPhase.guest) {
        if (isSplash || isWelcome || isAuth) return '/home';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),
      GoRoute(
        path: '/welcome',
        pageBuilder: (_, state) =>
            fadeThroughPage(state, const WelcomeScreen()),
      ),
      GoRoute(
        path: '/login',
        pageBuilder: (_, state) => fadeThroughPage(state, const LoginScreen()),
      ),
      GoRoute(
        path: '/register',
        pageBuilder: (_, state) =>
            fadeThroughPage(state, const RegisterScreen()),
      ),
      GoRoute(
        path: '/forgot',
        pageBuilder: (_, state) =>
            fadeThroughPage(state, const ForgotPasswordScreen()),
      ),
      GoRoute(
        path: '/update-required',
        pageBuilder: (_, state) =>
            fadeThroughPage(state, const UpdateRequiredScreen()),
      ),
      GoRoute(
        path: '/maintenance',
        pageBuilder: (_, state) =>
            fadeThroughPage(state, const MaintenanceScreen()),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return AppShell(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(
            navigatorKey: _shellKey,
            routes: [
              GoRoute(
                path: '/home',
                pageBuilder: (_, __) => const NoTransitionPage(
                  child: HomeScreen(),
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/locations',
                pageBuilder: (_, __) => const NoTransitionPage(
                  child: LocationsScreen(),
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/settings',
                pageBuilder: (_, __) => const NoTransitionPage(
                  child: SettingsScreen(),
                ),
                routes: [
                  GoRoute(
                    path: 'account',
                    pageBuilder: (_, state) =>
                        fadeThroughPage(state, const AccountScreen()),
                  ),
                  GoRoute(
                    path: 'security',
                    pageBuilder: (_, state) =>
                        fadeThroughPage(state, const SecurityScreen()),
                  ),
                  GoRoute(
                    path: 'connection',
                    pageBuilder: (_, state) => fadeThroughPage(
                        state, const ConnectionSettingsScreen()),
                  ),
                  GoRoute(
                    path: 'devices',
                    pageBuilder: (_, state) =>
                        fadeThroughPage(state, const DevicesScreen()),
                  ),
                  GoRoute(
                    path: 'notifications',
                    pageBuilder: (_, state) =>
                        fadeThroughPage(state, const NotificationsScreen()),
                  ),
                  GoRoute(
                    path: 'personalization',
                    pageBuilder: (_, state) =>
                        fadeThroughPage(state, const PersonalizationScreen()),
                  ),
                  GoRoute(
                    path: 'support',
                    pageBuilder: (_, state) =>
                        fadeThroughPage(state, const SupportScreen()),
                  ),
                  GoRoute(
                    path: 'about',
                    pageBuilder: (_, state) =>
                        fadeThroughPage(state, const AboutScreen()),
                  ),
                ],
              ),
            ],
          ),
          // Its own proper tab, not a link buried under other UI — see
          // app_shell.dart's _kMobileBranchIndexes. Branch index 3 (after
          // Settings) rather than reordering the existing three: nothing
          // else references branch indices by position, but there's no
          // reason to risk it when appending is just as easy.
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/speed-test',
                pageBuilder: (_, __) => const NoTransitionPage(
                  child: SpeedTestScreen(),
                ),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/subscription',
        pageBuilder: (_, state) =>
            fadeThroughPage(state, const SubscriptionScreen()),
      ),
    ],
  );
});
