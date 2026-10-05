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
  final fromName = splitPlaceAndProtocol(l.city).$2;
  final raw = (fromName ?? l.rawLink ?? '').toLowerCase();
  if (raw.contains('hysteria')) return 'Hysteria2';
  if (raw.contains('reality')) return 'REALITY';
  if (raw.contains('direct') || raw.startsWith('vless')) return 'Direct';
  if (raw.contains('cdn')) return 'CDN';
  return fromName;
}

/// The selected server: flag, place, "country · protocol", chevron to the
/// picker — and, when the country has more than one protocol, a segmented
/// Direct / Hysteria2 switch. Never truncates the place to fit the
/// protocol: the protocol has its own line.
class LocationBar extends StatelessWidget {
  const LocationBar({
    super.key,
    required this.location,
    required this.siblings,
    required this.s,
    required this.onOpenPicker,
    required this.onSelect,
  });

  final LocationItem location;

  /// Locations of the same country (including [location]), one per
  /// protocol, in display order.
  final List<LocationItem> siblings;
  final AppStrings s;
  final VoidCallback onOpenPicker;
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
    final options = [
      for (final l in siblings)
        if (protocolLabel(l) != null) l,
    ];

    return Column(
      children: [
        TintedGlass(
          onTap: onOpenPicker,
          padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
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
                width: 44,
                height: 44,
                child: Icon(Icons.expand_more_rounded, color: Ic.textSecondary),
              ),
            ],
          ),
        ),
        if (options.length > 1) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Ic.glassBorder),
              color: Ic.glassBottom.withValues(alpha: 0.6),
            ),
            child: Row(
              children: [
                for (final l in options)
                  Expanded(
                    child: _Segment(
                      label: protocolLabel(l)!,
                      selected: l.id == location.id,
                      onTap: l.id == location.id ? null : () => onSelect(l),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({required this.label, required this.selected, this.onTap});

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
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(11),
            color: selected ? context.brand.withValues(alpha: 0.18) : null,
            border: Border.all(
              color: selected
                  ? context.brand.withValues(alpha: 0.45)
                  : Colors.transparent,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Ic.text : Ic.textMuted,
              fontSize: 14,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}
