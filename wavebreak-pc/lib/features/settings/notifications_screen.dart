import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/language_controller.dart';
import '../../core/storage/prefs_store.dart';
import '../../core/theme/wb_colors.dart';
import '../shared/detail_scaffold.dart';
import '../shared/nav_utils.dart';
import '../shared/wb_card.dart';

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() => _NotificationsScreenState();
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
    return DetailScaffold(
      title: s.notifications,
      onBack: () => safePop(context, fallback: '/settings'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
                WbCard(
                  child: SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    activeTrackColor: WbColors.waveCyan,
                    title: Text(s.connectionNotifications),
                    value: _connection,
                    onChanged: (value) async {
                      await PrefsStore.setBool(
                          PrefsStore.notifyConnection, value);
                      setState(() => _connection = value);
                    },
                  ),
                ),
                const SizedBox(height: 12),
                WbCard(
                  child: SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    activeTrackColor: WbColors.waveCyan,
                    title: Text(s.subscriptionNotifications),
                    subtitle: Text(
                      s.subscriptionNotificationsHint,
                      style: const TextStyle(color: WbColors.ice60, fontSize: 12),
                    ),
                    value: _subscription,
                    onChanged: (value) async {
                      await PrefsStore.setBool(
                          PrefsStore.notifySubscription, value);
                      setState(() => _subscription = value);
                    },
                  ),
                ),
        ],
      ),
    );
  }
}
