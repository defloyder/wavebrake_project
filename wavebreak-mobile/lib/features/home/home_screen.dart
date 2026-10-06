import '../../core/theme/wb_theme.dart';
import 'dart:async';
import 'dart:math' as math;
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/session_controller.dart';
import '../../core/errors/app_exception.dart';
import '../../core/i18n/app_strings.dart';
import '../../core/i18n/language_controller.dart';
import '../../core/theme/flag_colors.dart';
import '../../core/theme/wb_colors.dart';
import '../../core/storage/prefs_store.dart';
import '../../services/core_api/models.dart';
import '../../services/custom_servers/custom_server_controller.dart';
import '../../services/custom_servers/custom_subscription.dart';
import '../../services/system/battery_optimization.dart';
import '../../services/update/apk_installer.dart';
import '../../services/vpn/connection_manager.dart';
import '../shared/add_custom_server_sheet.dart';
import '../shared/confirm_dialogs.dart';
import '../shared/connect_button.dart';
import '../shared/data_providers.dart';
import '../shared/traffic_wave_bar.dart';
import '../shared/traffic_format.dart';
import '../../services/vpn/server_catalog.dart';
import '../shared/menu_button.dart';
import '../shell/app_shell.dart';
import '../shared/ocean_background.dart';
import '../shared/subscription_accordion.dart';
import '../shared/subscription_texts.dart';
import '../shared/toast.dart';
import '../shared/wave_params.dart';
import '../shared/wb_card.dart';
import '../shared/wavebreak_mark.dart';
import '../immersive/immersive_colors.dart';
import '../immersive/living_core.dart';
import '../immersive/tinted_glass.dart';
import '../immersive/wave_field.dart';
import 'home_vitals.dart';
import 'location_bar.dart';
import '../locations/servers_sheet.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with WidgetsBindingObserver {
  Timer? _ticker;
  final _scrollController = ScrollController();

  // Closing a long, scrolled-into location list should smoothly bring the
  // gaze back up the page instead of leaving the view stranded on the
  // now-empty space the collapsed list used to fill.
  void _scrollToTop() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (ref.read(connectionManagerProvider).status ==
          ConnectionStatus.connected) {
        setState(() {});
      }
    });
    // The subscription/locations prefetch during sign-in can resolve the
    // provider before this screen ever mounts, in which case ref.listen
    // below never fires (it only reacts to *changes*) — so also hydrate
    // once against whatever is already cached.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final cached = ref.read(locationsProvider).valueOrNull;
      if (cached != null) {
        ref.read(connectionManagerProvider.notifier).hydrateLocations(cached);
      }
      // ConnectionManager.build() restores the *previously selected*
      // location from prefs on cold start using only its saved id — for a
      // real WAVEBREAK location that id is "cc-..." shaped so a country
      // code can be guessed straight from it, but a custom/BYO server's id
      // is a random uuid, so that guess produces garbage (a hash of the
      // uuid's first segment) until the real server — with its real
      // countryCode — loads from storage and gets hydrated in here. Custom
      // servers load synchronously from prefs in CustomServerController's
      // own build(), so this alone is enough to fix the one frame (or,
      // before this fix, indefinitely) where the wrong accent/flag showed.
      final customFlat =
          ref.read(customServersProvider).expand((g) => g.servers).toList();
      if (customFlat.isNotEmpty) {
        ref
            .read(connectionManagerProvider.notifier)
            .hydrateLocations(customFlat);
        // A guest who already added at least one server of their own has
        // nothing left to "add" — the sphere previously still opened on
        // the never-selected Auto placeholder, which _StatusCopy reads as
        // "no server chosen yet" and answers with an "add your own link"
        // prompt even though one is already sitting right there in the
        // location list. Point the selection at it instead, the same way
        // picking it from the list would.
        if (ref.read(connectionManagerProvider).location.isAuto) {
          ref
              .read(connectionManagerProvider.notifier)
              .selectLocation(customFlat.first);
        }
      }
      unawaited(
        ref.read(connectionManagerProvider.notifier).reconcileWithSystem(),
      );
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  // Real-device reliability gap this fixes: Doze/App Standby can defer
  // this app's own background work (health-check callbacks, holding a
  // live QUIC/UDP session through an extended deep-sleep window) even
  // with the VpnService foreground notification's partial exemption — a
  // real, documented contributor to the sleep/wake reconnect failures
  // this app has been fighting. Asked right after a successful connection
  // (the moment the user has just seen the feature work) rather than
  // during onboarding, and at most once a week while the app is still not
  // exempt; Settings > Connection offers it at any time.
  Future<void> _maybeOfferBatteryOptimizationExemption() async {
    if (!Platform.isAndroid) return;
    // Re-offered weekly while still not exempt (bug 1: the tunnel's
    // watchdog is only reliable in the background with the exemption).
    const reofferAfter = Duration(days: 7);
    final lastMs =
        PrefsStore.getInt(PrefsStore.batteryOptimizationPromptLastMs) ?? 0;
    if (DateTime.now().millisecondsSinceEpoch - lastMs <
        reofferAfter.inMilliseconds) {
      return;
    }
    const battery = BatteryOptimizationService();
    if (await battery.isExempt()) return;
    if (!mounted) return;
    await PrefsStore.setInt(PrefsStore.batteryOptimizationPromptLastMs,
        DateTime.now().millisecondsSinceEpoch);
    if (!mounted) return;
    final s = ref.read(stringsProvider);
    final allow = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: WbColors.card,
        title: Text(s.batteryOptPromptTitle),
        content: Text(s.batteryOptPromptBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(s.notNow),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(s.enable),
          ),
        ],
      ),
    );
    if (allow == true) {
      await battery.requestExemption();
    }
  }

  // Real-device bug this fixes: after the phone sits idle/screen-off for a
  // few minutes then wakes, Android's own status bar VPN key icon can show
  // the tunnel as active (it genuinely still is) while this screen keeps
  // showing "not connected" — sometimes for tens of seconds. Root cause is
  // Android freezing this app's own (Flutter/UI) process while cached in
  // the background; WaveEngineVpnService's broadcastState() call lives in
  // a separate, foreground-service-exempt process and fires normally, but
  // the ordinary dynamic BroadcastReceiver MainActivity registers for it
  // (see engineStatusChannelName's EventChannel) can sit queued, undelivered,
  // until this process actually unfreezes — by which point the real state
  // change it was reporting is stale news. reconcileWithSystem() already
  // exists for the equivalent cold-start version of this same problem (a
  // relaunch after the tunnel outlived a killed UI process) but was only
  // ever called once, from initState — recalling it here, on every real
  // resume, re-asks Android directly (isSystemVpnActive(), a live query,
  // not a broadcast that can be queued) rather than waiting on whatever
  // broadcast may or may not still be in flight.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      unawaited(
        ref.read(connectionManagerProvider.notifier).reconcileWithSystem(),
      );
      if (Platform.isAndroid) {
        // Check whether an update completed while the installer had focus.
        unawaited(ref
            .read(apkInstallControllerProvider.notifier)
            .checkPendingInstallCompleted());
      }
    }
  }

  Future<void> _removeCustomGroup(String id) async {
    final s = ref.read(stringsProvider);
    if (!await confirmRemoveCustomGroup(context, s)) return;
    // A deleted group's server(s) can still be the one the tunnel is
    // actively using — removeGroup() only drops it from the saved list,
    // it has no reach into ConnectionManager's live state, so without this
    // check the tunnel just kept running against a server the UI no
    // longer lists anywhere, with no way back to it short of a manual
    // disconnect. Checked and torn down BEFORE removing, since afterward
    // there'd be nothing left to look up which group the id belonged to.
    final connection = ref.read(connectionManagerProvider);
    final matches = ref.read(customServersProvider).where((g) => g.id == id);
    final group = matches.isEmpty ? null : matches.first;
    final connectedToThisGroup = group != null &&
        connection.status != ConnectionStatus.idle &&
        group.servers.any((server) => server.id == connection.location.id);
    ref.read(customServersProvider.notifier).removeGroup(id);
    if (connectedToThisGroup) {
      await ref.read(connectionManagerProvider.notifier).disconnect();
    }
  }

  bool _refreshing = false;

  /// Reloads the servers and the subscription — the refresh button and
  /// pull-down on Home. Taps while a reload is running are ignored; the
  /// message comes once it is done (and only for the button: the pull-down
  /// spinner already says it).
  Future<void> _refresh({bool toast = true}) async {
    if (_refreshing) return;
    _refreshing = true;
    final messenger = ScaffoldMessenger.of(context);
    final s = ref.read(stringsProvider);
    try {
      ref.invalidate(locationsProvider);
      ref.invalidate(subscriptionProvider);
      await Future.wait([
        ref.read(locationsProvider.future),
        ref.read(subscriptionProvider.future),
      ]).timeout(const Duration(seconds: 20));
    } catch (_) {
      // Errors show on the screen itself (offline icon, server list).
    } finally {
      _refreshing = false;
    }
    if (mounted && toast) showToast(messenger, s.serversUpdated);
  }

  Future<void> _restart() async {
    final s = ref.read(stringsProvider);
    final canConnect = ref.read(canConnectProvider);
    if (mounted) showToast(ScaffoldMessenger.of(context), s.restarting);
    await ref
        .read(connectionManagerProvider.notifier)
        .restart(subscriptionActive: canConnect);
  }

  @override
  Widget build(BuildContext context) {
    final connection = ref.watch(connectionManagerProvider);
    final subscription = ref.watch(subscriptionProvider);
    final locations = ref.watch(locationsProvider);
    final s = ref.watch(stringsProvider);
    // .select, not the whole SessionState — this screen only cares about
    // guest-vs-not, but sessionControllerProvider also changes on every
    // silent background token refresh (see data_providers.dart's own
    // .select for the identical reasoning). Watching the full object
    // rebuilt all of Home — including everything under OceanBackground —
    // on every one of those, not just an actual guest/account change.
    final isGuest = ref.watch(sessionControllerProvider
        .select((session) => session.phase == SessionPhase.guest));
    ref.listen(locationsProvider, (prev, next) {
      next.whenData(
        (items) => ref
            .read(connectionManagerProvider.notifier)
            .hydrateLocations(items),
      );
    });
    ref.listen(connectionManagerProvider, (prev, next) {
      if (prev?.status != ConnectionStatus.connected &&
          next.status == ConnectionStatus.connected) {
        unawaited(_maybeOfferBatteryOptimizationExemption());
      }
    });
    ref.listen(customServersProvider, (prev, next) {
      final flat = next.expand((g) => g.servers).toList();
      if (flat.isNotEmpty) {
        ref.read(connectionManagerProvider.notifier).hydrateLocations(flat);
      }
    });

    final canConnect = ref.watch(canConnectProvider);
    // A WAVEBREAK subscription is never required for the user's own
    // (custom/pasted) server — ConnectionManager.connect() already
    // bypasses that check for isCustom locations, so the UI gating a
    // "Choose a plan" wall in front of it would be a bug, not a feature.
    // This is also what makes guest mode (no account, no subscription at
    // all) actually usable for its one intended purpose.
    final effectiveCanConnect = canConnect || connection.location.isCustom;

    // Derived centrally (from the same connection/location state every
    // other screen reads too) so Home doesn't own or push this — it's
    // just one more consumer of the app-wide tint/wave mood.
    final waves = ref.watch(appWaveParamsProvider);
    final tint = waves.tint;

    final locationsSection = locations.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text(
          error is AppException ? error.localized(s) : s.errUnavailable,
          textAlign: TextAlign.center,
          style: const TextStyle(color: WbColors.ice60),
        ),
      ),
      // Wide windows only (the phone has the Servers tab): the same list,
      // from the same catalog.
      data: (_) {
        return SubscriptionAccordion(
          sections: ref.watch(serverCatalogProvider),
          current: connection.location,
          s: s,
          shrinkWrap: true,
          onSelect: (item) => ref
              .read(connectionManagerProvider.notifier)
              .selectLocation(item, subscriptionActive: canConnect),
          onAddCustom: () => showAddCustomServerSheet(context, ref),
          onRemove: (id) => _removeCustomGroup(id),
          onRefresh: (id) =>
              ref.read(customServersProvider.notifier).refreshGroup(id),
          onCollapse: _scrollToTop,
        );
      },
    );

    Widget buildTopBar(bool isDesktop) => SizedBox(
          height: 46,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Centered against the row's true midpoint, not balanced by
              // Spacers — the menu button and toolbar chip have different
              // widths, so equal Spacers would leave the wordmark off-center.
              // On a narrow phone (< 400) the centered wordmark ran under
              // the toolbar: it moves to the left edge there.
              Align(
                alignment: isDesktop || MediaQuery.sizeOf(context).width >= 400
                    ? Alignment.center
                    : Alignment.centerLeft,
                child: const WavebreakWordmarkText(size: 14),
              ),
              // Mobile has no side rail to expand — the menu button belongs
              // to desktop only.
              if (isDesktop)
                const Align(
                    alignment: Alignment.centerLeft, child: MenuButton()),
              Align(
                alignment: Alignment.centerRight,
                child: _ToolbarChip(
                  children: [
                    _SpinIconButton(
                      // A reload glyph reads as "refresh the server list" —
                      // kept distinct from the restart icon below rather than
                      // two near-identical circular-arrow shapes sitting side
                      // by side.
                      icon: Icons.refresh_rounded,
                      tooltip: s.refreshServers,
                      onTap: _refresh,
                    ),
                    Container(width: 1, height: 20, color: WbColors.ice08),
                    _SpinIconButton(
                      // A power glyph — visually unmistakable next to the
                      // refresh arrows, and reads clearly as "power-cycle the
                      // connection" rather than "reload some list".
                      icon: Icons.power_settings_new_rounded,
                      tooltip: s.restart,
                      onTap: connection.status == ConnectionStatus.connected ||
                              connection.status ==
                                  ConnectionStatus.configPending ||
                              connection.status == ConnectionStatus.error
                          ? () => _restart()
                          : null,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );

    // requestingProfile/connecting stay tappable so
    // ConnectionManager.toggle() can treat that tap as "cancel this
    // attempt" (see cancelConnect()) instead of it just sitting there
    // unresponsive for however long a slow grant/handshake takes.
    final connectEnabled = effectiveCanConnect ||
        connection.status == ConnectionStatus.connected ||
        connection.status == ConnectionStatus.configPending ||
        connection.status == ConnectionStatus.connecting ||
        connection.status == ConnectionStatus.requestingProfile ||
        connection.status == ConnectionStatus.disconnecting;
    void onConnectPressed() {
      ref
          .read(connectionManagerProvider.notifier)
          .toggle(subscriptionActive: canConnect);
    }

    final connectButton = ConnectButton(
      status: connection.status,
      enabled: connectEnabled,
      accentColors: connection.location.isAuto
          ? null
          : accentPairFor(connection.location.countryCode),
      onPressed: onConnectPressed,
    );

    // Phone (V5): the living sphere instead of the glass button. The ping /
    // download readouts sit beside it when the sphere keeps at least 180
    // across between them; on narrower phones they go in a row under it
    // (beside a full-size sphere they covered it and clipped).
    final screenWidth = MediaQuery.sizeOf(context).width;
    final betweenVitals = screenWidth - 40 - 2 * SideVital.width;
    final vitalsBeside = betweenVitals >= 180;
    final coreDiameter = vitalsBeside
        ? math.min(livingCoreDiameter(screenWidth), betweenVitals)
        : livingCoreDiameter(screenWidth);

    final statusCopy = _StatusCopy(
      connection: connection,
      canConnect: effectiveCanConnect,
      // True only while there's genuinely no subscription snapshot yet at
      // all (first-ever login on this device, nothing cached) — see
      // subscriptionProvider's own doc comment in data_providers.dart. A
      // returning user with a cached snapshot skips this entirely (the
      // provider yields the cache before this widget ever builds with
      // `isLoading`), so this only ever fires for that one genuine
      // first-run gap.
      subscriptionLoading: subscription.isLoading && !subscription.hasValue,
      isGuest: isGuest,
      onAddCustom: () => showAddCustomServerSheet(context, ref),
      s: s,
      tint: tint,
      onRetry: () {
        ref
            .read(connectionManagerProvider.notifier)
            .connect(subscriptionActive: canConnect);
      },
      onCancel: () {
        ref.read(connectionManagerProvider.notifier).disconnect();
      },
      onChoosePlan: () => context.push('/subscription'),
      // The protocol switch is right above the sphere: the hint points
      // there instead of a button of its own (one place to switch).
      hasOtherProtocol: connection.noTraffic &&
          ref.read(connectionManagerProvider.notifier).otherProtocol != null,
    );

    final subscriptionStrip = _SubscriptionStrip(
      asyncSub: subscription,
      s: s,
      tint: tint,
      isGuest: isGuest,
      onOpen: () => context.push('/subscription'),
      onSignIn: () async {
        await ref.read(sessionControllerProvider.notifier).exitGuestMode();
        if (context.mounted) context.go('/login');
      },
    );

    // The current place's protocols (Direct / Hysteria2 …) from the server
    // catalog — the Servers tab picks from the same entries. The row
    // itself opens the Servers tab (the one place to change location).
    final current = connection.location;
    final currentPlace = current.isAuto
        ? null
        : placeOf(current, ref.watch(serverCatalogProvider));
    final locationHeader = LocationBar(
      location: current,
      variants: currentPlace?.variants ?? const <LocationItem>[],
      s: s,
      onOpenServers: () => showServersSheet(context, ref),
      onSelect: (item) => ref
          .read(connectionManagerProvider.notifier)
          .selectLocation(item, subscriptionActive: canConnect),
    );

    // Own active subscription: it fits as one line at the bottom of the
    // session card. Anything that needs action (guest, expired, unpaid,
    // a shared subscription selected) keeps its own card under it.
    final sub = subscription.valueOrNull;
    final sharedSelected = ref.watch(customServersProvider).any((g) =>
        g.sharedWithMe && g.servers.any((v) => v.id == connection.location.id));
    final compactSubscription = !isGuest &&
        !sharedSelected &&
        sub != null &&
        sub.isActive &&
        !sub.isExpired &&
        !sub.isPastDue;

    // Phone layout, used under the wave field (see below). No scrolling
    // (owner, 06.10): the sphere takes whatever height the rest leaves,
    // up to its normal size. Very short screens (< 600 px of body) still
    // scroll rather than squeeze the sphere to nothing.
    Widget buildMobileBody() => LayoutBuilder(
          builder: (context, constraints) {
            final heroTopGap = (constraints.maxHeight * 0.03).clamp(8.0, 22.0);
            final height = math.max(constraints.maxHeight, 600.0);
            // Pull down to reload the servers and the subscription, like
            // the refresh button (owner, 06.10). Always scrollable, or a
            // screen whose content fits would never start the pull.
            return RefreshIndicator(
              onRefresh: () => _refresh(toast: false),
              color: Ic.text,
              backgroundColor: const Color(0xE6101418),
              // No rubber-band either way (owner, 06.10: the page moved on
              // every swipe): hard edges, no stretch effect. Pulling down
              // still reaches the refresh indicator (an overscroll).
              child: ScrollConfiguration(
                behavior:
                    ScrollConfiguration.of(context).copyWith(overscroll: false),
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(
                      parent: ClampingScrollPhysics()),
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: SizedBox(
                    height: height,
                    child: Column(
                      children: [
                        SizedBox(height: heroTopGap),
                        buildTopBar(false),
                        const SizedBox(height: 10),
                        locationHeader,
                        // Real ping / download beside the core (dashes until
                        // connected — never invented), laid over the
                        // sphere's wave stage. The empty middle lets taps
                        // through to the sphere.
                        Expanded(
                          child: LayoutBuilder(
                            builder: (context, box) {
                              final d =
                                  math.min(coreDiameter, box.maxHeight / 1.27);
                              return Center(
                                child: CoreStage(
                                  diameter: d,
                                  core: LivingCore(
                                    status: connection.status,
                                    enabled: connectEnabled,
                                    diameter: d,
                                    onPressed: onConnectPressed,
                                  ),
                                  overlay: vitalsBeside
                                      ? const CoreWithVitals(
                                          core: SizedBox.shrink())
                                      : null,
                                ),
                              );
                            },
                          ),
                        ),
                        if (!vitalsBeside) const VitalsRow(),
                        const SizedBox(height: 4),
                        statusCopy,
                        const SizedBox(height: 14),
                        SessionPanel(
                          footer: compactSubscription
                              ? _SubscriptionFooter(
                                  sub: sub,
                                  s: s,
                                  onOpen: () => context.push('/subscription'),
                                )
                              : null,
                        ),
                        if (!compactSubscription) ...[
                          const SizedBox(height: 12),
                          subscriptionStrip,
                        ],
                        // The bottom nav pill floats over the body.
                        const SizedBox(height: kMobileBottomBarReserve + 12),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );

    return LayoutBuilder(
      builder: (context, outer) {
        final isDesktop = outer.maxWidth >= 820;
        if (!isDesktop) {
          // Phone: the immersive (V5) look — full-screen wave field under
          // the content.
          return Stack(
            children: [
              Positioned.fill(
                child: WaveField(
                  tint: tint,
                  intensity: connection.status == ConnectionStatus.connected
                      ? 1
                      : 0.55,
                ),
              ),
              GlassGroup(child: SafeArea(child: buildMobileBody())),
            ],
          );
        }
        return OceanBackground(
          illuminate: true,
          tint: tint,
          waveSpeed: waves.speed,
          waveAmplitude: waves.amplitude,
          waveLineCount: 5,
          // On desktop the two columns center themselves independently
          // (below), so OceanBackground shouldn't also cap+center the
          // whole Row as one block — that stacked the columns' own
          // centering on top of a narrower, off-to-one-side block,
          // leaving the connect button visibly closer to the divider
          // than to the true center of its half of the screen.
          maxContentWidth: isDesktop ? double.infinity : 560,
          child: SafeArea(
            child: isDesktop
                ? Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 32, vertical: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        buildTopBar(true),
                        const SizedBox(height: 8),
                        Expanded(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                flex: 5,
                                // Top-aligned (not vertically centered) so
                                // this column's content starts at the same
                                // height as "Выбор локации" on the right —
                                // the two halves previously started at
                                // different Y positions, which read as
                                // misaligned even though each was correctly
                                // centered within its own half.
                                child: Align(
                                  alignment: Alignment.topCenter,
                                  child: Column(
                                    children: [
                                      const SizedBox(height: 4),
                                      locationHeader,
                                      const SizedBox(height: 40),
                                      connectButton,
                                      const SizedBox(height: 28),
                                      statusCopy,
                                      const SizedBox(height: 36),
                                      ConstrainedBox(
                                        constraints:
                                            const BoxConstraints(maxWidth: 360),
                                        child: subscriptionStrip,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(width: 1, color: WbColors.ice08),
                              const SizedBox(width: 32),
                              Expanded(
                                flex: 6,
                                child: Center(
                                  child: ConstrainedBox(
                                    constraints:
                                        const BoxConstraints(maxWidth: 640),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          s.chooseLocation,
                                          style: const TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.w600),
                                        ),
                                        const SizedBox(height: 12),
                                        Expanded(
                                          child: SingleChildScrollView(
                                            child: locationsSection,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  )
                : buildMobileBody(),
          ),
        );
      },
    );
  }
}

class _ToolbarChip extends StatelessWidget {
  const _ToolbarChip({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: WbColors.card.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: WbColors.ice08),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: children),
    );
  }
}

class _SpinIconButton extends StatefulWidget {
  const _SpinIconButton(
      {required this.icon, required this.tooltip, required this.onTap});

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  State<_SpinIconButton> createState() => _SpinIconButtonState();
}

class _SpinIconButtonState extends State<_SpinIconButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 500),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTap() {
    if (widget.onTap == null) return;
    _controller.forward(from: 0);
    widget.onTap!();
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap == null ? null : _handleTap,
          customBorder: const CircleBorder(),
          child: Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            child: RotationTransition(
              turns: _controller,
              child: Icon(
                widget.icon,
                size: 21,
                color: widget.onTap == null
                    ? WbColors.ice60.withValues(alpha: 0.35)
                    : WbColors.ice60,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusCopy extends StatelessWidget {
  const _StatusCopy({
    required this.connection,
    required this.canConnect,
    this.subscriptionLoading = false,
    required this.s,
    required this.onRetry,
    required this.onChoosePlan,
    required this.isGuest,
    required this.onAddCustom,
    required this.onCancel,
    this.hasOtherProtocol = false,
    this.tint,
  });

  final WbConnectionState connection;

  /// Set while the connection passes no traffic and another protocol of
  /// the same country is left to try; null otherwise.
  final bool hasOtherProtocol;
  final bool canConnect;
  final bool subscriptionLoading;
  final AppStrings s;
  final VoidCallback onRetry;
  final VoidCallback onChoosePlan;
  final bool isGuest;
  final VoidCallback onAddCustom;
  final VoidCallback onCancel;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    if (!canConnect &&
        connection.status != ConnectionStatus.connected &&
        connection.status != ConnectionStatus.configPending) {
      // We genuinely don't know yet whether this account has an active
      // plan (first-ever login, nothing cached) — showing the "Subscribe"
      // wall here would be asserting a fact we haven't actually checked.
      // A neutral skeleton until the real answer lands is what the wall
      // itself should never have been standing in for.
      if (subscriptionLoading) {
        return const _ConnectWallSkeleton();
      }
      // A guest has no subscription to sell — the equivalent "nothing to
      // connect to yet" prompt is adding their own server, not a plan
      // wall they have no way (and no reason) to get past.
      if (isGuest) {
        return Column(
          children: [
            Text(
              s.addSubscriptionLink,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: onAddCustom,
              style: FilledButton.styleFrom(
                backgroundColor: context.accent,
                foregroundColor: WbColors.midnight,
              ),
              child: Text(s.addSubscription),
            ),
          ],
        );
      }
      return Column(
        children: [
          Text(
            s.subscriptionRequiredTitle,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: onChoosePlan,
            style: FilledButton.styleFrom(
              backgroundColor: context.accent,
              foregroundColor: WbColors.midnight,
            ),
            child: Text(s.choosePlan),
          ),
        ],
      );
    }

    final noTraffic = connection.noTraffic;
    final title = switch (connection.status) {
      ConnectionStatus.idle => s.statusReady,
      ConnectionStatus.requestingProfile ||
      ConnectionStatus.connecting =>
        s.statusOnWave,
      ConnectionStatus.connected when noTraffic => s.noTraffic,
      ConnectionStatus.connected => s.statusProtected,
      ConnectionStatus.configPending => s.configPending,
      ConnectionStatus.disconnecting => s.disconnecting,
      ConnectionStatus.error => s.statusFailed,
    };
    final subtitle = switch (connection.status) {
      ConnectionStatus.idle => s.statusReadyHint,
      ConnectionStatus.connected when noTraffic =>
        hasOtherProtocol ? s.noTrafficHint : s.noTrafficAllTried,
      ConnectionStatus.connected => _duration(connection.connectedAt, s),
      ConnectionStatus.configPending => s.configPendingHint,
      ConnectionStatus.error => connection.error?.localized(s) ?? s.tryAgain,
      _ => '',
    };

    // V5: ordinary states need no headline — the protection row under the
    // core already says "Not protected / Connecting… / Protection active"
    // with the session timer. Only states that ask the user to do
    // something keep their text (error + retry, no traffic, config
    // pending; the no-subscription walls returned above).
    final quiet = switch (connection.status) {
      ConnectionStatus.idle ||
      ConnectionStatus.requestingProfile ||
      ConnectionStatus.connecting ||
      ConnectionStatus.disconnecting =>
        true,
      ConnectionStatus.connected => !noTraffic,
      _ => false,
    };
    if (quiet) return const SizedBox.shrink();

    final titleColor = noTraffic
        ? WbColors.warning
        : connection.status == ConnectionStatus.connected && tint != null
            ? Color.lerp(Colors.white, tint, 0.16)
            : null;

    // An error message can run noticeably longer than the one-word status
    // copy every other state shows here — cap how wide this column ever
    // gets so long text wraps centered instead of stretching edge to edge
    // and reading as left-aligned once it no longer fits one line.
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 340),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: Text(
              title,
              key: ValueKey(title),
              textAlign: TextAlign.center,
              // System serif (V5: "emotional headings Georgia / serif"). Not
              // Fraunces: it has no Cyrillic, so Russian fell back to sans.
              style: TextStyle(
                fontFamily: Ic.fontSerif,
                fontSize: 30,
                fontWeight: FontWeight.w400,
                color: titleColor ?? WbColors.ice,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            // A non-breaking space keeps the line while connecting, so the
            // content below doesn't jump up and back down.
            subtitle.isEmpty ? ' ' : subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(color: WbColors.ice60, fontSize: 14),
          ),
          if (connection.status == ConnectionStatus.error)
            TextButton(
              onPressed: onRetry,
              child: Text(s.tryAgain),
            ),
          if (connection.status == ConnectionStatus.configPending)
            TextButton(
              onPressed: onCancel,
              child:
                  Text(s.cancel, style: const TextStyle(color: WbColors.ice60)),
            ),
          // Bug 5: no ping test under the connect button any more — latency
          // is shown in the notification, the speed test and the list.
        ],
      ),
    );
  }

  String _duration(DateTime? started, AppStrings s) {
    if (started == null) return s.protected;
    final elapsed = DateTime.now().difference(started);
    final hours = elapsed.inHours.toString().padLeft(2, '0');
    final minutes = elapsed.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = elapsed.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }
}

/// Placeholder for the connect wall while [subscriptionProvider] hasn't
/// resolved even a cached snapshot yet — a real first-ever login, not the
/// common "reopening the app" case (which now renders instantly off the
/// cache, see that provider's own doc comment). Same title/subtitle/
/// button silhouette as the actual wall it stands in for, so nothing
/// visibly reflows the instant real data replaces it — just shimmering
/// placeholder blocks instead of committing to an answer ("you have no
/// plan") the app hasn't actually gotten from Core yet.
class _ConnectWallSkeleton extends StatefulWidget {
  const _ConnectWallSkeleton();

  @override
  State<_ConnectWallSkeleton> createState() => _ConnectWallSkeletonState();
}

class _ConnectWallSkeletonState extends State<_ConnectWallSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _block({required double width, required double height}) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final alpha = 0.05 + _controller.value * 0.06;
        return Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: WbColors.ice.withValues(alpha: alpha),
            borderRadius: BorderRadius.circular(height / 2),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _block(width: 220, height: 26),
        const SizedBox(height: 10),
        _block(width: 150, height: 15),
        const SizedBox(height: 18),
        _block(width: 168, height: 44),
      ],
    );
  }
}

/// Small entry point into the full [SpeedTestScreen] — styled like
/// a small pill; this is nav-only; the actual test
/// (with its live animated gauge) runs on its own dedicated page rather
/// than inline here. Shows the last result once one exists so glancing
class _SubscriptionStrip extends ConsumerWidget {
  const _SubscriptionStrip({
    required this.asyncSub,
    required this.s,
    required this.onOpen,
    required this.isGuest,
    required this.onSignIn,
    this.tint,
  });

  final AsyncValue<SubscriptionInfo> asyncSub;
  final AppStrings s;
  final VoidCallback onOpen;
  final bool isGuest;
  final VoidCallback onSignIn;
  final Color? tint;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (isGuest) {
      return WbCard(
        onTap: onSignIn,
        tint: tint,
        child: _StripHeader(
          icon: Icons.person_outline_rounded,
          iconColor: WbColors.ice,
          title: s.signIn,
          subtitle: s.signInToUnlock,
        ),
      );
    }
    // A location of a subscription someone shared with us is selected:
    // show that subscription (the owner's days and traffic), not ours.
    final locationId =
        ref.watch(connectionManagerProvider.select((c) => c.location.id));
    CustomSubscriptionGroup? sharedGroup;
    for (final g in ref.watch(customServersProvider)) {
      if (g.sharedWithMe &&
          g.servers.any((server) => server.id == locationId)) {
        sharedGroup = g;
        break;
      }
    }
    if (sharedGroup != null) {
      final received = ref
          .watch(sharingProvider)
          .valueOrNull
          ?.receivedFor(sharedGroup.sourceLink);
      return WbCard(
        tint: tint,
        child: _SharedSubscriptionStrip(
            title: sharedGroup.name, received: received, s: s),
      );
    }
    return WbCard(
      onTap: onOpen,
      tint: tint,
      child: asyncSub.when(
        // A re-read keeps the shown subscription (no one-line "loading"
        // flash that made the screen jump).
        skipLoadingOnReload: true,
        loading: () => Text(
          s.subscription,
          style: const TextStyle(color: WbColors.ice60),
        ),
        error: (error, _) => Text(
          error is AppException ? error.localized(s) : s.errUnavailable,
          style: const TextStyle(color: WbColors.ice60, fontSize: 13),
        ),
        data: (sub) {
          if (sub.isPastDue) {
            return _StripHeader(
              icon: Icons.error_outline_rounded,
              iconColor: WbColors.warning,
              title: s.subscriptionPastDueTitle,
              subtitle: '${renewBeforeLine(sub, s)}\n${s.renewResetNote}',
              subtitleColor: WbColors.warning,
            );
          }
          if (sub.isExpired || !sub.isActive) {
            return _StripHeader(
              icon: Icons.workspace_premium_outlined,
              iconColor: WbColors.warning,
              title: s.subscriptionExpiredTitle,
              subtitle: s.chooseAPlanToConnect,
            );
          }
          final days = sub.daysRemaining;
          // valueOrNull, not asData: while usage is re-read (every connect
          // or location switch) the last value stays instead of the bar
          // vanishing for a moment and the screen jumping.
          final usage = ref.watch(trafficUsageProvider).valueOrNull;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _StripHeader(
                icon: Icons.workspace_premium_outlined,
                iconColor: WbColors.oceanTeal,
                title: s.subscriptionActive,
                subtitle: days == null
                    ? sub.planName
                    : '${sub.planName} · $days ${s.daysRemaining}',
              ),
              if (usage != null) ...[
                const SizedBox(height: 12),
                TrafficWaveBar(
                  usedBytes: usage.bytesTotal,
                  limitBytes: usage.limitBytes ?? sub.trafficLimitBytes,
                  s: s,
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// The subscription section's head on Home: a neutral icon tile (the
/// state in its color), title, one muted line, a chevron to the plan.
class _StripHeader extends StatelessWidget {
  const _StripHeader({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    this.subtitleColor = WbColors.ice60,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final Color subtitleColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: WbColors.ice08,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 20, color: iconColor),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style:
                    const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style:
                    TextStyle(color: subtitleColor, fontSize: 13, height: 1.3),
              ),
            ],
          ),
        ),
        const Icon(Icons.chevron_right_rounded, color: WbColors.ice60),
      ],
    );
  }
}

/// Home's strip for a subscription shared with us: its owner's plan, days
/// and traffic (everyone sharing it uses the same traffic).
class _SharedSubscriptionStrip extends StatelessWidget {
  const _SharedSubscriptionStrip(
      {required this.title, required this.received, required this.s});

  final String title;
  final SharedSubscription? received;
  final AppStrings s;

  @override
  Widget build(BuildContext context) {
    final sub = received;
    final active = sub != null && sub.isActive;
    final days = sub?.daysRemaining;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          active ? s.subscriptionActive : title,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Text(
          sub == null
              ? s.sharedAccessTitle
              : !active
                  ? s.shareOwnerInactive
                  : days == null
                      ? title
                      : '$days ${s.daysRemaining} · $title',
          style: TextStyle(
            color: sub != null && !active ? WbColors.warning : WbColors.ice60,
            fontSize: 13,
          ),
        ),
        if (active) ...[
          const SizedBox(height: 10),
          TrafficWaveBar(
            usedBytes: sub.trafficUsedBytes,
            limitBytes: sub.trafficLimitBytes,
            s: s,
          ),
        ],
      ],
    );
  }
}

/// The own active subscription as the last line of Home's session card
/// (owner, 06.10: one card instead of three, no scrolling): plan, days
/// left, traffic. A limited plan gets a thin bar; close to the limit
/// (80 %+) the bar becomes the water-with-waves one, impossible to miss.
class _SubscriptionFooter extends ConsumerWidget {
  const _SubscriptionFooter({
    required this.sub,
    required this.s,
    required this.onOpen,
  });

  final SubscriptionInfo sub;
  final AppStrings s;
  final VoidCallback onOpen;

  static const _nearLimit = 0.8;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usage = ref.watch(trafficUsageProvider).valueOrNull;
    final days = sub.daysRemaining;
    final used = usage?.bytesTotal;
    final limit = usage?.limitBytes ?? sub.trafficLimitBytes;
    final fraction = used == null || limit == null || limit <= 0
        ? null
        : (used / limit).clamp(0.0, 1.0);
    final nearLimit = fraction != null && fraction >= _nearLimit;
    const muted = TextStyle(color: WbColors.ice60, fontSize: 12.5);
    return InkWell(
      onTap: onOpen,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.workspace_premium_outlined,
                    size: 16, color: WbColors.oceanTeal),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    days == null
                        ? sub.planName
                        : '${sub.planName} · $days ${s.daysRemaining}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: muted,
                  ),
                ),
                if (used != null && !nearLimit) ...[
                  const SizedBox(width: 8),
                  Text(formatTraffic(used, limit, s),
                      style: muted.copyWith(
                          fontFeatures: const [FontFeature.tabularFigures()])),
                ],
                const Icon(Icons.chevron_right_rounded,
                    size: 18, color: WbColors.ice60),
              ],
            ),
            if (nearLimit) ...[
              const SizedBox(height: 8),
              TrafficWaveBar(usedBytes: used!, limitBytes: limit, s: s),
            ] else if (fraction != null) ...[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: fraction,
                  minHeight: 4,
                  backgroundColor: WbColors.ice08,
                  color: context.accent,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
