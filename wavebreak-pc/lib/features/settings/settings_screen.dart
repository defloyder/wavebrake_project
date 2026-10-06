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
              // Phone: the page sits at the bottom, by the thumb and the nav
              // bar (owner, 06.10); it scrolls up if it doesn't fit.
              child: SingleChildScrollView(
                reverse: !isDesktop,
                // The bottom nav pill floats over the body (see app_shell).
                padding: EdgeInsets.fromLTRB(
                  20,
                  12,
                  20,
                  isDesktop ? 12 : kMobileBottomBarReserve + 12,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
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
                    const SizedBox(height: 16),
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
                        onTap: () => context.push('/settings/connection'),
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
                        onTap: () => context.push('/settings/personalization'),
                      ),
                      SettingsRow(
                        icon: Icons.notifications_none_rounded,
                        title: s.notifications,
                        subtitle: s.notificationsRowHint,
                        onTap: () => context.push('/settings/notifications'),
                      ),
                      SettingsRow(
                        icon: Icons.help_outline_rounded,
                        title: s.help,
                        subtitle: s.helpRowHint,
                        badge: pendingUpdate != null,
                        onTap: () => context.push('/settings/help'),
                      ),
                    ]),
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
