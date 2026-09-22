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
    if (_usesNativeAndroidNotification) return;
    if (ref.read(connectionManagerProvider).status !=
        ConnectionStatus.connected) return;
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

class _OfflineBanner extends ConsumerWidget {
  const _OfflineBanner({required this.child});

  final Widget? child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final deviceOffline = ref.watch(isOfflineProvider).asData?.value ?? false;
    // Device connectivity is only one way to end up looking at stale data —
    // the device can have a perfectly good signal while Core itself is
    // unreachable/erroring, in which case data_providers.dart's cache
    // fallback kicks in and flips this instead. Either one shows the same
    // pill; the label just says which happened.
    final usingCache = ref.watch(usingCachedDataProvider);
    final offline = deviceOffline || usingCache;
    final bannerText =
        deviceOffline ? s.noInternetBanner : s.showingSavedDataBanner;
    return Stack(
      children: [
        if (child != null) child!,
        // A floating glass pill, not a flat bar — matches the rest of the
        // app's frosted-card language instead of a jarring solid strip
        // pasted across the very top of the screen. Pushed down past
        // every screen's own top row (Home's wordmark+toolbar chip,
        // every DetailScaffold screen's back-button+title row — both
        // land in roughly the same ~50-60px band below the safe area) —
        // this used to sit right at the top and visually overlap those,
        // including the toolbar chip's tappable refresh/restart buttons.
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            bottom: false,
            child: Align(
              alignment: Alignment.topCenter,
              child: AnimatedSlide(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                offset: offline ? Offset.zero : const Offset(0, -1.6),
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 200),
                  opacity: offline ? 1 : 0,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 68),
                    child: Material(
                      color: Colors.transparent,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: WbColors.warning.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                              color: WbColors.warning.withValues(alpha: 0.4)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.25),
                              blurRadius: 16,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                                deviceOffline
                                    ? Icons.wifi_off_rounded
                                    : Icons.cloud_off_rounded,
                                color: WbColors.warning,
                                size: 16),
                            const SizedBox(width: 8),
                            Text(
                              bannerText,
                              style: const TextStyle(
                                color: WbColors.warning,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
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
