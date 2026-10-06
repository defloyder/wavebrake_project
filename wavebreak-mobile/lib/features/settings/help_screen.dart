import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n/language_controller.dart';
import '../../services/update/update_service.dart';
import 'settings_ui.dart';

/// Settings > Help: support, updates, about.
class HelpScreen extends ConsumerWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final updatable = Platform.isAndroid || Platform.isWindows;
    final pendingUpdate =
        updatable ? ref.watch(availableUpdateProvider).asData?.value : null;
    return SettingsPage(
      title: s.help,
      children: [
        SettingsGroup(children: [
          SettingsRow(
            icon: Icons.chat_bubble_outline_rounded,
            title: s.support,
            onTap: () => context.push('/settings/support'),
          ),
          if (updatable)
            SettingsRow(
              icon: Icons.system_update_rounded,
              title: s.updates,
              value: pendingUpdate?.versionName,
              badge: pendingUpdate != null,
              onTap: () => context.push('/settings/updates'),
            ),
          SettingsRow(
            icon: Icons.info_outline_rounded,
            title: s.about,
            onTap: () => context.push('/settings/about'),
          ),
        ]),
      ],
    );
  }
}
