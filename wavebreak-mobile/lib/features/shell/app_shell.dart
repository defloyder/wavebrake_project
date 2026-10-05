import '../../core/theme/wb_theme.dart';
import 'dart:async';
import 'dart:io' show Platform;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n/language_controller.dart';
import '../../core/storage/prefs_store.dart';
import '../../core/theme/wb_colors.dart';
import '../../services/update/update_service.dart';
import '../immersive/effects_quality.dart';
import '../immersive/immersive_colors.dart';
import '../shared/wave_params.dart';
import '../shared/wavebreak_mark.dart';

const _kRailCollapsedWidth = 58.0;
const _kRailExpandedWidth = 208.0;
const _kDesktopBreakpoint = 820.0;

/// Whether the persistent nav rail is showing labels (expanded) or just
/// icons (collapsed). Lives above the shell so the menu button in each
/// tab's own header can toggle it. Desktop only — mobile has no rail to
/// expand, it uses a bottom bar instead.
final navExpandedProvider = StateProvider<bool>((ref) => false);

/// Bottom bar order (V5): Home / Servers / Test / Metrics / Settings —
/// positions in the bar mapped to router branch indexes (Settings is
/// branch 2, Speed Test 3, Metrics 4 — appended over time).
const _kMobileBranchIndexes = [0, 1, 3, 4, 2];

/// Height the floating mobile bottom bar occupies (pill content + its
/// bottom margin, not counting the device's own safe-area inset) — screens
/// use this to keep their last row of content from sitting under the pill
/// now that it floats over the body instead of reserving a Scaffold slot.
const kMobileBottomBarReserve = 74.0;

/// Selected nav states (rail item, bottom-bar tab): the theme accent,
/// which follows the current location's flag.
Color _selectedNavColor(BuildContext context) => context.accent;

