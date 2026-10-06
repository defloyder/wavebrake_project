import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/language_controller.dart';
import '../../core/theme/wb_colors.dart';
import '../shared/data_providers.dart';
import '../shared/menu_button.dart';
import '../shared/ocean_background.dart';
import '../shell/app_shell.dart';
import '../shared/wave_params.dart';
import 'servers_sheet.dart';

class LocationsScreen extends ConsumerWidget {
  const LocationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final waves = ref.watch(appWaveParamsProvider);

    // Same isDesktop-aware widening Home does: on a big window the default
    // 560px column reads as an accordion adrift in a sea of near-black
    // background, so give it more room to breathe.
    return LayoutBuilder(
      builder: (context, outer) {
        final isDesktop = outer.maxWidth >= 820;
        // The title travels with the list: the list sits at the bottom by
        // the thumb, and a title pinned to the top left a big empty gap
        // between them (owner, 06.10).
        final title = Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 8),
          child: Row(
            children: [
              if (isDesktop) ...[
                const MenuButton(),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Text(
                  s.chooseLocation,
                  style: const TextStyle(fontFamily: 'serif', fontSize: 30),
                ),
              ),
              Tooltip(
                message: s.refreshServers,
                child: IconButton(
                  onPressed: () => ref.invalidate(locationsProvider),
                  icon:
                      const Icon(Icons.refresh_rounded, color: WbColors.ice60),
                ),
              ),
            ],
          ),
        );
        return OceanBackground(
          illuminate: true,
          tint: waves.tint,
          waveSpeed: waves.speed,
          waveAmplitude: waves.amplitude,
          maxContentWidth: isDesktop ? 720 : 560,
          // Full height: the background centers its child, and a
          // shrink-wrapped list would float mid-screen instead of sitting
          // at the bottom.
          child: SizedBox.expand(
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: ServersList(
                  header: title,
                  // Room for the floating bottom bar on phones.
                  bottomPadding: isDesktop ? 16 : kMobileBottomBarReserve + 12,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
