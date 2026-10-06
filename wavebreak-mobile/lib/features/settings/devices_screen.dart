import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../core/i18n/language_controller.dart';
import '../../core/logging/app_logger.dart';
import '../../core/theme/wb_colors.dart';
import '../../services/providers.dart';
import '../shared/data_providers.dart';
import 'settings_ui.dart';

class DevicesScreen extends ConsumerStatefulWidget {
  const DevicesScreen({super.key});

  @override
  ConsumerState<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends ConsumerState<DevicesScreen> {
  String? _revokingId;

  Future<void> _revoke(String deviceId, String deviceName) async {
    final s = ref.read(stringsProvider);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: WbColors.card,
        title: Text(s.removeDeviceTitle),
        content: Text('$deviceName\n\n${s.removeDeviceBody}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(s.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(s.remove, style: const TextStyle(color: WbColors.error)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _revokingId = deviceId);
    try {
      await ref.read(coreGatewayProvider).revokeDevice(deviceId);
      ref.invalidate(devicesProvider);
    } catch (error) {
      AppLogger.warn('Device revoke failed: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error is AppException ? error.localized(s) : s.errUnavailable),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _revokingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final devices = ref.watch(devicesProvider);
    final s = ref.watch(stringsProvider);

    Widget centered(String text) => Padding(
          padding: const EdgeInsets.only(top: 48),
          child: Text(text,
              textAlign: TextAlign.center,
              style: const TextStyle(color: WbColors.ice60)),
        );

    return SettingsPage(
      title: s.devices,
      fallback: '/settings/account',
      children: [
        devices.when(
          loading: () => const Padding(
            padding: EdgeInsets.only(top: 48),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) => centered(
              error is AppException ? error.localized(s) : s.errUnavailable),
          data: (items) => items.isEmpty
              ? centered(s.noDevicesYet)
              : SettingsGroup(children: [
                  for (final device in items)
                    SettingsRow(
                      icon: switch (device.platform) {
                        'ios' => Icons.phone_iphone,
                        'windows' || 'macos' || 'linux' => Icons.laptop_mac,
                        _ => Icons.phone_android,
                      },
                      title: device.name,
                      subtitle: device.current ? s.thisDevice : null,
                      // The current device can't revoke itself (it would
                      // cut off the session showing this screen); every
                      // other one can — the way under a plan's device
                      // limit once old installs have piled up.
                      trailing: device.current
                          ? null
                          : _revokingId == device.id
                              ? const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  ),
                                )
                              : IconButton(
                                  tooltip: s.remove,
                                  onPressed: () =>
                                      _revoke(device.id, device.name),
                                  icon: const Icon(Icons.delete_outline,
                                      color: WbColors.error),
                                ),
                    ),
                ]),
        ),
      ],
    );
  }
}
