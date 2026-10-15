import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/wb_colors.dart';
import '../immersive/immersive_colors.dart';

/// What a notice is about — picks its icon and accent.
enum NoticeKind { info, success, warning, error }

/// Every message the app shows on its own — "copied", "no internet",
/// "back online", "update available", an error — is one of these: a glass
/// card at the top of the screen, under the status bar (owner, 12.10: the
/// offline toast sat on the bottom bar, the update prompt and the others
/// each looked different). One at a time: a new one replaces the one on
/// screen, the same text again while it shows does nothing. Tap or swipe
/// up to close; it also goes by itself.
void showNotice(
  String text, {
  NoticeKind kind = NoticeKind.info,
  IconData? icon,
  String? actionLabel,
  VoidCallback? onAction,
  Duration duration = const Duration(seconds: 3),
}) {
  final host = _host;
  if (host == null || text.trim().isEmpty) return;
  host._show(_Notice(
    text: text,
    kind: kind,
    icon: icon,
    actionLabel: actionLabel,
    onAction: onAction,
    duration: duration,
  ));
}

/// Closes the notice on screen, if any.
void hideNotice() => _host?._hide();

_NoticeHostState? _host;

class _Notice {
  _Notice({
    required this.text,
    required this.kind,
    required this.icon,
    required this.actionLabel,
    required this.onAction,
    required this.duration,
  });

  final String text;
  final NoticeKind kind;
  final IconData? icon;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Duration duration;
  final key = UniqueKey();
}

/// Sits over the whole app (MaterialApp.builder) and shows [showNotice]'s
/// cards above every screen, sheet and dialog.
class NoticeHost extends StatefulWidget {
  const NoticeHost({super.key, required this.child});

  final Widget? child;

  @override
  State<NoticeHost> createState() => _NoticeHostState();
}

class _NoticeHostState extends State<NoticeHost> {
  _Notice? _current;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _host = this;
  }

  @override
  void dispose() {
    if (_host == this) _host = null;
    _timer?.cancel();
    super.dispose();
  }

  void _show(_Notice notice) {
    final current = _current;
    if (current != null &&
        current.text == notice.text &&
        current.kind == notice.kind) {
      _arm(notice.duration);
      return;
    }
    setState(() => _current = notice);
    _arm(notice.duration);
  }

  void _arm(Duration duration) {
    _timer?.cancel();
    _timer = Timer(duration, _hide);
  }

  void _hide() {
    _timer?.cancel();
    if (!mounted || _current == null) return;
    setState(() => _current = null);
  }

  @override
  Widget build(BuildContext context) {
    final notice = _current;
    return Stack(
      children: [
        if (widget.child != null) Positioned.fill(child: widget.child!),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 260),
                    reverseDuration: const Duration(milliseconds: 180),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween(
                                begin: const Offset(0, -0.4), end: Offset.zero)
                            .animate(animation),
                        child: child,
                      ),
                    ),
                    child: notice == null
                        ? const SizedBox.shrink()
                        : Dismissible(
                            key: notice.key,
                            direction: DismissDirection.up,
                            onDismissed: (_) => _hide(),
                            child: NoticeCard(
                              text: notice.text,
                              kind: notice.kind,
                              icon: notice.icon,
                              actionLabel: notice.actionLabel,
                              onAction: notice.onAction == null
                                  ? null
                                  : () {
                                      _hide();
                                      notice.onAction!();
                                    },
                              onTap: _hide,
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

Color noticeColor(NoticeKind kind) => switch (kind) {
      NoticeKind.info => Ic.arctic,
      NoticeKind.success => WbColors.oceanTeal,
      NoticeKind.warning => WbColors.warning,
      NoticeKind.error => Ic.crimson,
    };

IconData _defaultIcon(NoticeKind kind) => switch (kind) {
      NoticeKind.info => Icons.info_outline_rounded,
      NoticeKind.success => Icons.check_circle_outline_rounded,
      NoticeKind.warning => Icons.warning_amber_rounded,
      NoticeKind.error => Icons.error_outline_rounded,
    };

/// The card itself — also what a screen uses for a notice that stays
/// in place (e.g. inside a sheet), so both look the same.
class NoticeCard extends StatelessWidget {
  const NoticeCard({
    super.key,
    required this.text,
    this.kind = NoticeKind.info,
    this.icon,
    this.actionLabel,
    this.onAction,
    this.onTap,
  });

  final String text;
  final NoticeKind kind;
  final IconData? icon;
  final String? actionLabel;
  final VoidCallback? onAction;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = noticeColor(kind);
    return Semantics(
      liveRegion: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding:
                EdgeInsets.fromLTRB(14, 10, actionLabel == null ? 16 : 6, 10),
            decoration: BoxDecoration(
              color: const Color(0xF20C1418),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: color.withValues(alpha: 0.45)),
              boxShadow: const [
                BoxShadow(
                    color: Color(0x66000000),
                    blurRadius: 18,
                    offset: Offset(0, 6)),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color.withValues(alpha: 0.16),
                  ),
                  child:
                      Icon(icon ?? _defaultIcon(kind), color: color, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    text,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Ic.text, fontSize: 14, height: 1.3),
                  ),
                ),
                if (actionLabel != null)
                  TextButton(
                    onPressed: onAction,
                    style: TextButton.styleFrom(foregroundColor: color),
                    child: Text(actionLabel!,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
