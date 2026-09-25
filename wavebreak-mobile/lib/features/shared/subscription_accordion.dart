import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/app_strings.dart';
import '../../core/theme/flag_colors.dart';
import '../../core/theme/wb_colors.dart';
import '../../services/core_api/models.dart';
import '../../services/vpn/connection_test_service.dart';
import 'flag_icon.dart';
import 'share_subscription_sheet.dart';
import 'subscription_section.dart';
import 'wave_params.dart';

/// A Happ-style expandable list: one card per subscription source, each
/// expanding to reveal that source's servers. Used both in the Home quick
/// picker and the full Locations screen.
class SubscriptionAccordion extends StatefulWidget {
  const SubscriptionAccordion({
    super.key,
    required this.sections,
    required this.currentId,
    required this.s,
    required this.onSelect,
    required this.onAddCustom,
    this.onRemove,
    this.onRefresh,
    this.onShare,
    this.onCollapse,
    this.shrinkWrap = false,
  });

  final List<SubscriptionSectionData> sections;
  final String currentId;
  final AppStrings s;
  final ValueChanged<LocationItem> onSelect;
  final VoidCallback onAddCustom;
  final ValueChanged<String>? onRemove;
  final ValueChanged<String>? onRefresh;

  /// Fires when a section that was expanded gets collapsed (tapped again
  /// to close, not just switched to another section) — lets the caller
  /// scroll the page back up so closing a long location list doesn't
  /// leave the view stranded on now-empty space below it.
  final VoidCallback? onCollapse;

  /// When set, share taps call this instead of opening the share sheet
  /// directly — needed when the accordion lives inside another overlay
  /// (the Home dropdown), so that overlay can close first and the caller
  /// can open the share sheet afterwards from a stable context.
  final void Function(String title, String link)? onShare;
  final bool shrinkWrap;

  @override
  State<SubscriptionAccordion> createState() => _SubscriptionAccordionState();
}

