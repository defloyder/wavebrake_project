import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/i18n/app_strings.dart';
import '../../core/theme/wb_colors.dart';
import 'wave_params.dart';

Future<void> showShareSubscriptionSheet(
  BuildContext context, {
  required String title,
  required String link,
  required AppStrings s,
}) {
  final isDesktop = MediaQuery.sizeOf(context).width >= 820;
  // A one-off read, not a watch — this sheet is short-lived and doesn't
  // need to react to the tint changing while it happens to be open.
  final tint = ProviderScope.containerOf(context).read(appWaveParamsProvider).tint;
  final borderColor = tint == null ? WbColors.ice08 : tint.withValues(alpha: 0.28);

  // A bottom sheet reads fine on a phone-sized viewport (it's anchored to
  // where a thumb naturally reaches), but on a wide desktop window it just
  // hugs the bottom edge with a huge dead gap above it — nowhere near
  // "centered". A proper centered dialog is the desktop-appropriate
  // equivalent of the same content.
  if (isDesktop) {
    return showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: wbBlend(WbColors.card, tint, 0.12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: borderColor),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _TitleAndQr(title: title, link: link),
                const SizedBox(height: 24),
                _CopyLinkPill(link: link, s: s, tint: tint),
              ],
            ),
          ),
        ),
      ),
    );
  }

  return showModalBottomSheet<void>(
    context: context,
    // The floating bottom nav pill paints on top of whatever the *branch's*
    // own nested Navigator shows, so a sheet opened the normal way ends up
    // rendered behind it near the bottom edge. Routing it through the root
    // Navigator instead puts it above the whole app shell, pill included.
    useRootNavigator: true,
    isScrollControlled: true,
    // Transparent sheet background — the card below draws its own
    // rounded-all-corners, margined shape instead of a panel glued edge
    // to edge across the whole screen width.
    backgroundColor: Colors.transparent,
    builder: (context) {
      // A fixed share of the screen height, not content-driven sizing —
      // that's what lets the QR sit near the vertical center of the card
      // instead of being squeezed up against whichever edge the content
      // happens to reach first, and keeps the copy button a fixed,
      // predictable distance from the bottom instead of wherever the
      // content's natural height happens to end.
      final cardHeight = (MediaQuery.sizeOf(context).height * 0.6).clamp(420.0, 580.0);
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Container(
            height: cardHeight,
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
            decoration: BoxDecoration(
              color: wbBlend(WbColors.card, tint, 0.12),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: borderColor),
            ),
            child: Column(
              children: [
                // A drag handle at the top signals this can be dismissed
                // by dragging down or tapping outside — for anyone who
                // doesn't immediately realize how to close it.
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: WbColors.ice08,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                Expanded(child: Center(child: _TitleAndQr(title: title, link: link))),
                const SizedBox(height: 20),
                _CopyLinkPill(link: link, s: s, tint: tint),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _TitleAndQr extends StatelessWidget {
  const _TitleAndQr({required this.title, required this.link});

  final String title;
  final String link;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 24),
        // Just the QR itself — no extra card/frame behind it. The white
        // square is the code's own required quiet zone, not a decorative
        // background block.
        QrImageView(
          data: link,
          size: 240,
          backgroundColor: Colors.white,
          eyeStyle: const QrEyeStyle(
            eyeShape: QrEyeShape.square,
            color: WbColors.midnight,
          ),
          dataModuleStyle: const QrDataModuleStyle(
            dataModuleShape: QrDataModuleShape.square,
            color: WbColors.midnight,
          ),
        ),
      ],
    );
  }
}

class _CopyLinkPill extends StatelessWidget {
  const _CopyLinkPill({required this.link, required this.s, this.tint});

  final String link;
  final AppStrings s;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final borderColor = tint == null ? WbColors.ice08 : tint!.withValues(alpha: 0.3);
    // Small, quiet pill — present without competing visually with the QR
    // code above it, and never glued to the sheet's own bottom edge.
    return Center(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: () async {
            await Clipboard.setData(ClipboardData(text: link));
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(s.linkCopied)),
              );
            }
          },
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: borderColor),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.copy_rounded, size: 16, color: WbColors.ice60),
                const SizedBox(width: 8),
                Text(
                  s.copyLink,
                  style: const TextStyle(
                    color: WbColors.ice60,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
