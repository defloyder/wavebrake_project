import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/language_controller.dart';
import '../../core/storage/prefs_store.dart';
import '../../core/theme/wb_colors.dart';
import '../../services/system/battery_optimization.dart';
import '../../services/system/quick_tile.dart';
import '../../services/system/vpn_lockdown.dart';
import 'settings_ui.dart';

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
  late bool _smartRouting =
      PrefsStore.getBool(PrefsStore.smartRouting, fallback: true);

  Future<void> _setAutoConnect(bool value) async {
    await PrefsStore.setBool(PrefsStore.autoConnect, value);
    setState(() {
      _autoConnect = value;
      if (!value) {
        _onLaunch = false;
        _onUntrustedWifi = false;
      }
    });
    if (!value) {
      await PrefsStore.setBool(PrefsStore.autoConnectOnLaunch, false);
      await PrefsStore.setBool(PrefsStore.autoConnectUntrustedWifi, false);
    }
  }

  /// Adds the WAVEBREAK tile to the phone's Quick Settings (Android 13+
  /// asks the system; older versions get the manual steps).
  Future<void> _addQuickTile() async {
    final s = ref.read(stringsProvider);
    final result = await QuickTile.requestAdd();
    if (!mounted) return;
    if (result == QuickTileResult.manual) {
      await showSettingsInfo(context, s.quickTileTitle, s.quickTileManual);
      return;
    }
    final text = switch (result) {
      QuickTileResult.added => s.quickTileAdded,
      QuickTileResult.alreadyAdded => s.quickTileAlready,
      _ => null,
    };
    if (text != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    return SettingsPage(
      title: s.connection,
      children: [
        SettingsGroup(
          title: s.autoConnect,
          children: [
            SettingsSwitchRow(
              icon: Icons.bolt_outlined,
              title: s.autoConnect,
              value: _autoConnect,
              onChanged: _setAutoConnect,
            ),
            SettingsSwitchRow(
              icon: Icons.play_circle_outline_rounded,
              title: s.onAppLaunch,
              value: _onLaunch,
              onChanged: _autoConnect
                  ? (value) async {
                      await PrefsStore.setBool(
                          PrefsStore.autoConnectOnLaunch, value);
                      setState(() => _onLaunch = value);
                    }
                  : null,
            ),
            SettingsSwitchRow(
              icon: Icons.wifi_password_rounded,
              title: s.onUntrustedWifi,
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
        SettingsGroup(
          title: s.groupRouting,
          children: [
            SettingsRow(
              icon: Icons.tune_rounded,
              title: s.connectionMode,
              value: s.automatic,
            ),
            // WAVEBREAK locations only; applies on the next connect.
            // Android for now — the Windows engine doesn't read it yet.
            if (Platform.isAndroid)
              SettingsSwitchRow(
                icon: Icons.alt_route_rounded,
                title: s.smartRoutingTitle,
                subtitle: s.smartRoutingHint,
                value: _smartRouting,
                onChanged: (value) async {
                  await PrefsStore.setBool(PrefsStore.smartRouting, value);
                  setState(() => _smartRouting = value);
                },
              ),
          ],
        ),
        if (Platform.isAndroid)
          SettingsGroup(
            title: s.groupSystem,
            children: [
              // The system kill switch: a short line, details behind (i);
              // the row opens Android's VPN screen, where the user turns
              // it on (apps can't).
              if (VpnLockdown.available)
                SettingsRow(
                  icon: Icons.gpp_good_outlined,
                  title: s.killSwitchTitle,
                  subtitle: s.killSwitchHint,
                  info: s.killSwitchInfo,
                  trailing: const Icon(Icons.open_in_new_rounded,
                      size: 20, color: WbColors.ice60),
                  onTap: VpnLockdown.openSystemSettings,
                ),
              if (QuickTile.available)
                SettingsRow(
                  icon: Icons.toggle_on_outlined,
                  title: s.quickTileTitle,
                  subtitle: s.quickTileHint,
                  info: s.quickTileInfo,
                  trailing: const Icon(Icons.add_rounded,
                      size: 22, color: WbColors.ice60),
                  onTap: _addQuickTile,
                ),
              // Always here (not just the one-time prompt after the first
              // connect), so declining that prompt is never a one-way door.
              SettingsRow(
                icon: Icons.battery_charging_full_outlined,
                title: s.batteryOptSettingsRow,
                onTap: () =>
                    const BatteryOptimizationService().requestExemption(),
              ),
            ],
          ),
      ],
    );
  }
}
