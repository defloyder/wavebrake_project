import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/env/app_env.dart';
import '../core/i18n/language_controller.dart';
import '../core/network/connectivity_provider.dart';
import '../core/theme/personalization_controller.dart';
import '../core/theme/wb_colors.dart';
import '../core/theme/wb_theme.dart';
import '../features/shared/app_lock_gate.dart';
import '../features/shared/data_providers.dart';
import '../services/notification/status_notification_service.dart';
import '../services/vpn/connection_manager.dart';
import 'router.dart';

/// On Android, the real VLESS tunnel ([V2RayVpnAdapter]) already brings its
/// own mandatory foreground-service notification — Android requires any
/// active VpnService to show one, and it can't be suppressed. Pushing our
/// own branded notification on top of that used to leave two separate
/// entries sitting in the shade at once. There's exactly one real native
/// notification slot on this path, so it's fed WAVEBREAK's own branding
/// directly (see V2RayVpnAdapter.connect's `remark`/disconnect-button
/// params) and our custom one is skipped entirely here. Every other
/// adapter (simulated, Windows, the iOS/desktop stub) has no such native
/// notification to collide with, so it keeps using the custom one.
bool get _usesNativeAndroidNotification =>
    Platform.isAndroid &&
    !AppEnv.useSimulatedVpn &&
    AppEnv.accessProtocol == 'vless';

const _statusNotifier = StatusNotificationService();

class WavebreakApp extends ConsumerStatefulWidget {
  const WavebreakApp({super.key});

  @override
  ConsumerState<WavebreakApp> createState() => _WavebreakAppState();
}

final _scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

class _WavebreakAppState extends ConsumerState<WavebreakApp> {
  Timer? _pingTicker;

  void _updateNotification(ConnectionStatus status) {
    final s = ref.read(stringsProvider);
    final skipCustom = _usesNativeAndroidNotification;
    switch (status) {
      case ConnectionStatus.connected:
        if (!skipCustom) {
          _statusNotifier.show(title: 'WAVEBREAK', text: s.connected);
        }
        _startPingTicker();
      case ConnectionStatus.configPending:
        if (!skipCustom) {
          _statusNotifier.show(title: 'WAVEBREAK', text: s.configPending);
        }
        _stopPingTicker();
      case ConnectionStatus.connecting:
      case ConnectionStatus.requestingProfile:
        if (!skipCustom) {
          _statusNotifier.show(title: 'WAVEBREAK', text: s.connecting);
        }
        _stopPingTicker();
      case ConnectionStatus.disconnecting:
        if (!skipCustom) {
          _statusNotifier.show(title: 'WAVEBREAK', text: s.disconnecting);
        }
        _stopPingTicker();
      case ConnectionStatus.idle:
      case ConnectionStatus.error:
        if (!skipCustom) {
          _statusNotifier.hide();
        }
        _stopPingTicker();
    }
  }

  void _startPingTicker() {
    if (_usesNativeAndroidNotification) return;
    _pingTicker?.cancel();
    _refreshPing();
    _pingTicker =
        Timer.periodic(const Duration(seconds: 20), (_) => _refreshPing());
  }

  void _stopPingTicker() {
    _pingTicker?.cancel();
    _pingTicker = null;
  }

  Future<void> _refreshPing() async {
    if (_usesNativeAndroidNotification) {
      return;
    }
    if (ref.read(connectionManagerProvider).status !=
        ConnectionStatus.connected) {
      return;
    }
    final ms = await ref.read(vpnAdapterProvider).pingMs();
    if (!mounted ||
        ref.read(connectionManagerProvider).status !=
            ConnectionStatus.connected) {
      return;
    }
    final s = ref.read(stringsProvider);
    _statusNotifier.show(
      title: 'WAVEBREAK',
      text: ms != null ? '${s.connected} · $ms ms' : s.connected,
    );
  }

