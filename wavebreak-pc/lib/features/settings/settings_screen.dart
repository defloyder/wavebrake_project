import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n/language_controller.dart';
import '../../core/theme/wb_colors.dart';
import '../../services/system/launcher_app.dart';
import '../../services/update/update_service.dart';
import '../shared/anchored_page.dart';
import '../shared/notice.dart';
import '../shared/ocean_background.dart';
import '../shared/wave_params.dart';
import '../shell/app_shell.dart';
import '../shared/page_hero.dart';
import 'settings_ui.dart';
import '../shared/page_width.dart';

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
          maxContentWidth: isDesktop ? kDesktopPageWidth : 560,
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
                        Text(
                          s.settings,
                          style: const TextStyle(
                              fontFamily: 'serif', fontSize: 30),
                        ),
                      ],
                    ),
                    Expanded(
                      child: AnchoredPage(
                        // The bottom nav pill floats over the body.
                        padding: EdgeInsets.only(
                            bottom:
                                isDesktop ? 12 : kMobileBottomBarReserve + 12),
                        // Fills the room above the groups; left out where
                        // there is none (a TV is 540 px tall).
                        hero: const AccountHero(),
                        content: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SettingsGroup(children: [
                              SettingsRow(
                                icon: Icons.person_outline_rounded,
                                title: s.account,
                                subtitle: s.accountRowHint,
                                onTap: () => context.push('/settings/account'),
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
                                onTap: () => context.push('/settings/security'),
                              ),
                            ]),
                            SettingsGroup(children: [
                              SettingsRow(
                                icon: Icons.palette_outlined,
                                title: s.appearance,
                                subtitle: s.appearanceRowHint,
                                onTap: () =>
                                    context.push('/settings/personalization'),
                              ),
                              SettingsRow(
                                icon: Icons.notifications_none_rounded,
                                title: s.notifications,
                                subtitle: s.notificationsRowHint,
                                onTap: () =>
                                    context.push('/settings/notifications'),
                              ),
                              SettingsRow(
                                icon: Icons.help_outline_rounded,
                                title: s.help,
                                subtitle: s.helpRowHint,
                                badge: pendingUpdate != null,
                                onTap: () => context.push('/settings/help'),
                              ),
                              // Windows: every WAVEBREAK program for this PC
                              // (owner, 13.10).
                              if (LauncherApp.available)
                                SettingsRow(
                                  icon: Icons.apps_rounded,
                                  title: s.launcherRow,
                                  subtitle: s.launcherRowHint,
                                  trailing: const Icon(
                                      Icons.open_in_new_rounded,
                                      size: 20,
                                      color: WbColors.ice60),
                                  onTap: () async {
                                    showNotice(s.launcherOpening);
                                    try {
                                      await const LauncherApp().open();
                                    } catch (_) {
                                      showNotice(s.launcherFailed,
                                          kind: NoticeKind.error);
                                    }
                                  },
                                ),
                            ]),
                          ],
                        ),
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
