import '../../core/theme/wb_theme.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/app_strings.dart';
import '../../core/theme/wb_colors.dart';
import '../../services/core_api/models.dart';
import '../../services/vpn/connection_test_service.dart';
import '../../services/vpn/server_catalog.dart';
import '../home/location_bar.dart';
import 'flag_icon.dart';
import '../immersive/immersive_colors.dart';
import 'share_subscription_sheet.dart';
import 'wave_params.dart';

/// The server list of the Servers tab: one expandable card per
/// subscription source; inside, one row per place (a city) with its
/// protocols as chips. Built from the server catalog — the same source as
/// the home header's protocol switch.
class SubscriptionAccordion extends StatefulWidget {
  const SubscriptionAccordion({
    super.key,
    required this.sections,
    required this.current,
    required this.s,
    required this.onSelect,
    required this.onAddCustom,
    this.onRemove,
    this.onRefresh,
    this.onCollapse,
    this.shrinkWrap = false,
  });

  final List<ServerSection> sections;
  final LocationItem current;
  final AppStrings s;
  final ValueChanged<LocationItem> onSelect;
  final VoidCallback onAddCustom;
  final ValueChanged<String>? onRemove;
  final ValueChanged<String>? onRefresh;

  /// Fires when an expanded section gets collapsed — lets the caller
  /// scroll back up so closing a long list doesn't strand the view.
  final VoidCallback? onCollapse;
  final bool shrinkWrap;

  @override
  State<SubscriptionAccordion> createState() => _SubscriptionAccordionState();
}

class _SubscriptionAccordionState extends State<SubscriptionAccordion> {
  late String? _expanded = _sectionOfCurrent();

  String? _sectionOfCurrent() {
    final place = placeOf(widget.current, widget.sections);
    if (place != null) return place.sectionId;
    return widget.sections.isEmpty ? null : widget.sections.first.data.id;
  }

  @override
  Widget build(BuildContext context) {
    final currentPlace = placeOf(widget.current, widget.sections);
    return Column(
      mainAxisSize: widget.shrinkWrap ? MainAxisSize.min : MainAxisSize.max,
      children: [
        for (final section in widget.sections)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _SectionCard(
              section: section,
              expanded: _expanded == section.data.id,
              current: widget.current,
              currentPlaceKey: currentPlace?.key,
              s: widget.s,
              onToggle: () {
                final wasExpanded = _expanded == section.data.id;
                setState(() => _expanded = wasExpanded ? null : section.data.id);
                if (wasExpanded) widget.onCollapse?.call();
              },
              onSelect: widget.onSelect,
              onRemove: widget.onRemove,
              onRefresh: widget.onRefresh,
            ),
          ),
        Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: widget.onAddCustom,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Ic.glassBorder),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_circle_outline, color: context.accent, size: 18),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      widget.s.addSubscriptionLink,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Ic.text,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
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
    required this.current,
    required this.currentPlaceKey,
    required this.s,
    required this.onToggle,
    required this.onSelect,
    required this.onRemove,
    required this.onRefresh,
  });

  final ServerSection section;
  final bool expanded;
  final LocationItem current;
  final String? currentPlaceKey;
  final AppStrings s;
  final VoidCallback onToggle;
  final ValueChanged<LocationItem> onSelect;
  final ValueChanged<String>? onRemove;
  final ValueChanged<String>? onRefresh;

  @override
  State<_SectionCard> createState() => _SectionCardState();
}

class _SectionCardState extends State<_SectionCard> {
  static const _pingInterval = Duration(seconds: 25);
  static const _pingService = ConnectionTestService();

  Timer? _pingTimer;
  final Map<String, int?> _livePings = {};

  ServerSection get section => widget.section;

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

  void _startPingSweep() {
    _runPingSweep();
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(_pingInterval, (_) => _runPingSweep());
  }

  // Core's connection_test recipe for WAVEBREAK entries, the share link's
  // host/port for the user's own; the selected one through the tunnel when
  // it is up (works for Hysteria2 too).
  Future<void> _runPingSweep() async {
    final targets = [
      for (final p in section.places)
        for (final v in p.variants)
          if (v.connectionTest != null ||
              (v.isCustom && (v.rawLink ?? '').isNotEmpty))
            v,
    ];
    if (targets.isEmpty) return;
    Future<int?> ping(LocationItem s) async {
      if (s.id == widget.current.id) {
        final viaTunnel = await _pingService.measureTunnelLatency();
        if (viaTunnel != null) return viaTunnel;
      }
      return _pingService.testLocation(s);
    }

    final results = await Future.wait(targets.map(ping));
    if (!mounted) return;
    setState(() {
      for (var i = 0; i < targets.length; i++) {
        _livePings[targets[i].id] = results[i];
      }
    });
  }

  void _share(BuildContext context, String title, String link) {
    showShareSubscriptionSheet(context, title: title, link: link, s: widget.s);
  }

