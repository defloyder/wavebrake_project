import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// Back and forward on Windows the way a browser does it (owner, 16.10:
/// the mouse's side buttons did nothing): the side buttons, Alt+← / Alt+→
/// and the keyboard's Back/Forward keys walk the pages visited — tabs and
/// settings sections alike.
///
/// The history is the app's own list of visited locations; moving through
/// it uses `go`, so the page stack under each location is the router's
/// usual one (a settings section sits on the settings list).
class DesktopHistory extends StatefulWidget {
  const DesktopHistory({super.key, required this.router, required this.child});

  final GoRouter router;
  final Widget child;

  @override
  State<DesktopHistory> createState() => _DesktopHistoryState();
}

class _DesktopHistoryState extends State<DesktopHistory> {
  final _visited = <String>[];
  var _index = -1;

  /// Set while back/forward moves, so that move isn't recorded as a visit.
  bool _walking = false;

  static const _max = 50;

  /// Only the app's own pages: never back into sign-in or the splash.
  static bool _inApp(String path) => const [
        '/home',
        '/locations',
        '/settings',
        '/speed-test',
        '/metrics',
        '/subscription',
      ].any((p) => path == p || path.startsWith('$p/'));

  @override
  void initState() {
    super.initState();
    widget.router.routerDelegate.addListener(_onRoute);
    HardwareKeyboard.instance.addHandler(_onKey);
    _onRoute();
  }

  @override
  void dispose() {
    widget.router.routerDelegate.removeListener(_onRoute);
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  void _onRoute() {
    final path =
        widget.router.routerDelegate.currentConfiguration.uri.toString();
    if (!_inApp(Uri.parse(path).path)) return;
    if (_walking) {
      _walking = false;
      return;
    }
    if (_index >= 0 && _visited[_index] == path) return;
    // A new visit drops whatever was ahead, as in a browser.
    _visited.removeRange(_index + 1, _visited.length);
    _visited.add(path);
    if (_visited.length > _max) _visited.removeAt(0);
    _index = _visited.length - 1;
  }

  void _walk(int step) {
    final target = _index + step;
    if (target < 0 || target >= _visited.length) return;
    _index = target;
    _walking = true;
    widget.router.go(_visited[target]);
  }

  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    final key = event.logicalKey;
    final alt = HardwareKeyboard.instance.isAltPressed;
    if (key == LogicalKeyboardKey.browserBack ||
        (alt && key == LogicalKeyboardKey.arrowLeft)) {
      _walk(-1);
      return true;
    }
    if (key == LogicalKeyboardKey.browserForward ||
        (alt && key == LogicalKeyboardKey.arrowRight)) {
      _walk(1);
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) {
        if (event.kind != PointerDeviceKind.mouse) return;
        if (event.buttons & kBackMouseButton != 0) _walk(-1);
        if (event.buttons & kForwardMouseButton != 0) _walk(1);
      },
      child: widget.child,
    );
  }
}
