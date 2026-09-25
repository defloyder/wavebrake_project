import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/app_strings.dart';
import '../../core/theme/wb_colors.dart';
import '../../services/core_api/models.dart';
import 'location_picker_result.dart';
import 'subscription_accordion.dart';
import 'subscription_section.dart';
import 'wave_params.dart';

/// Shows an anchored, animated dropdown (scale + fade) listing [sections]
/// as an expandable Happ-style accordion, with [current] checked.
///
/// Resolves with a [LocationPickerResult] describing what the user did, or
/// null if dismissed without a choice. Actions that need their own
/// dialog/sheet (share, add-link) are reported as data on the result — the
/// caller must open them only *after* this dropdown has fully closed, using
/// its own stable context, since stacking a second overlay while this one
/// is still animating out races its removal.
Future<LocationPickerResult?> showLocationDropdown({
  required BuildContext context,
  required LayerLink link,
  required List<SubscriptionSectionData> sections,
  required LocationItem current,
  required AppStrings s,
  required ValueChanged<String> onRemoveCustom,
  required ValueChanged<String> onRefreshCustom,
}) {
  final overlay = Overlay.of(context);
  final completer = _DropdownCompleter<LocationPickerResult?>();
  // A one-off read, not a watch — this overlay is short-lived and doesn't
  // need to react to the tint changing while it happens to be open.
  final tint = ProviderScope.containerOf(context).read(appWaveParamsProvider).tint;
  late OverlayEntry entry;

  entry = OverlayEntry(
    builder: (context) {
      return _DropdownRoute(
        link: link,
        sections: sections,
        current: current,
        s: s,
        tint: tint,
        onRemoveCustom: onRemoveCustom,
        onRefreshCustom: onRefreshCustom,
        onDismiss: (value) {
          entry.remove();
          completer.complete(value);
        },
      );
    },
  );

  overlay.insert(entry);
  return completer.future;
}

/// Mobile equivalent of [showLocationDropdown] — a bottom sheet instead of
/// a dropdown anchored under the location header. The header sits near the
/// top of the screen; a sheet that slides up from the bottom keeps the
/// actual picking (the part someone repeats over and over) within thumb
/// reach instead of requiring a stretch to the top every time.
Future<LocationPickerResult?> showLocationSheet({
  required BuildContext context,
  required List<SubscriptionSectionData> sections,
  required LocationItem current,
  required AppStrings s,
  required ValueChanged<String> onRemoveCustom,
  required ValueChanged<String> onRefreshCustom,
}) {
  final tint = ProviderScope.containerOf(context).read(appWaveParamsProvider).tint;
  return showModalBottomSheet<LocationPickerResult?>(
    context: context,
    // See share_subscription_sheet.dart — without this the floating bottom
    // nav pill paints over the sheet's own bottom edge since it lives above
    // the branch's nested Navigator, not the root one.
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: wbBlend(WbColors.deepOcean, tint, 0.14),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) {
      return SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 10,
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 16,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(sheetContext).size.height * 0.78,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: WbColors.ice08,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    child: SubscriptionAccordion(
                      sections: sections,
                      currentId: current.id,
                      s: s,
                      shrinkWrap: true,
                      onSelect: (item) =>
                          Navigator.of(sheetContext).pop(LocationPickerResult.select(item)),
                      onAddCustom: () =>
                          Navigator.of(sheetContext).pop(const LocationPickerResult.addCustom()),
                      onShare: (title, link) => Navigator.of(sheetContext)
                          .pop(LocationPickerResult.share(title: title, link: link)),
                      onRemove: onRemoveCustom,
                      onRefresh: onRefreshCustom,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _DropdownCompleter<T> {
  final _completer = Completer<T>();
  Future<T> get future => _completer.future;
  void complete(T value) {
    if (!_completer.isCompleted) _completer.complete(value);
  }
}

class _DropdownRoute extends StatefulWidget {
  const _DropdownRoute({
    required this.link,
    required this.sections,
    required this.current,
    required this.s,
    required this.onRemoveCustom,
    required this.onRefreshCustom,
    required this.onDismiss,
    this.tint,
  });

  final LayerLink link;
  final List<SubscriptionSectionData> sections;
  final LocationItem current;
  final AppStrings s;
  final ValueChanged<String> onRemoveCustom;
  final ValueChanged<String> onRefreshCustom;
  final ValueChanged<LocationPickerResult?> onDismiss;
  final Color? tint;

  @override
  State<_DropdownRoute> createState() => _DropdownRouteState();
}

class _DropdownRouteState extends State<_DropdownRoute>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
    reverseDuration: const Duration(milliseconds: 160),
  )..forward();

  bool _closing = false;

  Future<void> _close([LocationPickerResult? value]) async {
    if (_closing) return;
    _closing = true;
    await _controller.reverse();
    widget.onDismiss(value);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _close(),
            child: FadeTransition(
              opacity: curved,
              child: Container(color: Colors.black.withValues(alpha: 0.35)),
            ),
          ),
        ),
        CompositedTransformFollower(
          link: widget.link,
          showWhenUnlinked: false,
          targetAnchor: Alignment.bottomCenter,
          followerAnchor: Alignment.topCenter,
          offset: const Offset(0, 12),
          child: Align(
            alignment: Alignment.topCenter,
            child: FadeTransition(
              opacity: curved,
              child: ScaleTransition(
                scale: Tween(begin: 0.94, end: 1.0).animate(curved),
                alignment: Alignment.topCenter,
                child: Material(
                  color: Colors.transparent,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 360, minWidth: 280),
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 20),
                      padding: const EdgeInsets.all(10),
                      constraints: const BoxConstraints(maxHeight: 480),
                      decoration: BoxDecoration(
                        color: wbBlend(WbColors.deepOcean, widget.tint, 0.14),
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                          color: widget.tint == null
                              ? WbColors.ice08
                              : widget.tint!.withValues(alpha: 0.28),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.45),
                            blurRadius: 28,
                            offset: const Offset(0, 14),
                          ),
                        ],
                      ),
                      child: SingleChildScrollView(
                        child: SubscriptionAccordion(
                          sections: widget.sections,
                          currentId: widget.current.id,
                          s: widget.s,
                          shrinkWrap: true,
                          onSelect: (item) => _close(LocationPickerResult.select(item)),
                          onAddCustom: () => _close(const LocationPickerResult.addCustom()),
                          onShare: (title, link) =>
                              _close(LocationPickerResult.share(title: title, link: link)),
                          onRemove: widget.onRemoveCustom,
                          onRefresh: widget.onRefreshCustom,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