class _SubscriptionAccordionState extends State<SubscriptionAccordion> {
  late String? _expanded = sectionIdFor(widget.sections, widget.currentId);

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: widget.shrinkWrap ? MainAxisSize.min : MainAxisSize.max,
      children: [
        for (final section in widget.sections)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _SectionCard(
              section: section,
              expanded: _expanded == section.id,
              currentId: widget.currentId,
              s: widget.s,
              onToggle: () {
                final wasExpanded = _expanded == section.id;
                setState(() => _expanded = wasExpanded ? null : section.id);
                if (wasExpanded) widget.onCollapse?.call();
              },
              onSelect: widget.onSelect,
              onRemove: widget.onRemove,
              onRefresh: widget.onRefresh,
              onShare: widget.onShare,
            ),
          ),
        Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: widget.onAddCustom,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: WbColors.waveCyan.withValues(alpha: 0.35),
                  style: BorderStyle.solid,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.add_circle_outline, color: WbColors.waveCyan, size: 18),
                  const SizedBox(width: 10),
                  Text(
                    widget.s.addSubscriptionLink,
                    style: const TextStyle(
                      color: WbColors.waveCyan,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionCard extends StatefulWidget {
  const _SectionCard({
    required this.section,
    required this.expanded,
    required this.currentId,
    required this.s,
    required this.onToggle,
    required this.onSelect,
    required this.onRemove,
    required this.onRefresh,
    required this.onShare,
  });

  final SubscriptionSectionData section;
  final bool expanded;
  final String currentId;
  final AppStrings s;
  final VoidCallback onToggle;
  final ValueChanged<LocationItem> onSelect;
  final ValueChanged<String>? onRemove;
  final ValueChanged<String>? onRefresh;
  final void Function(String title, String link)? onShare;

  @override
  State<_SectionCard> createState() => _SectionCardState();
}

class _SectionCardState extends State<_SectionCard> {
  static const _pingInterval = Duration(seconds: 25);
  static const _pingService = ConnectionTestService();

  Timer? _pingTimer;
  final Map<String, int?> _livePings = {};

  SubscriptionSectionData get section => widget.section;

  @override
  void initState() {
    super.initState();
    if (widget.expanded) _startPingSweep();
  }

  @override
  void didUpdateWidget(_SectionCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.expanded && !oldWidget.expanded) {
      _startPingSweep();
    } else if (!widget.expanded && oldWidget.expanded) {
      _pingTimer?.cancel();
      _pingTimer = null;
    }
  }

  @override
  void dispose() {
    _pingTimer?.cancel();
    super.dispose();
  }

  // Real WAVEBREAK locations carry Core's connection_test recipe; custom
  // (BYO) servers instead get tested straight against the host/port
  // ConnectionTestService pulls out of their own pasted share link (see
  // its _hostPortFromRawLink) — either way there's a real target to probe,
  // just not for a section the user isn't even looking at.
  void _startPingSweep() {
    _runPingSweep();
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(_pingInterval, (_) => _runPingSweep());
  }

  Future<void> _runPingSweep() async {
    final targets = section.servers
        .where((s) => s.connectionTest != null || (s.isCustom && (s.rawLink ?? '').isNotEmpty))
        .toList();
    if (targets.isEmpty) return;
    final results = await Future.wait(targets.map((s) => _pingService.testLocation(s)));
    if (!mounted) return;
    setState(() {
      for (var i = 0; i < targets.length; i++) {
        _livePings[targets[i].id] = results[i];
      }
    });
  }

  void _share(BuildContext context, String title, String link) {
    if (widget.onShare != null) {
      widget.onShare!(title, link);
    } else {
      showShareSubscriptionSheet(context, title: title, link: link, s: widget.s);
    }
  }

  LocationItem? get _activeServer {
    for (final l in section.servers) {
      if (l.id == widget.currentId) return l;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final active = _activeServer;
    final borderColor = active == null
        ? WbColors.ice08
        : accentColorFor(active.countryCode).withValues(alpha: 0.4);
    // Not a BackdropFilter blur — this card is one of several stacked in
    // the location picker, and a live blur per section is the kind of
    // per-instance GPU cost that stays smooth on a desktop/emulator but
    // turns the whole sheet janky to open/scroll on a real phone.
    return Container(
      decoration: BoxDecoration(
        color: WbColors.card.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.onToggle,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: WbColors.waveCyan.withValues(alpha: 0.12),
                      ),
                      child: Icon(section.icon, color: WbColors.waveCyan, size: 17),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            section.title,
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            section.subtitle,
                            style: const TextStyle(color: WbColors.ice60, fontSize: 12),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    if ((section.canRefresh && widget.onRefresh != null) ||
                        section.shareLink != null ||
                        (section.isCustom && widget.onRemove != null))
                      _SectionMenuButton(
                        s: widget.s,
                        onRefresh: (section.canRefresh && widget.onRefresh != null)
                            ? () => widget.onRefresh!(section.id)
                            : null,
                        onShare: section.shareLink != null
                            ? () => _share(context, section.title, section.shareLink!)
                            : null,
                        onRemove: (section.isCustom && widget.onRemove != null)
                            ? () => widget.onRemove!(section.id)
                            : null,
                      ),
                    const SizedBox(width: 4),
                    AnimatedRotation(
                      turns: widget.expanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: const Icon(Icons.expand_more, color: WbColors.ice60, size: 20),
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            child: widget.expanded
                ? Column(
                    children: [
                      const Divider(height: 1, color: WbColors.ice08),
                      for (final server in section.servers)
                        _ServerRow(
                          server: server,
                          s: widget.s,
                          selected: server.id == widget.currentId,
                          livePingMs: _livePings[server.id],
                          onTap: server.available ? () => widget.onSelect(server) : null,
                          onShare: widget.onShare == null
                              ? null
                              : (title, link) => widget.onShare!(title, link),
                        ),
                    ],
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

class _HeaderIcon extends StatelessWidget {
  const _HeaderIcon({required this.icon, required this.tooltip, required this.onTap});

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: 40,
            height: 40,
            child: Icon(icon, color: WbColors.ice60, size: 18),
          ),
        ),
      ),
    );
  }
}

/// Rolls refresh/share/remove into one clearly separate, comfortably sized
/// tap target instead of a row of small icons squeezed against the
/// section's own expand/collapse area — those tiny targets were easy to
/// miss and would toggle the section instead of doing what was tapped.
class _SectionMenuButton extends StatelessWidget {
  const _SectionMenuButton({
    required this.s,
    this.onRefresh,
    this.onShare,
    this.onRemove,
  });

  final AppStrings s;
  final VoidCallback? onRefresh;
  final VoidCallback? onShare;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    // A one-off read — the popup is short-lived and doesn't need to react
    // to the tint changing while it happens to be open.
    final tint = ProviderScope.containerOf(context).read(appWaveParamsProvider).tint;
    return PopupMenuButton<VoidCallback>(
      tooltip: s.more,
      padding: EdgeInsets.zero,
      // See share_subscription_sheet.dart — without this the floating
      // bottom nav pill can paint over the menu when it opens near the
      // bottom of the screen, since it lives above the branch's nested
      // Navigator, not the root one.
      useRootNavigator: true,
      color: wbBlend(WbColors.deepOcean, tint, 0.16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: tint == null ? WbColors.ice08 : tint.withValues(alpha: 0.25),
        ),
      ),
      itemBuilder: (context) => [
        if (onRefresh != null)
          PopupMenuItem(
            value: onRefresh,
            child: _MenuRow(icon: Icons.refresh_rounded, label: s.refreshServers),
          ),
        if (onShare != null)
          PopupMenuItem(
            value: onShare,
            child: _MenuRow(icon: Icons.ios_share_rounded, label: s.shareSubscription),
          ),
        if (onRemove != null)
          PopupMenuItem(
            value: onRemove,
            child: _MenuRow(icon: Icons.delete_outline, label: s.remove, destructive: true),
          ),
      ],
      onSelected: (callback) => callback(),
      child: const SizedBox(
        width: 40,
        height: 40,
        child: Icon(Icons.more_horiz_rounded, color: WbColors.ice60, size: 22),
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.icon, required this.label, this.destructive = false});

  final IconData icon;
  final String label;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color = destructive ? WbColors.error : WbColors.ice;
    return Row(
      children: [
        Icon(icon, color: color, size: 19),
        const SizedBox(width: 12),
        Text(label, style: TextStyle(color: color, fontSize: 14)),
      ],
    );
  }
}

