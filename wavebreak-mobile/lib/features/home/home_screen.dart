import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/auth/session_controller.dart';
import '../../core/errors/app_exception.dart';
import '../../core/i18n/app_strings.dart';
import '../../core/i18n/language_controller.dart';
import '../../core/theme/flag_colors.dart';
import '../../core/theme/wb_colors.dart';
import '../../services/core_api/models.dart';
import '../../services/custom_servers/custom_server_controller.dart';
import '../../services/vpn/connection_manager.dart';
import '../../services/vpn/connection_test_service.dart';
import '../shared/add_custom_server_sheet.dart';
import '../shared/confirm_dialogs.dart';
import '../shared/connect_button.dart';
import '../shared/data_providers.dart';
import '../shared/traffic_wave_bar.dart';
import '../shared/location_dropdown.dart';
import '../shared/menu_button.dart';
import '../shell/app_shell.dart';
import '../shared/ocean_background.dart';
import '../shared/flag_icon.dart';
import '../shared/share_subscription_sheet.dart';
import '../shared/subscription_accordion.dart';
import '../shared/subscription_section.dart';
import '../shared/update_available_sheet.dart';
import '../shared/wave_params.dart';
import '../shared/wb_card.dart';
import '../shared/wavebreak_mark.dart';
import '../../services/update/update_service.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with WidgetsBindingObserver {
  Timer? _ticker;
  final _locationLink = LayerLink();
  final _scrollController = ScrollController();
  bool _dropdownOpen = false;
  int? _lastPingMs;
  bool _pingTesting = false;

  Future<void> _testPing() async {
    if (_pingTesting) return;
    setState(() => _pingTesting = true);
    final connection = ref.read(connectionManagerProvider);
    // Always the same TCP-connect-and-time probe against the selected
    // server's own address (ConnectionTestService — also what the
    // location picker's per-row ping uses), whether or not the tunnel is
    // currently up. A previous version used a hardcoded 1.1.1.1:443 check
    // while connected instead — confirmed on-device that came back as an
    // implausible ~2ms almost every time, far too fast for a real
    // internet round trip even over a fast connection, most likely
    // because Android's VPN stack special-cases traffic to the tunnel's
    // own configured DNS server address rather than actually forwarding
    // it through tun2socks like ordinary traffic. Testing the real node's
    // own host:port instead has no such special case and — as a bonus —
    // now reads the same number the location list shows for consistency.
    final result =
        await const ConnectionTestService().testLocation(connection.location);
    if (!mounted) return;
    setState(() {
      _pingTesting = false;
      _lastPingMs = result;
    });
    if (result == null && mounted) {
      final s = ref.read(stringsProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.pingUnavailable)),
      );
    }
  }

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
      final cached = ref.read(locationsProvider).asData?.value;
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
    }
  }

  Future<void> _openLocationPicker(List<LocationItem> locations) async {
    if (_dropdownOpen) return;
    setState(() => _dropdownOpen = true);
    final current = ref.read(connectionManagerProvider).location;
    final custom = ref.read(customServersProvider);
    final s = ref.read(stringsProvider);
    final sections = buildSubscriptionSections(
      wavebreakLocations: locations,
      customGroups: custom,
      s: s,
      wavebreakShareUrl: ref.read(sessionControllerProvider).config.websiteUrl,
    );
    if (!mounted) return;
    final isDesktop = MediaQuery.sizeOf(context).width >= 820;
    final result = isDesktop
        ? await showLocationDropdown(
            // ignore: use_build_context_synchronously
            context: context,
            link: _locationLink,
            sections: sections,
            current: current,
            s: s,
            onRemoveCustom: (id) => _removeCustomGroup(id),
            onRefreshCustom: (id) =>
                ref.read(customServersProvider.notifier).refreshGroup(id),
          )
        : await showLocationSheet(
            // ignore: use_build_context_synchronously
            context: context,
            sections: sections,
            current: current,
            s: s,
            onRemoveCustom: (id) => _removeCustomGroup(id),
            onRefreshCustom: (id) =>
                ref.read(customServersProvider.notifier).refreshGroup(id),
          );
    if (mounted) setState(() => _dropdownOpen = false);
    if (result == null) return;
    if (result.addCustom) {
      if (mounted) await showAddCustomServerSheet(context, ref);
      return;
    }
    if (result.shareLink != null) {
      if (mounted) {
        await showShareSubscriptionSheet(
          context,
          title: result.shareTitle ?? '',
          link: result.shareLink!,
          s: s,
        );
      }
      return;
    }
    if (result.selected != null) {
      final canConnect = ref.read(canConnectProvider);
      ref
          .read(connectionManagerProvider.notifier)
          .selectLocation(result.selected!, subscriptionActive: canConnect);
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

  Future<void> _refresh() async {
    ref.invalidate(locationsProvider);
    ref.invalidate(subscriptionProvider);
    final s = ref.read(stringsProvider);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(s.serversUpdated),
            duration: const Duration(seconds: 2)),
      );
    }
  }

  Future<void> _restart() async {
    final s = ref.read(stringsProvider);
    final canConnect = ref.read(canConnectProvider);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(s.restarting), duration: const Duration(seconds: 2)),
      );
    }
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
      data: (items) {
        final sections = buildSubscriptionSections(
          wavebreakLocations: items,
          customGroups: ref.watch(customServersProvider),
          s: s,
          wavebreakShareUrl: ref.watch(sessionControllerProvider
              .select((session) => session.config.websiteUrl)),
        );
        return SubscriptionAccordion(
          sections: sections,
          currentId: connection.location.id,
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

    // Android only — this app ships outside the Play Store, so this is
    // the only in-app path to a new build (see update_service.dart's own
    // doc comment). The bell only appears at all once there's something
    // to say — no permanent fixture taking up toolbar space the rest of
    // the time, unlike the old always-present bottom pill this replaces.
    final pendingUpdate = Platform.isAndroid
        ? ref.watch(availableUpdateProvider).asData?.value
        : null;

    Widget buildTopBar(bool isDesktop) => SizedBox(
          height: 46,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Centered against the row's true midpoint, not balanced by
              // Spacers — the menu button and toolbar chip have different
              // widths, so equal Spacers would leave the wordmark off-center.
              const Center(child: WavebreakWordmarkText(size: 14)),
              // Mobile has no side rail to expand — the menu button belongs
              // to desktop only.
              if (isDesktop)
                const Align(
                    alignment: Alignment.centerLeft, child: MenuButton()),
              Align(
                alignment: Alignment.centerRight,
                child: _ToolbarChip(
                  children: [
                    if (pendingUpdate != null) ...[
                      _UpdateBellButton(
                        tooltip: s.updateAvailable,
                        onTap: () => showUpdateAvailableSheet(
                            context, ref, pendingUpdate),
                      ),
                      Container(width: 1, height: 20, color: WbColors.ice08),
                    ],
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

    final connectButton = ConnectButton(
      status: connection.status,
      // requestingProfile/connecting stay tappable so
      // ConnectionManager.toggle() can treat that tap as "cancel this
      // attempt" (see cancelConnect()) instead of it just sitting there
      // unresponsive for however long a slow grant/handshake takes.
      enabled: effectiveCanConnect ||
          connection.status == ConnectionStatus.connected ||
          connection.status == ConnectionStatus.configPending ||
          connection.status == ConnectionStatus.connecting ||
          connection.status == ConnectionStatus.requestingProfile ||
          connection.status == ConnectionStatus.disconnecting,
      accentColors: connection.location.isAuto
          ? null
          : accentPairFor(connection.location.countryCode),
      onPressed: () {
        ref
            .read(connectionManagerProvider.notifier)
            .toggle(subscriptionActive: canConnect);
      },
    );

    final statusCopy = _StatusCopy(
      connection: connection,
      canConnect: effectiveCanConnect,
      isGuest: isGuest,
      onAddCustom: () => showAddCustomServerSheet(context, ref),
      s: s,
      tint: tint,
      pingMs: _lastPingMs,
      pingTesting: _pingTesting,
      onTestPing: _testPing,
      onRetry: () {
        ref
            .read(connectionManagerProvider.notifier)
            .connect(subscriptionActive: canConnect);
      },
      onCancel: () {
        ref.read(connectionManagerProvider.notifier).disconnect();
      },
      onChoosePlan: () => context.push('/subscription'),
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

    final locationHeader = CompositedTransformTarget(
      link: _locationLink,
      child: _LocationHeader(
        location: connection.location,
        s: s,
        open: _dropdownOpen,
        onTap: () => locations.whenData(_openLocationPicker),
        tint: tint,
      ),
    );

    return LayoutBuilder(
      builder: (context, outer) {
        final isDesktop = outer.maxWidth >= 820;
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
                : LayoutBuilder(
                    builder: (context, constraints) {
                      // A comfortable fixed rhythm for the hero section — no
                      // Spacer games tied to viewport height, so it looks the
                      // same whether the screen is short or tall.
                      final heroTopGap =
                          (constraints.maxHeight * 0.04).clamp(8.0, 28.0);
                      final aboveButtonGap =
                          (constraints.maxHeight * 0.06).clamp(20.0, 56.0);
                      return SingleChildScrollView(
                        controller: _scrollController,
                        // The bottom nav pill now floats over the body
                        // instead of reserving its own Scaffold slot, so
                        // this has to leave room for it manually or the
                        // last row of locations ends up underneath it.
                        padding: const EdgeInsets.fromLTRB(
                          20,
                          0,
                          20,
                          kMobileBottomBarReserve + 12,
                        ),
                        child: Column(
                          children: [
                            SizedBox(height: heroTopGap),
                            buildTopBar(false),
                            SizedBox(height: aboveButtonGap * 0.5),
                            locationHeader,
                            SizedBox(height: aboveButtonGap),
                            connectButton,
                            const SizedBox(height: 24),
                            statusCopy,
                            SizedBox(height: aboveButtonGap),
                            subscriptionStrip,
                            const SizedBox(height: 28),
                            const Divider(color: WbColors.ice08, height: 1),
                            const SizedBox(height: 20),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                s.chooseLocation,
                                style: const TextStyle(
                                    fontSize: 18, fontWeight: FontWeight.w600),
                              ),
                            ),
                            const SizedBox(height: 12),
                            locationsSection,
                          ],
                        ),
                      );
                    },
                  ),
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

/// A bell-with-badge, not just another plain icon button in the toolbar
/// chip — that dot is the whole point: a persistent, glanceable "there's
/// an update" signal that survives tapping it and closing the detail
/// sheet again, unlike the old bottom pill which WAS the notification and
/// disappeared once installed/dismissed with nowhere else to find it
/// again (see update_available_sheet.dart's own comment, and About's
/// matching badge on its "check for updates" row).
class _UpdateBellButton extends StatelessWidget {
  const _UpdateBellButton({required this.tooltip, required this.onTap});

  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: 44,
            height: 44,
            child: Stack(
              alignment: Alignment.center,
              children: [
                const Icon(Icons.notifications_rounded,
                    size: 21, color: WbColors.waveCyan),
                Positioned(
                  top: 10,
                  right: 11,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: WbColors.waveCyan,
                      shape: BoxShape.circle,
                      border: Border.all(color: WbColors.card, width: 1.5),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
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

class _LocationHeader extends StatelessWidget {
  const _LocationHeader({
    required this.location,
    required this.s,
    required this.open,
    required this.onTap,
    this.tint,
  });

  final LocationItem location;
  final AppStrings s;
  final bool open;
  final VoidCallback onTap;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Text(
              location.isAuto ? s.auto : location.country.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 15,
                letterSpacing: 3,
                color: WbColors.ice60,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(height: 6),
          // Custom/BYO server names can run long — the raw share-link
          // label, or a city with a protocol note appended to disambiguate
          // it from another variant of the same location (see
          // custom_server_controller.dart's _splitCountryCity). Row used
          // to size to its unconstrained content and simply run off the
          // edge of the screen for those; it's now bounded to the
          // available width with the name itself eliding instead.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (!location.isAuto) ...[
                  FlagIcon(countryCode: location.countryCode, width: 26),
                  const SizedBox(width: 8),
                ],
                Flexible(
                  child: Text(
                    location.isAuto
                        ? s.fastestLocation
                        : (location.city.isEmpty
                            ? location.country
                            : location.city),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                AnimatedRotation(
                  turns: open ? 0.5 : 0,
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  child: Icon(
                    Icons.expand_more,
                    color: tint == null
                        ? WbColors.ice60
                        : Color.lerp(WbColors.ice60, tint, 0.5),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusCopy extends StatelessWidget {
  const _StatusCopy({
    required this.connection,
    required this.canConnect,
    required this.s,
    required this.onRetry,
    required this.onChoosePlan,
    required this.onTestPing,
    required this.isGuest,
    required this.onAddCustom,
    required this.onCancel,
    this.pingMs,
    this.pingTesting = false,
    this.tint,
  });

  final WbConnectionState connection;
  final bool canConnect;
  final AppStrings s;
  final VoidCallback onRetry;
  final VoidCallback onChoosePlan;
  final VoidCallback onTestPing;
  final bool isGuest;
  final VoidCallback onAddCustom;
  final VoidCallback onCancel;
  final int? pingMs;
  final bool pingTesting;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    if (!canConnect &&
        connection.status != ConnectionStatus.connected &&
        connection.status != ConnectionStatus.configPending) {
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
                backgroundColor: WbColors.waveCyan,
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
              backgroundColor: WbColors.waveCyan,
              foregroundColor: WbColors.midnight,
            ),
            child: Text(s.choosePlan),
          ),
        ],
      );
    }

    final title = switch (connection.status) {
      ConnectionStatus.idle => s.notConnected,
      ConnectionStatus.requestingProfile ||
      ConnectionStatus.connecting =>
        s.connecting,
      ConnectionStatus.connected => s.connected,
      ConnectionStatus.configPending => s.configPending,
      ConnectionStatus.disconnecting => s.disconnecting,
      ConnectionStatus.error => s.couldNotConnect,
    };
    final subtitle = switch (connection.status) {
      ConnectionStatus.idle => s.tapToConnect,
      ConnectionStatus.connected => _duration(connection.connectedAt, s),
      ConnectionStatus.configPending => s.configPendingHint,
      ConnectionStatus.error => connection.error?.localized(s) ?? s.tryAgain,
      _ => '',
    };

    final titleColor =
        connection.status == ConnectionStatus.connected && tint != null
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
              // Fraunces — the same serif wavebreak-web uses for its own
              // large headlines (site-section h2, hero copy — see
              // wavebreak-site.css's --font/h1/h2 rules). Kept at this
              // screen's existing mobile-tuned 28px rather than the
              // site's 52-70px display scale — the point is matching the
              // font family/character, not transplanting a desktop type
              // scale onto a phone. Loaded via google_fonts (already a
              // dependency, already used for Inter below) rather than
              // bundling the site's own woff2 files — same OFL-licensed
              // typeface, no separate asset registration or web-font-
              // format risk.
              style: GoogleFonts.fraunces(
                fontSize: 28,
                fontWeight: FontWeight.w500,
                color: titleColor ?? WbColors.ice,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
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
          if (!connection.isBusy &&
              (connection.status == ConnectionStatus.connected ||
                  connection.location.connectionTest != null)) ...[
            const SizedBox(height: 4),
            _PingRow(
              pingMs: pingMs,
              testing: pingTesting,
              onTest: onTestPing,
              s: s,
            ),
          ],
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

/// A small, explicit "test my connection" control — replaces the old
/// silent, sometimes-there-sometimes-not ping number (real backends don't
/// give per-location latency at all) with an honest on-demand measurement
/// through whatever tunnel is actually up right now.
class _PingRow extends StatelessWidget {
  const _PingRow({
    required this.pingMs,
    required this.testing,
    required this.onTest,
    required this.s,
  });

  final int? pingMs;
  final bool testing;
  final VoidCallback onTest;
  final AppStrings s;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: testing ? null : onTest,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (testing)
                const SizedBox(
                  width: 13,
                  height: 13,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                const Icon(Icons.speed_rounded,
                    size: 15, color: WbColors.ice60),
              const SizedBox(width: 6),
              Text(
                testing
                    ? s.testPing
                    : pingMs != null
                        ? '$pingMs ms'
                        : s.testPing,
                style: const TextStyle(
                  color: WbColors.ice60,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small entry point into the full [SpeedTestScreen] — styled like
/// [_PingRow] right above it, but this is nav-only now; the actual test
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
        child: Row(
          children: [
            Expanded(
              child: Text(
                s.signInToUnlock,
                style:
                    const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: WbColors.ice60),
          ],
        ),
      );
    }
    return WbCard(
      onTap: onOpen,
      tint: tint,
      child: asyncSub.when(
        loading: () => Text(
          s.subscription,
          style: const TextStyle(color: WbColors.ice60),
        ),
        error: (error, _) => Text(
          error is AppException ? error.localized(s) : s.errUnavailable,
          style: const TextStyle(color: WbColors.ice60, fontSize: 13),
        ),
        data: (sub) {
          if (sub.isExpired || !sub.isActive) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.subscriptionExpiredTitle,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  s.chooseAPlanToConnect,
                  style: const TextStyle(color: WbColors.ice60, fontSize: 13),
                ),
              ],
            );
          }
          final days = sub.daysRemaining;
          final usage = ref.watch(trafficUsageProvider).asData?.value;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                s.subscriptionActive,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                days == null ? s.active : '$days ${s.daysRemaining}',
                style: const TextStyle(color: WbColors.ice60, fontSize: 13),
              ),
              if (usage != null) ...[
                const SizedBox(height: 10),
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