class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final waveParams = ref.watch(appWaveParamsProvider);
    // Android only — see update_service.dart's own doc comment. A small
    // badge dot on the Settings destination itself, rather than a header
    // bell: the bell used to collide with the logo/wordmark and the
    // offline indicator once both needed header space — this is the
    // same "there's something pending" signal without any header at all.
    // Settings > Updates (updates_screen.dart) is what it always points to.
    final pendingUpdate = Platform.isAndroid
        ? ref.watch(availableUpdateProvider).asData?.value
        : null;
    if (Platform.isAndroid) {
      ref.listen(availableUpdateProvider, (previous, next) {
        final info = next.asData?.value;
        if (info == null) return;
        final lastNotified =
            PrefsStore.getInt(PrefsStore.lastNotifiedUpdateVersionCode) ?? 0;
        if (info.versionCode <= lastNotified) return;
        unawaited(PrefsStore.setInt(
            PrefsStore.lastNotifiedUpdateVersionCode, info.versionCode));
        unawaited(showUpdateAvailableNotification(info.versionName,
            versionCode: info.versionCode));
      });
    }
    final items = [
      _NavItemData(
          icon: Icons.home_outlined,
          filledIcon: Icons.home_rounded,
          label: s.navHome),
      _NavItemData(
          icon: Icons.public_outlined,
          filledIcon: Icons.public,
          label: s.navLocations),
      _NavItemData(
          icon: Icons.settings_outlined,
          filledIcon: Icons.settings,
          label: s.navSettings,
          showBadge: pendingUpdate != null),
      // Index 3 — must match router.dart's branch order (appended after
      // Settings) since _SideNav's onSelect maps position i straight to
      // navigationShell.goBranch(i).
      _NavItemData(
          icon: Icons.speed_outlined,
          filledIcon: Icons.speed_rounded,
          label: s.speedTest),
      // Index 4 — Metrics (router branch 4).
      _NavItemData(
          icon: Icons.ssid_chart_outlined,
          filledIcon: Icons.ssid_chart_rounded,
          label: s.navMetrics),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= _kDesktopBreakpoint;
        if (!isDesktop) {
          return _MobileShell(
            navigationShell: navigationShell,
            waveParams: waveParams,
          );
        }

        final expanded = ref.watch(navExpandedProvider);
        return Scaffold(
          body: Stack(
            children: [
              // The content always sees a constant-width rail slot —
              // expanding the rail never reflows or squeezes this.
              Row(
                children: [
                  const SizedBox(width: _kRailCollapsedWidth),
                  Expanded(child: navigationShell),
                ],
              ),
              if (expanded)
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () =>
                        ref.read(navExpandedProvider.notifier).state = false,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 200),
                      opacity: 1,
                      child: Container(
                          color: Colors.black.withValues(alpha: 0.28)),
                    ),
                  ),
                ),
              // The rail itself floats on top so its expanded state
              // overlays the content instead of resizing it.
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                child: _SideNav(
                  expanded: expanded,
                  selectedIndex: navigationShell.currentIndex,
                  items: items,
                  waveParams: waveParams,
                  onSelect: (i) {
                    ref.read(navExpandedProvider.notifier).state = false;
                    navigationShell.goBranch(
                      i,
                      initialLocation: i == navigationShell.currentIndex,
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _NavItemData {
  const _NavItemData({
    required this.icon,
    required this.filledIcon,
    required this.label,
    this.showBadge = false,
  });
  final IconData icon;
  final IconData filledIcon;
  final String label;
  final bool showBadge;
}

/// Mobile layout: content fills the screen, a frosted bottom bar floats
/// over the very bottom of it — the one navigation surface someone
/// holding the phone one-handed can always reach with their thumb,
/// instead of a side rail that puts destinations up near the top edge.
class _MobileShell extends ConsumerWidget {
  const _MobileShell({required this.navigationShell, required this.waveParams});

  final StatefulNavigationShell navigationShell;
  final WaveParams waveParams;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    // Which of the two bottom-bar buttons corresponds to the active
    // branch — branch 1 (Locations) has no button, so nothing lights up
    // for it (it's only ever reached via Home's own location picker).
    final activeButton =
        _kMobileBranchIndexes.indexOf(navigationShell.currentIndex);
    // See AppShell's own copy of this same watch for the full comment —
    // this one's needed here too since the mobile bottom bar builds its
    // three buttons directly rather than from the desktop rail's `items`.
    final pendingUpdate = Platform.isAndroid
        ? ref.watch(availableUpdateProvider).asData?.value
        : null;

    return Scaffold(
      // No slot-based bottomNavigationBar — that slot paints the
      // Scaffold's own flat background behind it. Floating the pill over
      // a full-height body instead means nothing but the pill's own
      // frosted glass paints anything down there; the screen's real
      // (moving, tinted) background shows through everywhere else.
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Positioned.fill(child: navigationShell),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  child: BackdropFilter(
                    // Economy effects (older phones): no live blur.
                    enabled: !ref.watch(effectsEconomyProvider),
                    filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                    child: Container(
                      height: 64,
                      decoration: BoxDecoration(
                        // Same gentle wash as the desktop rail — tinted a
                        // little toward the selected location's accent
                        // color instead of a flat, unchanging navy.
                        color: Ic.glassMid.withValues(alpha: 0.82),
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(color: Ic.glassBorder),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.45),
                            blurRadius: 24,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          for (final (i, branch, icon, filled, label) in [
                            (
                              0,
                              0,
                              Icons.home_outlined,
                              Icons.home_rounded,
                              s.navHome
                            ),
                            (
                              1,
                              1,
                              Icons.public_outlined,
                              Icons.public,
                              s.navLocations
                            ),
                            (
                              2,
                              3,
                              Icons.speed_outlined,
                              Icons.speed_rounded,
                              s.navSpeedShort
                            ),
                            (
                              3,
                              4,
                              Icons.ssid_chart_outlined,
                              Icons.ssid_chart_rounded,
                              s.navMetrics
                            ),
                            (
                              4,
                              2,
                              Icons.settings_outlined,
                              Icons.settings,
                              s.navSettings
                            ),
                          ])
                            _MobileNavButton(
                              icon: icon,
                              filledIcon: filled,
                              label: label,
                              selected: activeButton == i,
                              tint: waveParams.tint,
                              showBadge: branch == 2 && pendingUpdate != null,
                              onTap: () => navigationShell.goBranch(
                                branch,
                                initialLocation:
                                    navigationShell.currentIndex == branch,
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
        ],
      ),
    );
  }
}

class _MobileNavButton extends StatelessWidget {
  const _MobileNavButton({
    required this.icon,
    required this.filledIcon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.tint,
    this.showBadge = false,
  });

  final IconData icon;
  final IconData filledIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? tint;
  final bool showBadge;

  @override
  Widget build(BuildContext context) {
    final color = selected ? Ic.text : Ic.textMuted;
    return Expanded(
      child: Semantics(
        selected: selected,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(18),
            // The whole fifth of the bar is the tap target, not just the
            // icon+label — a big, easy, unmissable thumb target.
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              height: 56,
              margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                color: selected
                    ? context.brand.withValues(alpha: 0.16)
                    : Colors.transparent,
                border: Border.all(
                  color: selected
                      ? context.brand.withValues(alpha: 0.35)
                      : Colors.transparent,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Icon(selected ? filledIcon : icon,
                          color: color, size: 24),
                      if (showBadge)
                        Positioned(
                          top: -2,
                          right: -3,
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: context.accent,
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: WbColors.deepOcean, width: 1.5),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.fade,
                    softWrap: false,
                    style: TextStyle(
                      color: color,
                      fontSize: 10.5,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SideNav extends StatelessWidget {
  const _SideNav({
    required this.expanded,
    required this.selectedIndex,
    required this.items,
    required this.onSelect,
    required this.waveParams,
  });

  final bool expanded;
  final int selectedIndex;
  final List<_NavItemData> items;
  final ValueChanged<int> onSelect;
  final WaveParams waveParams;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      width: expanded ? _kRailExpandedWidth : _kRailCollapsedWidth,
      decoration: BoxDecoration(
        border: const Border(right: BorderSide(color: WbColors.ice08)),
        boxShadow: expanded
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 24,
                  offset: const Offset(6, 0),
                ),
              ]
            : null,
      ),
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            // Frosted glass over the same ocean background the rest of the
            // app paints — tinted a little toward the selected location's
            // accent color (like every other surface now), and lighter than
            // before so more of that background shows through.
            color: (waveParams.tint == null
                    ? WbColors.deepOcean
                    : Color.lerp(WbColors.deepOcean, waveParams.tint, 0.30) ??
                        WbColors.deepOcean)
                .withValues(alpha: 0.34),
            child: Stack(
              children: [
                // The signal-flow streaks are hidden for now (kept in
                // signal_flow.dart in case they come back later).
                SafeArea(
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        child: expanded
                            ? const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 16),
                                child: Row(
                                  children: [
                                    WavebreakMark(size: 28),
                                    SizedBox(width: 10),
                                    Expanded(
                                        child: WavebreakWordmarkText(size: 13)),
                                  ],
                                ),
                              )
                            : const WavebreakMark(size: 28),
                      ),
                      const SizedBox(height: 12),
                      for (var i = 0; i < items.length; i++)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 5),
                          child: _RailItem(
                            data: items[i],
                            expanded: expanded,
                            selected: selectedIndex == i,
                            tint: waveParams.tint,
                            onTap: () => onSelect(i),
                          ),
                        ),
                    ],
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

class _RailItem extends StatelessWidget {
  const _RailItem({
    required this.data,
    required this.expanded,
    required this.selected,
    required this.onTap,
    this.tint,
  });

  final _NavItemData data;
  final bool expanded;
  final bool selected;
  final VoidCallback onTap;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final color = selected ? _selectedNavColor(context) : WbColors.ice60;
    final content = Row(
      mainAxisAlignment:
          expanded ? MainAxisAlignment.start : MainAxisAlignment.center,
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            Icon(selected ? data.filledIcon : data.icon,
                color: color, size: 21),
            if (data.showBadge)
              Positioned(
                top: -2,
                right: -3,
                child: Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: context.accent,
                    shape: BoxShape.circle,
                    border: Border.all(color: WbColors.deepOcean, width: 1.2),
                  ),
                ),
              ),
          ],
        ),
        if (expanded) ...[
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              data.label,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.clip,
              style: TextStyle(
                color: color,
                fontSize: 14,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        ],
      ],
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          height: 44,
          padding: EdgeInsets.symmetric(horizontal: expanded ? 14 : 0),
          decoration: BoxDecoration(
            color:
                selected ? color.withValues(alpha: 0.14) : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color:
                  selected ? color.withValues(alpha: 0.3) : Colors.transparent,
            ),
          ),
          child: content,
        ),
      ),
    );
  }
}
