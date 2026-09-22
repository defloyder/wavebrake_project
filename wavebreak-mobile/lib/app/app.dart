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
import '../services/update/apk_installer.dart';
import '../services/update/update_service.dart';
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
          child: _UpdateBanner(child: _OfflineBanner(child: child)),
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
        // pasted across the very top of the screen.
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
                    padding: const EdgeInsets.only(top: 10),
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

/// A bottom-anchored pill offering to download+install a newer build —
/// see services/update/update_service.dart's doc comment for why this
/// checks a static JSON file rather than a Core endpoint. Android-only:
/// this app ships outside the Play Store, so there's no other in-app path
/// to a new build without this. Sits below [_OfflineBanner] in the
/// widget tree (wraps it) so both can be visible at once without
/// overlapping — this one is bottom-anchored, that one top-anchored.
class _UpdateBanner extends ConsumerWidget {
  const _UpdateBanner({required this.child});

  final Widget? child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!Platform.isAndroid) return child ?? const SizedBox.shrink();
    final s = ref.watch(stringsProvider);
    final update = ref.watch(availableUpdateProvider).asData?.value;
    final install = ref.watch(apkInstallControllerProvider);
    final visible =
        update != null && install.status != ApkInstallStatus.readyToInstall;

    return Stack(
      children: [
        if (child != null) child!,
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: SafeArea(
            top: false,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: AnimatedSlide(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                offset: visible ? Offset.zero : const Offset(0, 1.6),
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 200),
                  opacity: visible ? 1 : 0,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Material(
                      color: Colors.transparent,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: WbColors.card,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                              color: WbColors.waveCyan.withValues(alpha: 0.35)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.3),
                              blurRadius: 18,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.system_update_rounded,
                                color: WbColors.waveCyan, size: 16),
                            const SizedBox(width: 8),
                            Text(
                              install.status == ApkInstallStatus.downloading
                                  ? '${s.updateDownloading} ${(install.progress * 100).round()}%'
                                  : install.status ==
                                          ApkInstallStatus.needsPermission
                                      ? s.updateAllowInstalls
                                      : s.updateAvailable,
                              style: const TextStyle(
                                color: WbColors.ice,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (install.status !=
                                ApkInstallStatus.downloading) ...[
                              const SizedBox(width: 10),
                              GestureDetector(
                                onTap: () {
                                  final notifier = ref.read(
                                      apkInstallControllerProvider.notifier);
                                  if (install.status ==
                                      ApkInstallStatus.needsPermission) {
                                    // Already downloaded — this re-checks
                                    // permission fresh (in case the user
                                    // already granted it on a previous
                                    // tap's trip to Settings) and installs
                                    // straight away rather than
                                    // re-downloading, or opens Settings
                                    // again if it's still not granted.
                                    notifier.retryInstallOrOpenSettings();
                                  } else if (update != null) {
                                    notifier.downloadAndInstall(update);
                                  }
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: WbColors.waveCyan,
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    s.updateInstall,
                                    style: const TextStyle(
                                      color: WbColors.midnight,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                            ],
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
