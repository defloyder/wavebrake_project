import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/language_controller.dart';
import '../../core/storage/prefs_store.dart';
import '../../core/theme/wb_colors.dart';
import '../../services/system/battery_optimization.dart';
import '../shared/detail_scaffold.dart';
import '../shared/nav_utils.dart';
import '../shared/wb_card.dart';

class ConnectionSettingsScreen extends ConsumerStatefulWidget {
  const ConnectionSettingsScreen({super.key});

  @override
  ConsumerState<ConnectionSettingsScreen> createState() =>
      _ConnectionSettingsScreenState();
}

class _ConnectionSettingsScreenState
    extends ConsumerState<ConnectionSettingsScreen> {
  late bool _autoConnect = PrefsStore.getBool(PrefsStore.autoConnect);
  late bool _onLaunch = PrefsStore.getBool(PrefsStore.autoConnectOnLaunch);
  late bool _onUntrustedWifi =
      PrefsStore.getBool(PrefsStore.autoConnectUntrustedWifi);

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    return DetailScaffold(
      title: s.connection,
      onBack: () => safePop(context, fallback: '/settings'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          WbCard(
            child: SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              activeTrackColor: WbColors.waveCyan,
              title: Text(s.autoConnect),
              value: _autoConnect,
              onChanged: (value) async {
                await PrefsStore.setBool(PrefsStore.autoConnect, value);
                setState(() {
                  _autoConnect = value;
                  if (!value) {
                    _onLaunch = false;
                    _onUntrustedWifi = false;
                  }
                });
                if (!value) {
                  await PrefsStore.setBool(
                      PrefsStore.autoConnectOnLaunch, false);
                  await PrefsStore.setBool(
                      PrefsStore.autoConnectUntrustedWifi, false);
                }
              },
            ),
          ),
          const SizedBox(height: 12),
          WbCard(
            child: Column(
              children: [
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  activeTrackColor: WbColors.waveCyan,
                  title: Text(s.onAppLaunch),
                  value: _onLaunch,
                  onChanged: _autoConnect
                      ? (value) async {
                          await PrefsStore.setBool(
                              PrefsStore.autoConnectOnLaunch, value);
                          setState(() => _onLaunch = value);
                        }
                      : null,
                ),
                const Divider(height: 1, color: WbColors.ice08),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  activeTrackColor: WbColors.waveCyan,
                  title: Text(s.onUntrustedWifi),
                  value: _onUntrustedWifi,
                  onChanged: _autoConnect
                      ? (value) async {
                          await PrefsStore.setBool(
                              PrefsStore.autoConnectUntrustedWifi, value);
                          setState(() => _onUntrustedWifi = value);
                        }
                      : null,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            s.connectionMode,
            style: const TextStyle(color: WbColors.ice60, fontSize: 13),
          ),
          const SizedBox(height: 8),
          WbCard(
            child: Row(
              children: [
                const Icon(Icons.bolt_outlined, color: WbColors.waveCyan),
                const SizedBox(width: 12),
                Expanded(child: Text(s.automatic)),
              ],
            ),
          ),
          // Android only — see battery_optimization.dart's own comment.
          // Always shown here (not just the one-time post-connect prompt
          // on Home) so declining that prompt is never a one-way door.
          if (Platform.isAndroid) ...[
            const SizedBox(height: 20),
            WbCard(
              onTap: () async {
                await const BatteryOptimizationService().requestExemption();
              },
              child: Row(
                children: [
                  const Icon(Icons.battery_charging_full_outlined,
                      color: WbColors.waveCyan),
                  const SizedBox(width: 12),
                  Expanded(child: Text(s.batteryOptSettingsRow)),
                  const Icon(Icons.chevron_right, color: WbColors.ice60),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
