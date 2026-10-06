import 'package:flutter/material.dart';

import '../../core/theme/wb_colors.dart';
import '../../core/theme/wb_theme.dart';
import '../immersive/tinted_glass.dart';
import '../shared/detail_scaffold.dart';
import '../shared/nav_utils.dart';

// The building blocks every settings page is made of (P8): a page with a
// header, groups (a caption and one glass block of rows), rows, switch
// rows and footers. Pages only arrange these — no page has its own card
// layout. Icons and surfaces are neutral; the accent marks only what is
// on or selected (switches, badges, the chosen option).

/// A settings page: back button and title, then a scrolling column.
class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.title,
    required this.children,
    this.fallback = '/settings',
  });

  final String title;
  final List<Widget> children;

  /// Where "back" goes when there is nothing to pop.
  final String fallback;

  @override
  Widget build(BuildContext context) {
    return DetailScaffold(
      title: title,
      onBack: () => safePop(context, fallback: fallback),
      child: ListView(
        padding: const EdgeInsets.only(bottom: 16),
        children: children,
      ),
    );
  }
}

/// A caption and one glass block holding [children] (rows), with hairline
/// dividers between them and an optional [footer] under the block.
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({
    super.key,
    this.title,
    required this.children,
    this.footer,
  });

  final String? title;
  final List<Widget> children;
  final String? footer;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (final child in children) {
      if (rows.isNotEmpty) {
        rows.add(const Divider(
            height: 1, thickness: 1, indent: 62, color: WbColors.ice08));
      }
      rows.add(child);
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
              child: Text(
                title!,
                style: const TextStyle(
                  color: WbColors.muted,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                ),
              ),
            ),
          TintedGlass(
            padding: EdgeInsets.zero,
            radius: 18,
            // Rows draw their ink on this, above the glass.
            child: Material(
              type: MaterialType.transparency,
              child: Column(children: rows),
            ),
          ),
          if (footer != null) SettingsFooter(footer!),
        ],
      ),
    );
  }
}

/// The neutral icon tile at the start of a row.
class SettingsIcon extends StatelessWidget {
  const SettingsIcon(this.icon, {super.key, this.color});

  final IconData icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: WbColors.ice08,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Icon(icon, size: 18, color: color ?? WbColors.ice),
    );
  }
}

/// One row: icon, title, optional subtitle and value, then [trailing]
/// (a chevron by default when the row opens something).
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    this.icon,
    required this.title,
    this.subtitle,
    this.value,
    this.trailing,
    this.onTap,
    this.badge = false,
    this.info,
    this.destructive = false,
    this.enabled = true,
    this.chevron,
  });

  final IconData? icon;
  final String title;
  final String? subtitle;

  /// Current value, shown muted before the chevron ("Русский").
  final String? value;
  final Widget? trailing;
  final VoidCallback? onTap;

  /// An accent dot: something new behind this row (an update).
  final bool badge;

  /// The long explanation behind an (i) button.
  final String? info;
  final bool destructive;
  final bool enabled;

  /// Defaults to true when the row has [onTap] and no [trailing].
  final bool? chevron;

  @override
  Widget build(BuildContext context) {
    final titleColor = destructive ? WbColors.error : WbColors.ice;
    final showChevron = chevron ?? (onTap != null && trailing == null);
    final row = Padding(
      padding: EdgeInsets.fromLTRB(
          16, 12, showChevron || trailing != null || info != null ? 8 : 16, 12),
      child: Row(
        children: [
          if (icon != null) ...[
            SettingsIcon(icon!, color: destructive ? WbColors.error : null),
            const SizedBox(width: 14),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 15.5, color: titleColor),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: const TextStyle(
                        fontSize: 12.5, color: WbColors.muted, height: 1.3),
                  ),
                ],
              ],
            ),
          ),
          if (value != null) ...[
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: BoxConstraints(
                  maxWidth: MediaQuery.sizeOf(context).width * 0.32),
              child: Text(
                value!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14, color: WbColors.ice60),
              ),
            ),
          ],
          if (badge)
            Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.only(left: 8),
              decoration: BoxDecoration(
                color: context.accent,
                shape: BoxShape.circle,
              ),
            ),
          if (info != null)
            IconButton(
              tooltip: title,
              visualDensity: VisualDensity.compact,
              onPressed: () => showSettingsInfo(context, title, info!),
              icon: const Icon(Icons.info_outline_rounded,
                  color: WbColors.ice60, size: 20),
            ),
          if (trailing != null) ...[const SizedBox(width: 4), trailing!],
          if (showChevron)
            const Padding(
              padding: EdgeInsets.only(left: 2),
              child: Icon(Icons.chevron_right_rounded,
                  color: WbColors.ice60, size: 22),
            ),
        ],
      ),
    );
    final content = enabled ? row : Opacity(opacity: 0.45, child: row);
    if (onTap == null || !enabled) return content;
    return InkWell(onTap: onTap, child: content);
  }
}

/// A row with a switch; tapping the row flips it too.
class SettingsSwitchRow extends StatelessWidget {
  const SettingsSwitchRow({
    super.key,
    this.icon,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData? icon;
  final String title;
  final String? subtitle;
  final bool value;

  /// Null disables the row.
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final change = onChanged;
    return SettingsRow(
      icon: icon,
      title: title,
      subtitle: subtitle,
      enabled: change != null,
      onTap: change == null ? null : () => change(!value),
      trailing: Switch.adaptive(
        value: value,
        activeTrackColor: context.accent,
        onChanged: change,
      ),
    );
  }
}

/// A free-form block inside a group (a picker, segmented choice).
class SettingsBlock extends StatelessWidget {
  const SettingsBlock({
    super.key,
    this.title,
    this.subtitle,
    required this.child,
  });

  final String? title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null)
            Text(title!, style: const TextStyle(fontSize: 15.5)),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              subtitle!,
              style: const TextStyle(
                  fontSize: 12.5, color: WbColors.muted, height: 1.3),
            ),
          ],
          if (title != null || subtitle != null) const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

/// Small print under a group.
class SettingsFooter extends StatelessWidget {
  const SettingsFooter(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
      child: Text(
        text,
        style:
            const TextStyle(fontSize: 12.5, color: WbColors.muted, height: 1.35),
      ),
    );
  }
}

/// The (i) explanation dialog.
Future<void> showSettingsInfo(BuildContext context, String title, String body) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
      content: SingleChildScrollView(
        child: Text(body, style: const TextStyle(height: 1.45)),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}
