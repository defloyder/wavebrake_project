import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/language_controller.dart';
import '../../core/storage/prefs_store.dart';
import 'settings_ui.dart';

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  late bool _connection = PrefsStore.getBool(
    PrefsStore.notifyConnection,
    fallback: true,
  );
  late bool _subscription = PrefsStore.getBool(
    PrefsStore.notifySubscription,
    fallback: true,
  );

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    return SettingsPage(
      title: s.notifications,
      children: [
        SettingsGroup(children: [
          SettingsSwitchRow(
            icon: Icons.shield_outlined,
            title: s.connectionNotifications,
            value: _connection,
            onChanged: (value) async {
              await PrefsStore.setBool(PrefsStore.notifyConnection, value);
              setState(() => _connection = value);
            },
          ),
          SettingsSwitchRow(
            icon: Icons.event_outlined,
            title: s.subscriptionNotifications,
            subtitle: s.subscriptionNotificationsHint,
            value: _subscription,
            onChanged: (value) async {
              await PrefsStore.setBool(PrefsStore.notifySubscription, value);
              setState(() => _subscription = value);
            },
          ),
        ]),
      ],
    );
  }
}
