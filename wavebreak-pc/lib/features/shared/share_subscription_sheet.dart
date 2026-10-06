import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/errors/app_exception.dart';
import '../../core/i18n/app_strings.dart';
import '../../core/theme/wb_colors.dart';
import '../../services/core_api/models.dart';
import '../../services/providers.dart';
import 'subscription_section.dart';
import 'toast.dart';
import 'traffic_format.dart';
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
  final tint =
      ProviderScope.containerOf(context).read(appWaveParamsProvider).tint;
  final borderColor =
      tint == null ? WbColors.ice08 : tint.withValues(alpha: 0.28);
  // WAVEBREAK's own subscription: the QR is a fresh share code from Core
  // (bugs 11, 15), never a fixed link.
  final personal = link == kPersonalShareLink;

  // A bottom sheet reads fine on a phone-sized viewport (it's anchored to
  // where a thumb naturally reaches), but on a wide desktop window it just
  // hugs the bottom edge with a huge dead gap above it — nowhere near
  // "centered". A proper centered dialog is the desktop-appropriate
  // equivalent of the same content.
  if (isDesktop) {
    return showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: wbBlend(WbColors.card, tint, WbColors.sheetLean),
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
                if (personal)
                  _PersonalShareBody(
                      title: title, s: s, tint: tint, expand: false)
                else ...[
                  _TitleAndQr(title: title, link: link),
                  const SizedBox(height: 24),
                  _CopyLinkPill(link: link, s: s, tint: tint),
                ],
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
      final cardHeight =
          (MediaQuery.sizeOf(context).height * 0.6).clamp(420.0, 580.0);
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Container(
            height: cardHeight,
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
            decoration: BoxDecoration(
              color: wbBlend(WbColors.card, tint, WbColors.sheetLean),
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
                if (personal)
                  Expanded(
                    child: _PersonalShareBody(
                        title: title, s: s, tint: tint, expand: true),
                  )
                else ...[
                  Expanded(
                      child:
                          Center(child: _TitleAndQr(title: title, link: link))),
                  const SizedBox(height: 20),
                  _CopyLinkPill(link: link, s: s, tint: tint),
                ],
              ],
            ),
          ),
        ),
      );
    },
  );
}

/// The account's own subscription: asks Core for a fresh share code and
/// shows it with the limits everyone scanning it will share. A code names
/// only the owner; each scan takes one of the owner's device slots.
class _PersonalShareBody extends StatefulWidget {
  const _PersonalShareBody({
    required this.title,
    required this.s,
    required this.tint,
    required this.expand,
  });

  final String title;
  final AppStrings s;
  final Color? tint;

  /// Fill the phone sheet's fixed-height card (copy button pinned to the
  /// bottom) rather than sizing to content as the desktop dialog does.
  final bool expand;

  @override
  State<_PersonalShareBody> createState() => _PersonalShareBodyState();
}

class _PersonalShareBodyState extends State<_PersonalShareBody> {
  late Future<ShareInfo> _share = _load();

  Future<ShareInfo> _load() => ProviderScope.containerOf(context, listen: false)
      .read(coreGatewayProvider)
      .myShare();

  String _errorText(Object error) {
    final s = widget.s;
    if (error is AppException) {
      if (error.statusCode == 404 || error.statusCode == 422) {
        return s.shareNoSubscription;
      }
      return error.localized(s);
    }
    return s.errUnavailable;
  }