  @override
  Widget build(BuildContext context) {
    final data = section.data;
    final hasCurrent =
        section.places.any((p) => p.key == widget.currentPlaceKey);
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Ic.glassTop, Ic.glassMid, Ic.glassBottom],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: hasCurrent
              ? context.brand.withValues(alpha: 0.30)
              : Ic.glassBorder,
        ),
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
                        color: Ic.text.withValues(alpha: 0.06),
                      ),
                      child: Icon(data.icon, color: Ic.textSecondary, size: 17),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            data.title,
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            '${section.places.length} ${widget.s.locationsWord}',
                            style: const TextStyle(color: WbColors.ice60, fontSize: 12),
                            overflow: TextOverflow.ellipsis,
                          ),
                          // Traffic and devices of this subscription — the
                          // owner's own limits for a shared one — or a note.
                          if (data.limitsNote != null)
                            Text(
                              data.limitsNote!,
                              style: const TextStyle(color: WbColors.warning, fontSize: 12),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            )
                          else if (data.limitsTraffic != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 1),
                              child: Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      data.limitsTraffic!,
                                      style: const TextStyle(color: WbColors.ice60, fontSize: 12),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (data.limitsDevices != null) ...[
                                    const SizedBox(width: 8),
                                    const Icon(Icons.devices_rounded,
                                        color: WbColors.ice60, size: 12),
                                    const SizedBox(width: 3),
                                    Text(
                                      data.limitsDevices!,
                                      style: const TextStyle(color: WbColors.ice60, fontSize: 12),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                    if ((data.canRefresh && widget.onRefresh != null) ||
                        data.shareLink != null ||
                        (data.isCustom && widget.onRemove != null))
                      _SectionMenuButton(
                        s: widget.s,
                        onRefresh: (data.canRefresh && widget.onRefresh != null)
                            ? () => widget.onRefresh!(data.id)
                            : null,
                        onShare: data.shareLink != null
                            ? () => _share(context, data.title, data.shareLink!)
                            : null,
                        onRemove: (data.isCustom && widget.onRemove != null)
                            ? () => widget.onRemove!(data.id)
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
                      for (final place in section.places)
                        _PlaceRow(
                          place: place,
                          s: widget.s,
                          current: widget.current,
                          selected: place.key == widget.currentPlaceKey,
                          livePings: _livePings,
                          onSelect: widget.onSelect,
                          shareable: data.shareable,
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


/// One place: flag, city, country (and the protocol when it has only one),
/// ping, and — with several protocols — a chip per protocol. Tapping the
/// row picks the place keeping the current protocol when it has it;
/// a chip picks that protocol.
class _PlaceRow extends StatelessWidget {
  const _PlaceRow({
    required this.place,
    required this.s,
    required this.current,
    required this.selected,
    required this.livePings,
    required this.onSelect,
    this.shareable = true,
  });

  final ServerPlace place;
  final AppStrings s;
  final LocationItem current;
  final bool selected;
  final Map<String, int?> livePings;
  final ValueChanged<LocationItem> onSelect;

  /// False for a section redeemed from someone else's share code.
  final bool shareable;

  LocationItem get _rowTarget =>
      place.variant(protocolLabel(current)) ?? place.primary;

  @override
  Widget build(BuildContext context) {
    final currentProto = protocolLabel(current);
    final shown = selected ? (place.variant(currentProto) ?? place.primary) : _rowTarget;
    final ping = livePings[shown.id] ?? shown.pingMs;
    final available = place.variants.any((v) => v.available);
    final single = place.variants.length == 1;
    final singleProto = single ? protocolLabel(place.primary) : null;
    final subtitle = [
      if (place.title != place.country) place.country,
      if (singleProto != null) singleProto,
      // A node of a third-party subscription this engine can't run.
      if (!available && place.primary.isCustom) s.notSupportedMark,
    ].join(' · ');
    final shareTarget = shown.isCustom && shown.rawLink != null && shareable
        ? shown.rawLink
        : null;

    return Material(
      color: selected ? context.brand.withValues(alpha: 0.08) : Colors.transparent,
      child: InkWell(
        onTap: available && !(selected && single) ? () => onSelect(_rowTarget) : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
          child: Opacity(
            opacity: available ? 1 : 0.4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    place.countryCode.isNotEmpty
                        ? FlagIcon(countryCode: place.countryCode, width: 22)
                        : const Icon(Icons.link, color: WbColors.ice60, size: 16),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            place.title,
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                          if (subtitle.isNotEmpty)
                            Text(
                              subtitle,
                              style: const TextStyle(color: WbColors.ice60, fontSize: 12),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                        ],
                      ),
                    ),
                    if (ping != null) ...[
                      const SizedBox(width: 6),
                      Text(
                        '$ping ms',
                        style: const TextStyle(color: WbColors.ice60, fontSize: 12),
                      ),
                    ],
                    if (shareTarget != null)
                      _HeaderIcon(
                        icon: Icons.ios_share_rounded,
                        tooltip: s.shareSubscription,
                        onTap: () => showShareSubscriptionSheet(
                          context,
                          title: place.title,
                          link: shareTarget,
                          s: s,
                        ),
                      ),
                    SizedBox(
                      width: 28,
                      child: selected
                          ? Icon(Icons.check_circle, color: context.accent, size: 18)
                          : null,
                    ),
                  ],
                ),
                if (!single) ...[
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.only(left: 32),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final v in place.variants)
                          _ProtocolChip(
                            label: protocolLabel(v) ?? '—',
                            selected: selected && protocolLabel(v) == currentProto,
                            onTap: v.available &&
                                    !(selected && protocolLabel(v) == currentProto)
                                ? () => onSelect(v)
                                : null,
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProtocolChip extends StatelessWidget {
  const _ProtocolChip({required this.label, required this.selected, this.onTap});

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(9),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(9),
            color: selected ? context.brand.withValues(alpha: 0.16) : null,
            border: Border.all(
              color: selected ? context.brand.withValues(alpha: 0.45) : Ic.glassBorder,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: selected ? Ic.text : Ic.textMuted,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}
