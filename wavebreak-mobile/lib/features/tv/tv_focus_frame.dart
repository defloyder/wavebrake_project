import 'package:flutter/material.dart';

import '../../core/theme/wb_theme.dart';

/// Marks a control that draws its own focus mark (the sphere's round
/// ring): the TV frame leaves it alone.
class FocusFrameExempt extends StatelessWidget {
  const FocusFrameExempt({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

/// TV (owner, 12.10: "the remote is awkward"): one clear focus mark for
/// every control — a rounded accent ring with a glow that glides to
/// whatever the remote focuses and follows it while lists scroll. Plain
/// buttons and rows only showed a faint ink tint before, so after a press
/// of ↓ nothing on screen said where the focus was.
///
/// Recomputed on focus changes and scrolling, not every frame.
class TvFocusFrame extends StatefulWidget {
  const TvFocusFrame({super.key, required this.child});

  final Widget child;

  @override
  State<TvFocusFrame> createState() => _TvFocusFrameState();
}

class _TvFocusFrameState extends State<TvFocusFrame> {
  final _key = GlobalKey();
  Rect? _rect;
  bool _scheduled = false;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_schedule);
    FocusManager.instance.addHighlightModeListener(_onMode);
    _schedule();
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_schedule);
    FocusManager.instance.removeHighlightModeListener(_onMode);
    super.dispose();
  }

  void _onMode(FocusHighlightMode _) => _schedule();

  /// After this frame's layout (a focus change can scroll the item into
  /// view first).
  void _schedule() {
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (mounted) _update();
    });
  }

  void _update() {
    final next = _focusedRect();
    if (next == _rect) return;
    setState(() => _rect = next);
  }

  Rect? _focusedRect() {
    if (FocusManager.instance.highlightMode != FocusHighlightMode.traditional) {
      return null;
    }
    final node = FocusManager.instance.primaryFocus;
    final ctx = node?.context;
    if (node == null || ctx == null || !ctx.mounted) return null;
    if (node is FocusScopeNode) return null;
    if (ctx.findAncestorWidgetOfExactType<FocusFrameExempt>() != null) {
      return null;
    }
    // A text field draws its own focus border: framing the text inside it
    // doubled the outline and washed the field pink (owner, 15.10).
    if (ctx.widget is EditableText ||
        ctx.findAncestorWidgetOfExactType<EditableText>() != null) {
      return null;
    }
    final box = _key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    final global = node.rect;
    if (global.isEmpty) return null;
    final origin = box.localToGlobal(Offset.zero);
    final rect = global.shift(-origin);
    final screen = box.size;
    // A whole page or panel taking the focus is no control to frame.
    if (rect.width * rect.height > screen.width * screen.height * 0.5) {
      return null;
    }
    return rect;
  }

  @override
  Widget build(BuildContext context) {
    final rect = _rect;
    final accent = context.accent;
    return NotificationListener<ScrollNotification>(
      onNotification: (_) {
        _schedule();
        return false;
      },
      child: Stack(
        key: _key,
        children: [
          Positioned.fill(child: widget.child),
          if (rect != null)
            AnimatedPositioned.fromRect(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOutCubic,
              rect: rect.inflate(5),
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: accent, width: 3),
                    boxShadow: [
                      BoxShadow(
                        color: accent.withValues(alpha: 0.45),
                        blurRadius: 18,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
