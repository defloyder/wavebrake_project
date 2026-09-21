import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../core/i18n/language_controller.dart';
import '../../core/logging/app_logger.dart';
import '../../core/theme/wb_colors.dart';
import '../../services/providers.dart';
import '../shared/data_providers.dart';
import '../shared/detail_scaffold.dart';
import '../shared/nav_utils.dart';
import '../shared/wb_card.dart';

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

    return DetailScaffold(
      title: s.devices,
      onBack: () => safePop(context, fallback: '/settings'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: devices.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(
                child: Text(
                  error is AppException ? error.localized(s) : s.errUnavailable,
                  textAlign: TextAlign.center,
                ),
              ),
              data: (items) => items.isEmpty
                  ? Center(
                      child: Text(
                        s.noDevicesYet,
                        style: const TextStyle(color: WbColors.ice60),
                      ),
                    )
                  : ListView.separated(
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final device = items[index];
                  final revoking = _revokingId == device.id;
                  return WbCard(
                    child: Row(
                      children: [
                        Icon(
                          switch (device.platform) {
                            'ios' => Icons.phone_iphone,
                            'windows' || 'macos' || 'linux' => Icons.laptop_mac,
                            _ => Icons.phone_android,
                          },
                          color: WbColors.waveCyan,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(device.name, style: const TextStyle(fontSize: 16)),
                              if (device.current)
                                Text(
                                  s.thisDevice,
                                  style: const TextStyle(color: WbColors.ice60, fontSize: 12),
                                ),
                            ],
                          ),
                        ),
                        // The current device can't revoke itself — that
                        // would just cut off the session it's using to
                        // look at this very screen. Every other device
                        // can be cleared out (this is also the only way
                        // to get under a plan's device limit once old
                        // installs/reinstalls have piled up).
                        if (!device.current)
                          revoking
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : IconButton(
                                  onPressed: () => _revoke(device.id, device.name),
                                  icon: const Icon(Icons.delete_outline, color: WbColors.error),
                                ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
