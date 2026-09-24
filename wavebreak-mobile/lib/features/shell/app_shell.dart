import 'dart:io' show Platform;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n/language_controller.dart';
import '../../core/theme/wb_colors.dart';
import '../../services/update/update_service.dart';
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

/// Locations doesn't get its own bottom-bar destination on mobile —
/// location picking lives entirely on Home (tap the location header).
/// The branch/route still exists (desktop's rail still links to it).
/// Speed Test DOES get one (branch 3, appended after Settings in
/// router.dart) — it used to be a small text link buried under the ping
/// row on Home; this is its own proper tab now, in order Home / Speed
/// Test / Settings.
const _kMobileBranchIndexes = [0, 3, 2];

/// Height the floating mobile bottom bar occupies (pill content + its
/// bottom margin, not counting the device's own safe-area inset) — screens
/// use this to keep their last row of content from sitting under the pill
/// now that it floats over the body instead of reserving a Scaffold slot.
const kMobileBottomBarReserve = 74.0;

/// The brand cyan blended a little toward the current location's accent —
/// used for "selected" nav states everywhere (rail item, bottom-bar tab)
/// so they read as WAVEBREAK cyan first and flag-tinted second, never the
/// other way around.
Color _selectedNavColor(Color? tint) => tint == null
    ? WbColors.waveCyan
    : Color.lerp(WbColors.waveCyan, tint, 0.45) ?? WbColors.waveCyan;

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
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                    child: Container(
                      height: 64,
                      decoration: BoxDecoration(
                        // Same gentle wash as the desktop rail — tinted a
                        // little toward the selected location's accent
                        // color instead of a flat, unchanging navy.
                        color: (waveParams.tint == null
                                ? WbColors.deepOcean
                                : Color.lerp(WbColors.deepOcean,
                                        waveParams.tint, 0.30) ??
                                    WbColors.deepOcean)
                            .withValues(alpha: 0.72),
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(color: WbColors.ice08),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.35),
                            blurRadius: 24,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          _MobileNavButton(
                            icon: Icons.home_outlined,
                            filledIcon: Icons.home_rounded,
                            label: s.navHome,
                            selected: activeButton == 0,
                            tint: waveParams.tint,
                            onTap: () => navigationShell.goBranch(
                              0,
                              initialLocation:
                                  navigationShell.currentIndex == 0,
                            ),
                          ),
                          _MobileNavButton(
                            icon: Icons.speed_outlined,
                            filledIcon: Icons.speed_rounded,
                            label: s.speedTest,
                            selected: activeButton == 1,
                            tint: waveParams.tint,
                            onTap: () => navigationShell.goBranch(
                              3,
                              initialLocation:
                                  navigationShell.currentIndex == 3,
                            ),
                          ),
                          _MobileNavButton(
                            icon: Icons.settings_outlined,
                            filledIcon: Icons.settings,
                            label: s.navSettings,
                            selected: activeButton == 2,
                            tint: waveParams.tint,
                            showBadge: pendingUpdate != null,
                            onTap: () => navigationShell.goBranch(
                              2,
                              initialLocation:
                                  navigationShell.currentIndex == 2,
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
    final color = selected ? _selectedNavColor(tint) : WbColors.ice60;
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          // The whole half of the bar is the tap target, not just the
          // icon+label — a big, easy, unmissable thumb target.
          child: SizedBox(
            height: 64,
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
                            color: WbColors.waveCyan,
                            shape: BoxShape.circle,
                            border:
                                Border.all(color: WbColors.deepOcean, width: 1.5),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
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
    final color = selected ? _selectedNavColor(tint) : WbColors.ice60;
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
                    color: WbColors.waveCyan,
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