  List<Widget> _limits(ShareInfo info) {
    final s = widget.s;
    const style = TextStyle(color: WbColors.ice60, fontSize: 13);
    return [
      if (info.deviceLimit != null)
        Text(
          s.shareDevices
              .replaceAll('{used}', '${info.devicesUsed}')
              .replaceAll('{limit}', '${info.deviceLimit}'),
          style: style,
        ),
      const SizedBox(height: 4),
      Text(
        info.trafficLimitBytes == null
            ? s.shareTrafficUnlimited
            : s.shareTraffic
                .replaceAll('{used}', formatBytes(info.trafficUsedBytes, s))
                .replaceAll('{limit}', formatBytes(info.trafficLimitBytes!, s)),
        style: style,
      ),
      if (info.slotsFull) ...[
        const SizedBox(height: 8),
        Text(
          s.shareAllSlotsTaken,
          textAlign: TextAlign.center,
          style: const TextStyle(color: WbColors.warning, fontSize: 13),
        ),
      ],
      const SizedBox(height: 8),
      Text(
        s.shareScanHint,
        textAlign: TextAlign.center,
        style: const TextStyle(color: WbColors.ice60, fontSize: 12),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    return FutureBuilder<ShareInfo>(
      future: _share,
      builder: (context, snapshot) {
        final Widget content;
        ShareInfo? info;
        if (snapshot.connectionState != ConnectionState.done) {
          content = const SizedBox(
            height: 240,
            child: Center(child: CircularProgressIndicator()),
          );
        } else if (snapshot.hasError ||
            (snapshot.data?.shareUrl.isEmpty ?? true)) {
          content = Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.title,
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 24),
              Text(
                snapshot.hasError
                    ? _errorText(snapshot.error!)
                    : s.errUnavailable,
                textAlign: TextAlign.center,
                style: const TextStyle(color: WbColors.ice60),
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () => setState(() => _share = _load()),
                child: Text(s.tryAgain),
              ),
            ],
          );
        } else {
          info = snapshot.data!;
          content = Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _TitleAndQr(title: widget.title, link: info.shareUrl),
              const SizedBox(height: 16),
              ..._limits(info),
            ],
          );
        }
        final pill = info == null
            ? const SizedBox.shrink()
            : _CopyLinkPill(link: info.shareUrl, s: s, tint: widget.tint);
        if (!widget.expand) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              content,
              if (info != null) ...[const SizedBox(height: 20), pill]
            ],
          );
        }
        return Column(
          children: [
            Expanded(
              child: Center(child: SingleChildScrollView(child: content)),
            ),
            if (info != null) ...[const SizedBox(height: 16), pill],
          ],
        );
      },
    );
  }
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
          data: publicSubscriptionLink(link),
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

/// "Copy link" and "Share" side by side under the QR. Share opens the
/// system sheet — any messenger, mail, notes (owner, 06.10).
class _CopyLinkPill extends StatelessWidget {
  const _CopyLinkPill({required this.link, required this.s, this.tint});

  final String link;
  final AppStrings s;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final borderColor =
        tint == null ? WbColors.ice08 : tint!.withValues(alpha: 0.3);
    final shared = publicSubscriptionLink(link);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Flexible(
          child: _Pill(
            icon: Icons.copy_rounded,
            label: s.copyLink,
            borderColor: borderColor,
            onTap: () async {
              await Clipboard.setData(ClipboardData(text: shared));
              if (context.mounted) {
                showToast(ScaffoldMessenger.of(context), s.linkCopied);
              }
            },
          ),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: _Pill(
            icon: Icons.ios_share_rounded,
            label: s.shareSubscription,
            borderColor: borderColor,
            onTap: () {
              final box = context.findRenderObject() as RenderBox?;
              Share.share(
                shared,
                sharePositionOrigin: box == null
                    ? null
                    : box.localToGlobal(Offset.zero) & box.size,
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Small, quiet pill — present without competing with the QR above it.
class _Pill extends StatelessWidget {
  const _Pill({
    required this.icon,
    required this.label,
    required this.borderColor,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color borderColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: WbColors.ice60),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: WbColors.ice60,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// WAVEBREAK subscription links go out on core.wavebreak.com.tr: api. is
/// behind Cloudflare, which mobile networks in Russia often cut — a third-
/// party client (Happ) then got an error page instead of the subscription.
/// Same path, same content on both hosts.
String publicSubscriptionLink(String link) {
  final uri = Uri.tryParse(link.trim());
  if (uri == null || uri.host.toLowerCase() != 'api.wavebreak.com.tr') {
    return link.trim();
  }
  return uri.replace(host: 'core.wavebreak.com.tr').toString();
}
