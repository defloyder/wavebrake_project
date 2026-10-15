import 'package:flutter/widgets.dart';

/// TV (owner, 15.10: "everything is huge and doesn't fit"): a TV reports
/// about 960×540 logical pixels, where the phone-sized type and cards
/// filled the screen. The app is laid out on a larger canvas
/// ([scale] < 1: 0.8 → 1200×675 on such a TV) and drawn scaled down to
/// fit. Taps, focus and scrolling go through the same transform.
class TvScale extends StatelessWidget {
  const TvScale({super.key, required this.child, this.scale = 0.8});

  final Widget child;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final size = mq.size / scale;
    EdgeInsets div(EdgeInsets e) => e / scale;
    return FittedBox(
      fit: BoxFit.fill,
      alignment: Alignment.topLeft,
      child: SizedBox.fromSize(
        size: size,
        child: MediaQuery(
          data: mq.copyWith(
            size: size,
            devicePixelRatio: mq.devicePixelRatio * scale,
            padding: div(mq.padding),
            viewPadding: div(mq.viewPadding),
            viewInsets: div(mq.viewInsets),
          ),
          child: child,
        ),
      ),
    );
  }
}
