import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../core/i18n/language_controller.dart';
import '../../core/theme/wb_colors.dart';
import '../../services/custom_servers/custom_server_controller.dart';
import '../../services/vpn/connection_manager.dart';
import '../../services/vpn/server_catalog.dart';
import '../shared/add_custom_server_sheet.dart';
import '../shared/confirm_dialogs.dart';
import '../shared/data_providers.dart';
import '../shared/subscription_accordion.dart';
import '../shared/wave_params.dart';

/// The server list (sections, places, protocols) — the Servers tab and
/// the pop-up from Home's location header show this same widget.
class ServersList extends ConsumerWidget {
  const ServersList({
    super.key,
    this.controller,
    this.bottomPadding = 16,
    this.onPicked,
    this.header,
  });

  final ScrollController? controller;
  final double bottomPadding;

  /// After a server was chosen (the pop-up closes itself here).
  final VoidCallback? onPicked;

  /// Above the list, scrolling with it (the Servers tab's title: with the
  /// list anchored to the bottom it sits right on top of it).
  final Widget? header;

  Widget _withHeader(Widget body) => header == null
      ? body
      : Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [header!, Expanded(child: body)],
        );
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(connectionManagerProvider).location;
    final locations = ref.watch(locationsProvider);
    final s = ref.watch(stringsProvider);
    final canConnect = ref.watch(canConnectProvider);
    return locations.when(
      loading: () =>
          _withHeader(const Center(child: CircularProgressIndicator())),
      error: (error, _) => _withHeader(Center(
        child: Text(
          error is AppException ? error.localized(s) : s.errUnavailable,
          textAlign: TextAlign.center,
        ),
      )),
      data: (_) {
        final sections = ref.watch(serverCatalogProvider);
        return SingleChildScrollView(
          // Anchored to the bottom, near the thumb (owner, 06.10): a short
          // list sits right above the nav bar, a long one opens at its
          // end ("add your link") and scrolls up.
          reverse: true,
          controller: controller,
          padding: EdgeInsets.only(bottom: bottomPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (header != null) header!,
              SubscriptionAccordion(
                sections: sections,
                current: selected,
                s: s,
                shrinkWrap: true,
                onSelect: (item) {
                  ref
                      .read(connectionManagerProvider.notifier)
                      .selectLocation(item, subscriptionActive: canConnect);
                  onPicked?.call();
                },
                onAddCustom: () => showAddCustomServerSheet(context, ref),
                onRemove: (id) async {
                  if (!await confirmRemoveCustomGroup(context, s)) return;
                  // removeGroup() alone never reaches ConnectionManager: a
                  // tunnel running on a just-deleted server would keep going
                  // with nothing left in the UI to disconnect it from.
                  final connection = ref.read(connectionManagerProvider);
                  final matches =
                      ref.read(customServersProvider).where((g) => g.id == id);
                  final group = matches.isEmpty ? null : matches.first;
                  final connectedToThisGroup = group != null &&
                      connection.status != ConnectionStatus.idle &&
                      group.servers
                          .any((server) => server.id == connection.location.id);
                  ref.read(customServersProvider.notifier).removeGroup(id);
                  if (connectedToThisGroup) {
                    await ref
                        .read(connectionManagerProvider.notifier)
                        .disconnect();
                  }
                },
                onRefresh: (id) =>
                    ref.read(customServersProvider.notifier).refreshGroup(id),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// The server list as a pop-up over Home (owner, 06.10: tapping the
/// location on Home used to jump to the Servers tab; before that it was a
/// pop-up, which is what they want). Every subscription is in it, the list
/// scrolls inside, and a swipe doesn't close it — scrolling a long list
/// used to drag the sheet away. Closes with ✕, a tap outside, back, or
/// picking a server.
Future<void> showServersSheet(BuildContext context, WidgetRef ref) {
  final s = ref.read(stringsProvider);
  final tint = ref.read(appWaveParamsProvider).tint;
  return showModalBottomSheet<void>(
    context: context,
    // Above the floating bottom bar (it paints over the branch navigator).
    useRootNavigator: true,
    isScrollControlled: true,
    enableDrag: false,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) {
      final media = MediaQuery.of(sheetContext);
      return SafeArea(
        child: Container(
          constraints: BoxConstraints(maxHeight: media.size.height * 0.88),
          margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
          decoration: BoxDecoration(
            color: wbBlend(WbColors.card, tint, WbColors.sheetLean),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
                color: tint == null
                    ? WbColors.ice08
                    : tint.withValues(alpha: 0.28)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      s.chooseLocation,
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.w600),
                    ),
                  ),
                  IconButton(
                    tooltip: s.refreshServers,
                    onPressed: () => ref.invalidate(locationsProvider),
                    icon: const Icon(Icons.refresh_rounded,
                        color: WbColors.ice60),
                  ),
                  IconButton(
                    tooltip: MaterialLocalizations.of(sheetContext)
                        .closeButtonTooltip,
                    onPressed: () => Navigator.of(sheetContext).pop(),
                    icon:
                        const Icon(Icons.close_rounded, color: WbColors.ice60),
                  ),
                ],
              ),
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ServersList(
                    bottomPadding: 16,
                    onPicked: () => Navigator.of(sheetContext).pop(),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
