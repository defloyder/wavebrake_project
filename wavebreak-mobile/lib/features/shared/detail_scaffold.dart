import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/wb_colors.dart';
import '../shell/app_shell.dart';
import 'ocean_background.dart';
import 'wave_params.dart';

/// Shared shell for every "back button + title, then a column of cards"
/// settings/detail screen (Account, Security, Connection, Devices,
/// Notifications, Support, About, Subscription).
///
/// The back button sits inline with the title on one header row — both
/// scroll and center together as a unit, rather than the button being
/// pinned alone to the screen's physical edge while the title sits
/// somewhere else in the centered column below it.
class DetailScaffold extends ConsumerWidget {
  const DetailScaffold({
    super.key,
    required this.title,
    required this.child,
    required this.onBack,
    this.maxWidth = 560,
  });

  final String title;

  /// Content below the header row — do NOT include the title or back
  /// button here, both are rendered by the header above [child].
  final Widget child;
  final VoidCallback onBack;

  /// Cap on the centered content's width.
  final double maxWidth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final waves = ref.watch(appWaveParamsProvider);
    return Scaffold(
      body: OceanBackground(
        illuminate: true,
        tint: waves.tint,
        waveSpeed: waves.speed,
        waveAmplitude: waves.amplitude,
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              // The floating mobile bottom bar paints over the body
              // instead of reserving its own Scaffold slot (see
              // app_shell.dart), so any content this screen pins to the
              // bottom via Spacer/Expanded — a logout button, the last row
              // of a device list — needs this screen to leave room for it
              // manually, same as Home and Settings already do.
              final isDesktop = constraints.maxWidth >= 820;
              return Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxWidth),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      20,
                      0,
                      20,
                      isDesktop ? 0 : kMobileBottomBarReserve,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            _BackButton(onTap: onBack),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                title,
                                style:
                                    const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        // Expanded (not just `child` directly) so a screen
                        // whose own content uses Expanded/Spacer internally
                        // (e.g. a scrollable device list, or a logout
                        // button pinned to the bottom) gets the bounded
                        // height those need.
                        Expanded(child: child),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _BackButton extends StatelessWidget {
  const _BackButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: WbColors.card.withValues(alpha: 0.55),
            border: Border.all(color: WbColors.ice08),
          ),
          child: const Icon(Icons.arrow_back_ios_new_rounded, size: 17, color: WbColors.ice),
        ),
      ),
    );
  }
}