  @override
  void dispose() {
    _stopPingTicker();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    final language = ref.watch(languageProvider);
    final textScale = ref.watch(personalizationProvider).textScale.scale;

    // Mirrors the connection state into a persistent system notification —
    // the floating status bar a VPN app is expected to keep visible in the
    // phone's notification shade while connected or connecting.
    ref.listen(connectionManagerProvider, (previous, next) {
      _updateNotification(next.status);
    });

    return MaterialApp.router(
      title: 'WAVEBREAK',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: _scaffoldMessengerKey,
      theme: WbTheme.dark,
      locale: Locale(language.name),
      supportedLocales: const [
        Locale('en'),
        Locale('ru'),
        Locale('es'),
        Locale('de'),
        Locale('fr'),
        Locale('pt'),
        Locale('tr'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      routerConfig: router,
      builder: (context, child) => MediaQuery.withClampedTextScaling(
        minScaleFactor: textScale,
        maxScaleFactor: textScale,
        child: AppLockGate(
          child: _OfflineBanner(child: child),
        ),
      ),
    );
  }
}

// Real product feedback this replaces the old full-time pill for: it used
// to camp permanently over the top of whatever screen was showing for as
// long as the offline/cached-data condition lasted, and (being pinned to
// the very top of the stack) could sit over screens' own tappable header
// controls. Split into the two things it was actually trying to do at
// once: a TRANSIENT notification for the moment the state changes (a
// dismissible SnackBar — the standard toast primitive, already supports
// swipe-to-dismiss and auto-hides on its own) and a small, permanent but
// unobtrusive ICON (not a banner, not text, doesn't intercept taps) for as
// long as the underlying condition is still true.
class _OfflineBanner extends ConsumerStatefulWidget {
  const _OfflineBanner({required this.child});

  final Widget? child;

  @override
  ConsumerState<_OfflineBanner> createState() => _OfflineBannerState();
}

class _OfflineBannerState extends ConsumerState<_OfflineBanner> {
  bool? _wasOffline;

  void _showToast(bool offline, bool deviceOffline) {
    final messenger = _scaffoldMessengerKey.currentState;
    if (messenger == null) return;
    final s = ref.read(stringsProvider);
    messenger.hideCurrentSnackBar();
    final text = offline
        ? (deviceOffline ? s.noInternetBanner : s.showingSavedDataBanner)
        : s.backOnlineBanner;
    messenger.showSnackBar(
      SnackBar(
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              offline
                  ? (deviceOffline
                      ? Icons.wifi_off_rounded
                      : Icons.cloud_off_rounded)
                  : Icons.wifi_rounded,
              color: WbColors.ice,
              size: 18,
            ),
            const SizedBox(width: 10),
            Flexible(child: Text(text)),
          ],
        ),
        backgroundColor: offline ? WbColors.warning : WbColors.deepOcean,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
        // Swipe-to-dismiss, on top of the automatic 4s auto-hide — either
        // one closes it, neither camps over the screen indefinitely.
        dismissDirection: DismissDirection.horizontal,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final deviceOffline = ref.watch(isOfflineProvider).asData?.value ?? false;
    // Device connectivity is only one way to end up looking at stale data —
    // the device can have a perfectly good signal while Core itself is
    // unreachable/erroring, in which case data_providers.dart's cache
    // fallback kicks in and flips this instead. Either one shows the same
    // indicator; the toast text just says which happened.
    final usingCache = ref.watch(usingCachedDataProvider);
    final offline = deviceOffline || usingCache;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_wasOffline != null && _wasOffline != offline) {
        _showToast(offline, deviceOffline);
      }
      _wasOffline = offline;
    });

    return Stack(
      children: [
        if (widget.child != null) widget.child!,
        // The small persistent indicator — a plain icon in a soft circular
        // chip, not a pill with text and not full-width, and wrapped in
        // IgnorePointer so it can never sit in front of a real tap target
        // the way the old full-time banner sometimes did.
        Positioned(
          top: 0,
          right: 0,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.only(top: 8, right: 12),
              child: IgnorePointer(
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 200),
                  opacity: offline ? 1 : 0,
                  child: Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: WbColors.warning.withValues(alpha: 0.18),
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: WbColors.warning.withValues(alpha: 0.4)),
                    ),
                    child: Icon(
                      deviceOffline
                          ? Icons.wifi_off_rounded
                          : Icons.cloud_off_rounded,
                      color: WbColors.warning,
                      size: 14,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
