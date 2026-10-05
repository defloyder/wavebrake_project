import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/personalization_controller.dart';
import 'effects_quality.dart';

/// One shared clock for every decorative animation (background waves,
/// sphere, orbits, speed-test scene): seconds as a [ValueListenable] that
/// painters pass as `repaint:`, so a tick repaints only the painters and
/// never rebuilds widgets.
///
/// ~30 fps, and it asks for a frame only 30 times a second. (A Ticker
/// that merely skipped updates still requested a frame on every vsync —
/// on a 120 Hz phone Flutter then re-rendered the whole scene, glass
/// blur included, ~4× more often than the waves changed: the GPU stayed
/// saturated, scrolling dropped to ~30 fps and minimising lagged.)
/// Frozen (one static frame) when the user turned on "reduce motion" in
/// the app or the system asks to disable animations; stopped while the
/// app is not visible.
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
    with WidgetsBindingObserver {
  final _time = ValueNotifier<double>(0);
  final _watch = Stopwatch();
  Timer? _timer;
  int? _pendingFrame;
  double _offset = 0; // keeps time continuous across stop/start
  bool _frozen = false;
  bool _visible = true;

  // 30 fps; 20 fps with economy effects (older phones).
  Duration _frame = const Duration(milliseconds: 33);

  bool get _running => _timer != null;

  void _tick(Timer _) {
    if (_pendingFrame != null) return;
    // Update inside a frame callback so the new value lands vsync-aligned.
    _pendingFrame = SchedulerBinding.instance.scheduleFrameCallback((_) {
      _pendingFrame = null;
      _time.value = _offset + _watch.elapsedMicroseconds / 1e6;
    });
  }

  void _start() {
    if (_running) return;
    _offset = _time.value;
    _watch
      ..reset()
      ..start();
    _timer = Timer.periodic(_frame, _tick);
  }

  void _stop() {
    if (!_running) return;
    _timer!.cancel();
    _timer = null;
    if (_pendingFrame != null) {
      SchedulerBinding.instance.cancelFrameCallbackWithId(_pendingFrame!);
      _pendingFrame = null;
    }
    _watch.stop();
    _time.value = _offset + _watch.elapsedMicroseconds / 1e6;
  }

  void _apply() => (!_frozen && _visible) ? _start() : _stop();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _visible = state == AppLifecycleState.resumed ||
        state == AppLifecycleState.inactive;
    _apply();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stop();
    _time.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final economy = ref.watch(effectsEconomyProvider);
    final frozen = ref.watch(personalizationProvider).reduceMotion ||
        MediaQuery.of(context).disableAnimations;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _frozen = frozen;
      final frame = Duration(milliseconds: economy ? 50 : 33);
      if (frame != _frame) {
        _frame = frame;
        _stop();
      }
      _apply();
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
