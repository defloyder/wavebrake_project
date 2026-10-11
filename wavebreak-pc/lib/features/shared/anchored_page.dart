import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../core/theme/wb_theme.dart';
import '../immersive/immersive_colors.dart';

/// Bumped by every tap on the bottom bar / side rail: the tab pages jump
/// back to their top (owner, 07.10: a page always opens at its top).
final shellTabTaps = ValueNotifier<int>(0);

/// A page body: [content] (the rows) at the bottom by the thumb, [hero]
/// centred in the room above it (owner, 06.10–07.10: rows pressed to the
/// top made phone users reach up, and the page looked empty).
///
/// - Everything fits: no scrolling at all.
/// - The rows fit but not with the hero: the hero is left out — never a
///   short scroll just for a decoration.
/// - The rows alone are taller than the page: hero on top, then the rows,
///   and the page scrolls — starting at its top.
class AnchoredPage extends StatefulWidget {
  const AnchoredPage({
    super.key,
    required this.content,
    this.hero,
    this.padding = EdgeInsets.zero,
    this.gap = 16,
  });

  final Widget content;
  final Widget? hero;

  /// Around the whole scrolling body (the bottom one keeps the rows clear
  /// of the floating nav bar).
  final EdgeInsets padding;

  /// The least room above and below the hero.
  final double gap;

  @override
  State<AnchoredPage> createState() => _AnchoredPageState();
}

class _AnchoredPageState extends State<AnchoredPage> {
  final _controller = ScrollController();

  @override
  void initState() {
    super.initState();
    shellTabTaps.addListener(_toTop);
  }

  void _toTop() {
    if (_controller.hasClients) _controller.jumpTo(0);
  }

  @override
  void dispose() {
    shellTabTaps.removeListener(_toTop);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) => SingleChildScrollView(
        controller: _controller,
        physics: const ClampingScrollPhysics(),
        padding: widget.padding,
        child: _HeroAbove(
          minHeight: math.max(0, box.maxHeight - widget.padding.vertical),
          gap: widget.gap,
          hero: widget.hero ?? const SizedBox.shrink(),
          content: widget.content,
        ),
      ),
    );
  }
}

class _HeroAbove extends MultiChildRenderObjectWidget {
  _HeroAbove({
    required this.minHeight,
    required this.gap,
    required Widget hero,
    required Widget content,
  }) : super(children: [hero, content]);

  final double minHeight;
  final double gap;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderHeroAbove(minHeight: minHeight, gap: gap);

  @override
  void updateRenderObject(BuildContext context, _RenderHeroAbove renderObject) {
    renderObject
      ..minHeight = minHeight
      ..gap = gap;
  }
}

class _HeroAboveData extends ContainerBoxParentData<RenderBox> {}

class _RenderHeroAbove extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _HeroAboveData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _HeroAboveData> {
  _RenderHeroAbove({required double minHeight, required double gap})
      : _minHeight = minHeight,
        _gap = gap;

  double _minHeight;
  set minHeight(double value) {
    if (value == _minHeight) return;
    _minHeight = value;
    markNeedsLayout();
  }

  double _gap;
  set gap(double value) {
    if (value == _gap) return;
    _gap = value;
    markNeedsLayout();
  }

  bool _heroShown = false;

  RenderBox get _hero => firstChild!;
  RenderBox get _content => lastChild!;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _HeroAboveData) {
      child.parentData = _HeroAboveData();
    }
  }

  @override
  void performLayout() {
    final width = constraints.maxWidth;
    _content.layout(BoxConstraints.tightFor(width: width),
        parentUsesSize: true);
    _hero.layout(BoxConstraints(maxWidth: width), parentUsesSize: true);
    final contentH = _content.size.height;
    final hero = _hero.size;
    final free = _minHeight - contentH;
    final heroRoom = hero.height + 2 * _gap;
    final fits = free >= heroRoom;
    _heroShown = hero.height > 0 && (fits || contentH > _minHeight);

    final double height;
    double heroY = 0;
    if (_heroShown && fits) {
      height = _minHeight;
      heroY = (free - hero.height) / 2;
    } else if (_heroShown) {
      height = heroRoom + contentH;
      heroY = _gap;
    } else {
      height = math.max(_minHeight, contentH);
    }
    (_hero.parentData! as _HeroAboveData).offset =
        Offset((width - hero.width) / 2, heroY);
    (_content.parentData! as _HeroAboveData).offset =
        Offset(0, height - contentH);
    size = constraints.constrain(Size(width, height));
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (_heroShown) {
      context.paintChild(
          _hero, (_hero.parentData! as _HeroAboveData).offset + offset);
    }
    context.paintChild(
        _content, (_content.parentData! as _HeroAboveData).offset + offset);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    for (final child in [_content, if (_heroShown) _hero]) {
      final data = child.parentData! as _HeroAboveData;
      final hit = result.addWithPaintOffset(
        offset: data.offset,
        position: position,
        hitTest: (result, transformed) =>
            child.hitTest(result, position: transformed),
      );
      if (hit) return true;
    }
    return false;
  }

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {
    if (_heroShown) visitor(_hero);
    visitor(_content);
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(
        FlagProperty('heroShown', value: _heroShown, ifTrue: 'hero shown'));
  }
}

/// The emblem over a settings page: the page's icon in a glowing glass
/// orb with slow ripples going out from it — the app's sea — and a line
/// on what the page is for.
class PageEmblem extends StatefulWidget {
  const PageEmblem({super.key, required this.icon, this.caption});

  final IconData icon;
  final String? caption;

  @override
  State<PageEmblem> createState() => _PageEmblemState();
}

class _PageEmblemState extends State<PageEmblem>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ripple = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 4200));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _ripple
        ..stop()
        ..value = 0.35;
    } else if (!_ripple.isAnimating) {
      _ripple.repeat();
    }
  }

  @override
  void dispose() {
    _ripple.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = context.accent;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox.square(
          dimension: 150,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned.fill(
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: _RipplePainter(_ripple, accent),
                  ),
                ),
              ),
              Container(
                width: 80,
                height: 80,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      accent.withValues(alpha: 0.30),
                      accent.withValues(alpha: 0.08),
                    ],
                  ),
                  border: Border.all(color: accent.withValues(alpha: 0.55)),
                  boxShadow: [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.28),
                      blurRadius: 28,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Icon(widget.icon, size: 36, color: Ic.text),
              ),
            ],
          ),
        ),
        if (widget.caption case final caption?) ...[
          const SizedBox(height: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 300),
            child: Text(
              caption,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Ic.textSecondary, fontSize: 15, height: 1.35),
            ),
          ),
        ],
      ],
    );
  }
}

class _RipplePainter extends CustomPainter {
  _RipplePainter(this.t, this.color) : super(repaint: t);

  final Animation<double> t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final inner = 40.0;
    final outer = size.shortestSide / 2;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    for (var i = 0; i < 3; i++) {
      final p = (t.value + i / 3) % 1;
      final r = inner + (outer - inner) * Curves.easeOut.transform(p);
      paint.color = color.withValues(alpha: 0.38 * (1 - p));
      canvas.drawCircle(center, r, paint);
    }
  }

  @override
  bool shouldRepaint(_RipplePainter old) => old.color != color;
}
