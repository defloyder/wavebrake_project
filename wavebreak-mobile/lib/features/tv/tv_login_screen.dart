import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/auth/session_controller.dart';
import '../../core/errors/app_exception.dart';
import '../../core/i18n/language_controller.dart';
import '../../core/logging/app_logger.dart';
import '../../core/theme/wb_colors.dart';
import '../../services/core_api/models.dart';
import '../../services/device/device_service.dart';
import '../../services/providers.dart';
import '../immersive/immersive_colors.dart';
import '../immersive/tinted_glass.dart';
import '../shared/ocean_background.dart';
import '../shared/wave_params.dart';
import '../shared/wavebreak_mark.dart';

/// TV sign-in: a QR the owner scans with WAVEBREAK on the phone (Settings
/// → Account → "Sign in on another device"); typing an e-mail and a
/// password with a remote is a pain (owner, 06.10). The phone confirms,
/// this screen polls Core and signs in with a session of its own — the
/// phone stays signed in. E-mail and password stay one button away.
///
/// The code lives 10 minutes; a new one replaces it before that.
class TvLoginScreen extends ConsumerStatefulWidget {
  const TvLoginScreen({super.key});

  @override
  ConsumerState<TvLoginScreen> createState() => _TvLoginScreenState();
}

class _TvLoginScreenState extends ConsumerState<TvLoginScreen> {
  DeviceLoginStart? _login;
  Timer? _poll;
  Timer? _renew;
  String? _error;
  bool _unavailable = false;
  bool _starting = false;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _renew?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    if (_starting) return;
    _poll?.cancel();
    _renew?.cancel();
    setState(() {
      _starting = true;
      _error = null;
    });
    final gateway = ref.read(coreGatewayProvider);
    try {
      // The TV's model names it on the phone; not worth more than a
      // second's wait before the QR shows.
      final (_, name) = await DeviceService(gateway).platformInfo().timeout(
          const Duration(seconds: 1),
          onTimeout: () => ('android', 'Android TV'));
      final login = await gateway.startDeviceLogin(
          deviceName: name, platform: 'android-tv');
      if (!mounted) return;
      setState(() {
        _login = login;
        _starting = false;
        _unavailable = false;
      });
      _poll = Timer.periodic(
          Duration(seconds: login.interval.clamp(2, 10)), (_) => _check());
      // A fresh code a little before this one expires.
      _renew = Timer(
          Duration(seconds: (login.expiresIn - 20).clamp(30, 3600)), _start);
    } on AppException catch (e) {
      if (!mounted) return;
      AppLogger.warn('TV sign-in: start failed: ${e.kind} ${e.statusCode}');
      setState(() {
        _starting = false;
        _login = null;
        // An older Core has no QR sign-in yet.
        _unavailable = e.statusCode == 404 || e.statusCode == 405;
        _error = _unavailable ? null : e.localized(ref.read(stringsProvider));
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _starting = false;
        _login = null;
        _error = ref.read(stringsProvider).errUnavailable;
      });
    }
  }

  Future<void> _check() async {
    final login = _login;
    if (login == null || _done) return;
    try {
      final tokens =
          await ref.read(coreGatewayProvider).pollDeviceLogin(login.pollToken);
      if (tokens == null || !mounted || _done) return;
      _done = true;
      _poll?.cancel();
      _renew?.cancel();
      AppLogger.info('TV sign-in: approved on the phone');
      // The router moves on to Home once the session is in.
      await ref
          .read(sessionControllerProvider.notifier)
          .onAuthenticated(tokens);
    } on AppException catch (e) {
      // 410: expired or already used — a new code.
      if (e.statusCode == 410 && mounted) unawaited(_start());
    } catch (_) {
      // A missed poll; the next one tries again.
    }
  }

  static String _pretty(String code) =>
      code.length == 8 ? '${code.substring(0, 4)}-${code.substring(4)}' : code;

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final login = _login;
    const stepStyle =
        TextStyle(color: Ic.textSecondary, fontSize: 20, height: 1.4);

    final left = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const WavebreakMark(size: 64, glow: true),
        const SizedBox(height: 20),
        Text(s.tvLoginTitle,
            style: const TextStyle(
                color: Ic.text, fontSize: 40, fontFamily: Ic.fontSerif)),
        const SizedBox(height: 24),
        if (_unavailable)
          Text(s.tvLoginUnavailable, style: stepStyle)
        else ...[
          _Step(n: 1, text: s.tvLoginStep1, style: stepStyle),
          _Step(n: 2, text: s.tvLoginStep2, style: stepStyle),
          _Step(n: 3, text: s.tvLoginStep3, style: stepStyle),
        ],
        const SizedBox(height: 32),
        Wrap(
          spacing: 16,
          runSpacing: 12,
          children: [
            _TvButton(
              label: s.tvLoginWithEmail,
              autofocus: _unavailable,
              onPressed: () => context.push('/login'),
            ),
            if (!_unavailable)
              _TvButton(
                label: s.tvLoginNewCode,
                autofocus: !_unavailable,
                onPressed: _starting ? null : _start,
              ),
          ],
        ),
      ],
    );

    final Widget right;
    if (login != null) {
      right = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: QrImageView(
              data: login.url,
              size: 280,
              backgroundColor: Colors.white,
              eyeStyle: const QrEyeStyle(
                  eyeShape: QrEyeShape.square, color: WbColors.midnight),
              dataModuleStyle: const QrDataModuleStyle(
                  dataModuleShape: QrDataModuleShape.square,
                  color: WbColors.midnight),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            _pretty(login.code),
            style: const TextStyle(
              color: Ic.text,
              fontSize: 34,
              fontWeight: FontWeight.w600,
              letterSpacing: 6,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child:
                    CircularProgressIndicator(strokeWidth: 2, color: Ic.arctic),
              ),
              const SizedBox(width: 10),
              Text(s.tvLoginWaiting,
                  style: const TextStyle(color: Ic.textMuted, fontSize: 18)),
            ],
          ),
        ],
      );
    } else if (_starting) {
      right = const SizedBox(
          width: 60, height: 60, child: CircularProgressIndicator());
    } else if (_error != null) {
      right = Text(_error!,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Ic.amber, fontSize: 20));
    } else {
      right = const SizedBox.shrink();
    }

    final waves = ref.watch(appWaveParamsProvider);
    return Scaffold(
      body: OceanBackground(
        stars: true,
        illuminate: true,
        tint: waves.tint,
        waveSpeed: waves.speed,
        waveAmplitude: waves.amplitude,
        maxContentWidth: double.infinity,
        child: SafeArea(
          child: Padding(
            // TV overscan: keep everything inside the safe 5 % margin.
            padding: const EdgeInsets.symmetric(horizontal: 56, vertical: 32),
            child: Row(
              children: [
                // Scaled down to fit: TVs report anything from 960x540
                // to 1920x1080 logical pixels.
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: SizedBox(width: 520, child: left),
                  ),
                ),
                const SizedBox(width: 48),
                Expanded(
                  child: FittedBox(fit: BoxFit.scaleDown, child: right),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.n, required this.text, required this.style});

  final int n;
  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            margin: const EdgeInsets.only(right: 14),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Ic.glassBorder),
            ),
            child: Text('$n',
                style: const TextStyle(color: Ic.text, fontSize: 16)),
          ),
          Flexible(child: Text(text, style: style)),
        ],
      ),
    );
  }
}

/// A glass button that shows remote focus clearly (TintedGlass is an
/// InkWell: OK / Select on the remote presses it).
class _TvButton extends StatelessWidget {
  const _TvButton({
    required this.label,
    required this.onPressed,
    this.autofocus = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    // Button-sized (TintedGlass on its own fills the width).
    return IntrinsicWidth(
      child: TintedGlass(
        onTap: onPressed,
        autofocus: autofocus,
        padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 16),
        child: Text(label,
            style: TextStyle(
                color: onPressed == null ? Ic.textMuted : Ic.text,
                fontSize: 20,
                fontWeight: FontWeight.w600)),
      ),
    );
  }
}
