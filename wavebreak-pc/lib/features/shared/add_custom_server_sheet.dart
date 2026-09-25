import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/language_controller.dart';
import '../../core/theme/wb_colors.dart';
import '../../services/custom_servers/custom_server_controller.dart';
import 'qr_scan_screen.dart';
import 'wave_params.dart';

Future<void> showAddCustomServerSheet(BuildContext context, WidgetRef ref) async {
  final controller = TextEditingController();
  final s = ref.read(stringsProvider);
  final tint = ref.read(appWaveParamsProvider).tint;
  final scanColor = wbBlend(WbColors.waveCyan, tint, 0.4);
  String? error;
  bool busy = false;

  await showModalBottomSheet<void>(
    context: context,
    // See share_subscription_sheet.dart — without this the floating bottom
    // nav pill paints over the sheet's own bottom edge (the Add button)
    // since it lives above the branch's nested Navigator, not the root one.
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: wbBlend(WbColors.card, tint, 0.12),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {
          Future<void> submit() async {
            if (controller.text.trim().isEmpty) return;
            setState(() {
              busy = true;
              error = null;
            });
            final result =
                await ref.read(customServersProvider.notifier).addFromLink(controller.text);
            setState(() => busy = false);
            if (result == null) {
              if (context.mounted) Navigator.pop(context);
              return;
            }
            setState(() {
              error = switch (result) {
                'blocked' => s.blockedSubscriptionLink,
                'unreachable' => s.errUnavailable,
                'empty' => s.invalidSubscriptionLink,
                _ => s.invalidSubscriptionLink,
              };
            });
          }

          return Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 10,
              bottom: MediaQuery.of(context).viewInsets.bottom + 20,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: WbColors.ice08,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                Text(
                  s.addSubscriptionLink,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                Text(
                  s.addSubscriptionLinkHint,
                  style: const TextStyle(color: WbColors.ice60, fontSize: 13),
                ),
                const SizedBox(height: 18),
                // Scanning is the fastest path on a phone, so it leads and
                // gets the filled/emphasized treatment; pasting a link is
                // the secondary, outlined option next to it.
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 52,
                        child: FilledButton.icon(
                          onPressed: () async {
                            final scanned = await Navigator.of(context).push<String>(
                              MaterialPageRoute(builder: (_) => QrScanScreen(s: s)),
                            );
                            if (scanned != null) controller.text = scanned;
                          },
                          style: FilledButton.styleFrom(
                            backgroundColor: scanColor.withValues(alpha: 0.16),
                            foregroundColor: scanColor,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: BorderSide(color: scanColor.withValues(alpha: 0.35)),
                            ),
                          ),
                          icon: const Icon(Icons.qr_code_scanner_rounded, size: 19),
                          label: Text(
                            s.qrCode,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: SizedBox(
                        height: 52,
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final data = await Clipboard.getData('text/plain');
                            if (data?.text != null) {
                              controller.text = data!.text!.trim();
                            }
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: WbColors.ice,
                            side: const BorderSide(color: WbColors.ice08),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          icon: const Icon(Icons.content_paste_rounded, size: 18),
                          label: Text(s.pasteFromClipboard),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: controller,
                  autofocus: true,
                  minLines: 1,
                  maxLines: 3,
                  style: const TextStyle(fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'https://... · vless:// · trojan://',
                    errorText: error,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: WbColors.waveCyan,
                      foregroundColor: WbColors.midnight,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onPressed: busy ? null : submit,
                    child: busy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            s.addSubscription,
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                          ),
                  ),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}
