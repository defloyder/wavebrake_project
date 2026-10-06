import '../../core/theme/wb_theme.dart';
import 'package:flutter/material.dart';

import '../../core/i18n/app_strings.dart';
import '../../services/core_api/models.dart';
import '../immersive/immersive_colors.dart';
import '../immersive/tinted_glass.dart';
import '../shared/flag_icon.dart';

final _paren = RegExp(r'^(.*?)\s*\(([^)]+)\)\s*$');

/// "Istanbul (Direct-TLS)" → ("Istanbul", "Direct-TLS").
(String, String?) splitPlaceAndProtocol(String city) {
  final m = _paren.firstMatch(city);
  if (m == null) return (city, null);
  return (m.group(1)!, m.group(2));
}

/// Short protocol name for a location: from its label, else its link.
String? protocolLabel(LocationItem l) {
  // The link itself first: Core names its REALITY link "(VLESS)", which
  // the name rule below read as Direct.
  final link = (l.rawLink ?? '').toLowerCase();
  if (link.startsWith('hysteria2://') || link.startsWith('hy2://')) {
    return 'Hysteria2';
  }
  if (link.contains('security=reality')) return 'REALITY';
  final fromName = splitPlaceAndProtocol(l.city).$2;
  final raw = (fromName ?? l.rawLink ?? '').toLowerCase();
  if (raw.contains('hysteria')) return 'Hysteria2';
  if (raw.contains('reality')) return 'REALITY';
  if (raw.contains('direct') || raw.startsWith('vless')) return 'Direct';
  if (raw.contains('cdn')) return 'CDN';
  return fromName;
}

/// The selected server: flag, place, "country · protocol" and a chevron to
/// the Servers tab — and, when the place has more than one protocol, a
/// protocol switch under it. The protocols come from the server catalog
/// (server_catalog.dart), the same source as the Servers tab, so the
/// header and the list always pick the same entry.
///
/// Up to three protocols share the width equally; more scroll sideways
/// with the active one kept in view. Labels shrink rather than clip.
class LocationBar extends StatelessWidget {
  const LocationBar({
    super.key,
    required this.location,
    required this.variants,
    required this.s,
    required this.onOpenServers,
    required this.onSelect,
  });

  final LocationItem location;

  /// The current place's protocol variants (from the catalog), in order.
  final List<LocationItem> variants;
  final AppStrings s;
  final VoidCallback onOpenServers;
  final ValueChanged<LocationItem> onSelect;

  @override
  Widget build(BuildContext context) {
    final (place, _) = splitPlaceAndProtocol(location.city);
    final proto = protocolLabel(location);
    final title = location.isAuto
        ? s.fastestLocation
        : (place.isNotEmpty ? place : location.country);
    final subtitle = [
      if (!location.isAuto && place.isNotEmpty) location.country,
      if (proto != null) proto,
    ].join(' · ');

    return Column(
      children: [
        TintedGlass(
          onTap: onOpenServers,
          padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Ic.text.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: location.isAuto
                    ? const Icon(Icons.public, color: Ic.arctic)
                    : FlagIcon(countryCode: location.countryCode, width: 28),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Ic.text,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (subtitle.isNotEmpty)
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            const TextStyle(color: Ic.textMuted, fontSize: 13),
                      ),
                  ],
                ),
              ),
              const SizedBox(
                width: 40,
                height: 44,
                child: Icon(Icons.chevron_right_rounded, color: Ic.textSecondary),
              ),
            ],
          ),
        ),
        if (variants.length > 1) ...[
          const SizedBox(height: 10),
          ProtocolSwitch(
            variants: variants,
            selectedProtocol: proto,
            onSelect: onSelect,
          ),
        ],
      ],
    );
  }
}

/// Segmented protocol switch (2–6 protocols).
class ProtocolSwitch extends StatelessWidget {
  const ProtocolSwitch({
    super.key,
    required this.variants,
    required this.selectedProtocol,
    required this.onSelect,
  });

  final List<LocationItem> variants;
  final String? selectedProtocol;
  final ValueChanged<LocationItem> onSelect;

  static const _gap = 3.0;
  static const _minSegment = 92.0;

  @override
  Widget build(BuildContext context) {
    Widget segment(LocationItem v) {
      final label = protocolLabel(v) ?? '—';
      final selected = label == selectedProtocol;
      return _Segment(
        key: selected ? const ValueKey('selected-protocol') : null,
        label: label,
        selected: selected,
        onTap: selected ? null : () => onSelect(v),
      );
    }

    return Container(
      padding: const EdgeInsets.all(_gap),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Ic.glassBorder),
        color: Ic.glassBottom.withValues(alpha: 0.6),
      ),
      child: LayoutBuilder(
        builder: (context, c) {
          final fits = variants.length <= 3 ||
              c.maxWidth / variants.length >= _minSegment;
          if (fits) {
            return Row(
              children: [
                for (final v in variants) Expanded(child: segment(v)),
              ],
            );
          }
          // More than fits: scroll, the active one brought into view.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final ctx = _selectedContext(context);
            if (ctx != null) {
              Scrollable.ensureVisible(ctx,
                  alignment: 0.5, duration: const Duration(milliseconds: 250));
            }
          });
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final v in variants)
                  SizedBox(width: _minSegment, child: segment(v)),
              ],
            ),
          );
        },
      ),
    );
  }

  BuildContext? _selectedContext(BuildContext root) {
    BuildContext? found;
    void visit(Element e) {
      if (found != null) return;
      if (e.widget.key == const ValueKey('selected-protocol')) {
        found = e;
        return;
      }
      e.visitChildren(visit);
    }

    if (root.mounted) (root as Element).visitChildren(visit);
    return found;
  }
}

class _Segment extends StatelessWidget {
  const _Segment(
      {super.key, required this.label, required this.selected, this.onTap});

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
        borderRadius: BorderRadius.circular(11),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          height: 40,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(11),
            color: selected ? context.brand.withValues(alpha: 0.18) : null,
            border: Border.all(
              color: selected
                  ? context.brand.withValues(alpha: 0.45)
                  : Colors.transparent,
            ),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              maxLines: 1,
              style: TextStyle(
                color: selected ? Ic.text : Ic.textMuted,
                fontSize: 14,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
