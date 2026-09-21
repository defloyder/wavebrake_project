import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/session_controller.dart';
import '../../core/errors/app_exception.dart';
import '../../core/i18n/language_controller.dart';
import '../../core/theme/wb_colors.dart';
import '../../services/custom_servers/custom_server_controller.dart';
import '../../services/vpn/connection_manager.dart';
import '../shared/add_custom_server_sheet.dart';
import '../shared/confirm_dialogs.dart';
import '../shared/data_providers.dart';
import '../shared/menu_button.dart';
import '../shared/ocean_background.dart';
import '../shared/subscription_accordion.dart';
import '../shared/subscription_section.dart';
import '../shared/wave_params.dart';

class LocationsScreen extends ConsumerWidget {
  const LocationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(connectionManagerProvider).location;
    final locations = ref.watch(locationsProvider);
    final custom = ref.watch(customServersProvider);
    final s = ref.watch(stringsProvider);
    final canConnect = ref.watch(canConnectProvider);
    final waves = ref.watch(appWaveParamsProvider);

    // Same isDesktop-aware widening Home does: on a big window the default
    // 560px column reads as an accordion adrift in a sea of near-black
    // background (WbColors.midnight is dark enough that the empty margins
    // read as "unrendered" at a glance), so give it more room to breathe.
    return LayoutBuilder(
      builder: (context, outer) {
        final isDesktop = outer.maxWidth >= 820;
        return OceanBackground(
      illuminate: true,
      tint: waves.tint,
      waveSpeed: waves.speed,
      waveAmplitude: waves.amplitude,
      maxContentWidth: isDesktop ? 720 : 560,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 12),
              Row(
                children: [
                  if (isDesktop) ...[
                    const MenuButton(),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Text(
                      s.chooseLocation,
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
                    ),
                  ),
                  Tooltip(
                    message: s.refreshServers,
                    child: IconButton(
                      onPressed: () => ref.invalidate(locationsProvider),
                      icon: const Icon(Icons.refresh_rounded, color: WbColors.ice60),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: locations.when(
                  loading: () => const Center(
                    child: CircularProgressIndicator(),
                  ),
                  error: (error, _) => Center(
                    child: Text(
                      error is AppException ? error.localized(s) : s.errUnavailable,
                      textAlign: TextAlign.center,
                    ),
                  ),
                  data: (items) {
                    final sections = buildSubscriptionSections(
                      wavebreakLocations: items,
                      customGroups: custom,
                      s: s,
                      wavebreakShareUrl:
                          ref.watch(sessionControllerProvider).config.websiteUrl,
                    );
                    return SingleChildScrollView(
                      child: SubscriptionAccordion(
                        sections: sections,
                        currentId: selected.id,
                        s: s,
                        shrinkWrap: true,
                        onSelect: (item) => ref
                            .read(connectionManagerProvider.notifier)
                            .selectLocation(item, subscriptionActive: canConnect),
                        onAddCustom: () => showAddCustomServerSheet(context, ref),
                        onRemove: (id) async {
                          if (!await confirmRemoveCustomGroup(context, s)) return;
                          // See home_screen.dart's _removeCustomGroup for
                          // why this check exists: removeGroup() alone
                          // never reaches ConnectionManager, so a tunnel
                          // actively using a just-deleted server's link
                          // would otherwise keep running with no server
                          // left anywhere in the UI to disconnect it from.
                          final connection = ref.read(connectionManagerProvider);
                          final matches = ref
                              .read(customServersProvider)
                              .where((g) => g.id == id);
                          final group = matches.isEmpty ? null : matches.first;
                          final connectedToThisGroup = group != null &&
                              connection.status != ConnectionStatus.idle &&
                              group.servers.any((server) =>
                                  server.id == connection.effectiveLocation.id);
                          ref.read(customServersProvider.notifier).removeGroup(id);
                          if (connectedToThisGroup) {
                            await ref
                                .read(connectionManagerProvider.notifier)
                                .disconnect();
                          }
                        },
                        onRefresh: (id) =>
                            ref.read(customServersProvider.notifier).refreshGroup(id),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
        );
      },
    );
  }
}