class _ServerRow extends StatelessWidget {
  const _ServerRow({
    required this.server,
    required this.s,
    required this.selected,
    required this.onTap,
    required this.onShare,
    this.livePingMs,
  });

  final LocationItem server;
  final AppStrings s;
  final bool selected;
  final VoidCallback? onTap;
  final void Function(String title, String link)? onShare;

  /// A real, just-measured reachability figure from _SectionCard's
  /// periodic sweep (see connection_test_service.dart) — real backend
  /// locations never carry a static [LocationItem.pingMs] (Core doesn't
  /// track that server-side at all), so without this the ping column was
  /// silently blank for every real location and only ever populated for
  /// mock/demo data.
  final int? livePingMs;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? WbColors.waveCyan.withValues(alpha: 0.08) : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Opacity(
            opacity: server.available ? 1 : 0.4,
            child: Row(
              children: [
                // A custom link's label can carry a real, decodable flag
                // (see CustomServerController._flagCodeFromLabel) — show
                // it whenever one was found instead of always falling
                // back to a generic link icon just because the server is
                // custom. Only a link with no detectable country still
                // gets the link icon.
                server.isAuto
                    ? const Text('●', style: TextStyle(fontSize: 18))
                    : server.countryCode.isNotEmpty
                        ? FlagIcon(countryCode: server.countryCode, width: 22)
                        : const Icon(Icons.link, color: WbColors.ice60, size: 16),
                const SizedBox(width: 10),
                Expanded(
                  // The flag icon already carries the country, so
                  // repeating it as a text prefix on every single row
                  // ("Netherlands · Amsterdam", "Netherlands ·
                  // Rotterdam", ...) just burns width a group's rows
                  // usually share anyway — confirmed on-device: with a
                  // longer city/note (e.g. "Amsterdam (Direct-TLS)") that
                  // redundant prefix was exactly what pushed the ping
                  // value and action icons out of a narrow phone's width,
                  // or ellipsized the one part of the name that actually
                  // distinguishes the row. City (falling back to country
                  // only when there's no city at all) is the whole label
                  // now.
                  child: Text(
                    server.isAuto ? 'Auto · Fastest' : (server.city.isEmpty ? server.country : server.city),
                    style: const TextStyle(fontSize: 14),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
                if ((livePingMs ?? server.pingMs) != null) ...[
                  const SizedBox(width: 6),
                  Text(
                    '${livePingMs ?? server.pingMs} ms',
                    style: const TextStyle(color: WbColors.ice60, fontSize: 12),
                  ),
                  const SizedBox(width: 8),
                ],
                if (server.isCustom && server.rawLink != null)
                  _HeaderIcon(
                    icon: Icons.ios_share_rounded,
                    tooltip: s.shareSubscription,
                    onTap: () => onShare != null
                        ? onShare!(server.country, server.rawLink!)
                        : showShareSubscriptionSheet(
                            context,
                            title: server.country,
                            link: server.rawLink!,
                            s: s,
                          ),
                  ),
                if (selected)
                  const Icon(Icons.check_circle, color: WbColors.waveCyan, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
