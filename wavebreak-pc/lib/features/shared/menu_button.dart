import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/wb_colors.dart';
import '../shell/app_shell.dart';

/// Toggles the persistent side nav between icon-only and icon+label modes.
class MenuButton extends ConsumerWidget {
  const MenuButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => ref.read(navExpandedProvider.notifier).update((v) => !v),
        customBorder: const CircleBorder(),
        child: Container(
          width: 38,
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: WbColors.card.withValues(alpha: 0.55),
            border: Border.all(color: WbColors.ice08),
          ),
          child: const Icon(Icons.menu_rounded, color: WbColors.ice60, size: 19),
        ),
      ),
    );
  }
}
