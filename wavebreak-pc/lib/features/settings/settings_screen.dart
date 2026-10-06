import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n/language_controller.dart';
import '../../services/update/update_service.dart';
import '../shared/menu_button.dart';
import '../shared/ocean_background.dart';
import '../shared/wave_params.dart';
import '../shell/app_shell.dart';
import '../shared/page_hero.dart';
import 'settings_ui.dart';

/// Settings, top level (P6): six groups, everything else one level down.
///
/// Account · Connection · Security · Appearance · Notifications · Help.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final waves = ref.watch(appWaveParamsProvider);
    // Android and Windows ship outside any app store: Help > Updates is
    // the in-app path to a new build; the dot on Help says one is waiting.
    final pendingUpdate = (Platform.isAndroid || Platform.isWindows)
        ? ref.watch(availableUpdateProvider).asData?.value
        : null;

    return LayoutBuilder(
      builder: (context, outer) {
        final isDesktop = outer.maxWidth >= 820;
        return OceanBackground(
          illuminate: true,
          tint: waves.tint,
          waveSpeed: waves.speed,
          waveAmplitude: waves.amplitude,
          maxContentWidth: isDesktop ? 640 : 560,
          child: SizedBox.expand(
            child: SafeArea(
              // Title at the top, the groups at the bottom by the thumb and
              // the nav bar, the account filling the space between (owner,
              // 06.10); a long page scrolls up.
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        // The side rail this toggles only exists on desktop.
                        if (isDesktop) ...[
                          const MenuButton(),
                          const SizedBox(width: 12),
                        ],
                        Text(
                          s.settings,
                          style: const TextStyle(
                              fontFamily: 'serif', fontSize: 30),
                        ),
                      ],
                    ),
                    Expanded(
                      child: CustomScrollView(
                        reverse: true,
                        slivers: [
                          SliverPadding(
                            // The bottom nav pill floats over the body.
                            padding: EdgeInsets.only(
                                bottom: isDesktop
                                    ? 12
                                    : kMobileBottomBarReserve + 12),
                            sliver: SliverToBoxAdapter(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 16),
                                  SettingsGroup(children: [
                                    SettingsRow(
                                      icon: Icons.person_outline_rounded,
                                      title: s.account,
                                      subtitle: s.accountRowHint,
                                      onTap: () =>
                                          context.push('/settings/account'),
                                    ),
                                    SettingsRow(
                                      icon: Icons.wifi_tethering_rounded,
                                      title: s.connection,
                                      subtitle: s.connectionRowHint,
                                      onTap: () =>
                                          context.push('/settings/connection'),
                                    ),
                                    SettingsRow(
                                      icon: Icons.fingerprint_rounded,
                                      title: s.security,
                                      subtitle: s.securityRowHint,
                                      onTap: () =>
                                          context.push('/settings/security'),
                                    ),
                                  ]),
                                  SettingsGroup(children: [
                                    SettingsRow(
                                      icon: Icons.palette_outlined,
                                      title: s.appearance,
                                      subtitle: s.appearanceRowHint,
                                      onTap: () => context
                                          .push('/settings/personalization'),
                                    ),
                                    SettingsRow(
                                      icon: Icons.notifications_none_rounded,
                                      title: s.notifications,
                                      subtitle: s.notificationsRowHint,
                                      onTap: () => context
                                          .push('/settings/notifications'),
                                    ),
                                    SettingsRow(
                                      icon: Icons.help_outline_rounded,
                                      title: s.help,
                                      subtitle: s.helpRowHint,
                                      badge: pendingUpdate != null,
                                      onTap: () =>
                                          context.push('/settings/help'),
                                    ),
                                  ]),
                                ],
                              ),
                            ),
                          ),
                          // The account only where there is room (a TV is
                          // 540 px tall).
                          if (MediaQuery.sizeOf(context).height >= 600)
                            SliverFillRemaining(
                              hasScrollBody: false,
                              child: Center(
                                child: Padding(
                                  padding: EdgeInsets.symmetric(vertical: 16),
                                  child: AccountHero(),
                                ),
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
      },
    );
  }
}
