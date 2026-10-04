import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/personalization_controller.dart';

/// One shared clock for every decorative animation (background waves,
/// sphere, orbits, speed-test scene): seconds as a [ValueListenable] that
/// painters pass as `repaint:`, so a tick repaints only the painters and
/// never rebuilds widgets.
///
/// Throttled to ~30 fps — decoration doesn't need 60/120 and the battery
/// does. Frozen (one static frame) when the user turned on "reduce motion"
/// in the app or the system asks to disable animations. Flutter stops
/// ticking on its own while the app is in the background.
class ImmersiveClock extends ConsumerStatefulWidget {
  const ImmersiveClock({super.key, required this.child});

  final Widget child;

  static ValueListenable<double> of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_ClockScope>()?.time ??
      const _FrozenTime();

  /// True when animations are frozen — painters may skip extra work.
  static bool frozen(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_ClockScope>()?.frozen ?? true;

  @override
  ConsumerState<ImmersiveClock> createState() => _ImmersiveClockState();
}

class _ImmersiveClockState extends ConsumerState<ImmersiveClock>
    with SingleTickerProviderStateMixin {
  final _time = ValueNotifier<double>(0);
  late final Ticker _ticker = createTicker(_onTick);
  Duration _lastPaint = Duration.zero;
  double _offset = 0; // keeps time continuous across freeze/unfreeze
  bool _frozen = false;

  static const _frame = Duration(milliseconds: 33);

  void _onTick(Duration elapsed) {
    if (elapsed - _lastPaint < _frame) return;
    _lastPaint = elapsed;
    _time.value = _offset + elapsed.inMicroseconds / 1e6;
  }

  void _apply(bool frozen) {
    if (frozen == _frozen && (_ticker.isActive || frozen)) return;
    _frozen = frozen;
    if (frozen) {
      _offset = _time.value;
      if (_ticker.isActive) _ticker.stop();
    } else if (!_ticker.isActive) {
      _offset = _time.value;
      _lastPaint = Duration.zero;
      _ticker.start();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _time.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final frozen = ref.watch(personalizationProvider).reduceMotion ||
        MediaQuery.of(context).disableAnimations;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _apply(frozen);
    });
    return _ClockScope(time: _time, frozen: frozen, child: widget.child);
  }
}

class _ClockScope extends InheritedWidget {
  const _ClockScope(
      {required this.time, required this.frozen, required super.child});

  final ValueListenable<double> time;
  final bool frozen;

  @override
  bool updateShouldNotify(_ClockScope old) =>
      old.time != time || old.frozen != frozen;
}

class _FrozenTime extends ValueListenable<double> {
  const _FrozenTime();
  @override
  double get value => 0;
  @override
  void addListener(VoidCallback listener) {}
  @override
  void removeListener(VoidCallback listener) {}
}
