import '../../core/theme/wb_theme.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/i18n/app_strings.dart';
import '../../core/theme/wb_colors.dart';
import '../../services/pin/pin_service.dart';

/// Row of dots showing how many digits of a PIN have been entered so far —
/// shared between the lock screen and the PIN setup flow so both read as
/// the same control.
class PinDots extends StatelessWidget {
  const PinDots({super.key, required this.length, this.error = false, this.total = 6});

  final int length;
  final bool error;

  /// How many dots: the PIN's own length when known.
  final int total;

  @override
  Widget build(BuildContext context) {
    final color = error ? WbColors.error : context.accent;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(total, (i) {
        final filled = i < length;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.symmetric(horizontal: 6),
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: filled ? color : Colors.transparent,
            border: Border.all(color: color.withValues(alpha: filled ? 1 : 0.4)),
          ),
        );
      }),
    );
  }
}

/// A 0-9 + backspace numeric keypad, large-target and thumb-friendly, used
/// by both the lock screen and PIN setup/change flows.
class PinKeypad extends StatelessWidget {
  const PinKeypad({super.key, required this.onDigit, required this.onBackspace});

  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;

  static const _rows = [
    ['1', '2', '3'],
    ['4', '5', '6'],
    ['7', '8', '9'],
    ['', '0', 'back'],
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final row in _rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (final key in row)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: _KeypadButton(
                      keyValue: key,
                      onDigit: onDigit,
                      onBackspace: onBackspace,
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _KeypadButton extends StatelessWidget {
  const _KeypadButton({
    required this.keyValue,
    required this.onDigit,
    required this.onBackspace,
  });

  final String keyValue;
  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;

  @override
  Widget build(BuildContext context) {
    if (keyValue.isEmpty) return const SizedBox(width: 72, height: 72);
    final isBackspace = keyValue == 'back';
    return Material(
      color: WbColors.card.withValues(alpha: 0.6),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () {
          unawaited(HapticFeedback.selectionClick());
          isBackspace ? onBackspace() : onDigit(keyValue);
        },
        child: SizedBox(
          width: 72,
          height: 72,
          child: Center(
            child: isBackspace
                ? const Icon(Icons.backspace_outlined, color: WbColors.ice, size: 22)
                : Text(
                    keyValue,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w600,
                      color: WbColors.ice,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

/// PIN entry against the stored PIN — dots, error line, keypad and, for a
/// PIN whose length wasn't recorded, a Continue button. Shared by the lock
/// screen and the verify-before-change screen.
///
/// With the length known the PIN is checked the moment its last digit is
/// typed; a wrong one shows "Incorrect PIN" right away. Without it every
/// length from [PinService.minLength] up is tried silently (a match
/// unlocks) and Continue reports a mismatch. A PIN that can't be read at
/// all says so instead of doing nothing.
class PinEntry extends StatefulWidget {
  const PinEntry({super.key, required this.s, required this.onVerified});

  final AppStrings s;
  final VoidCallback onVerified;

  @override
  State<PinEntry> createState() => _PinEntryState();
}

class _PinEntryState extends State<PinEntry> {
  final _pin = const PinService();
  String _entered = '';
  String? _error;
  bool _checking = false;
  bool _done = false;

  int? get _length => _pin.length;
  int get _max => _length ?? PinService.maxLength;

  void _onDigit(String digit) {
    if (_done || _checking || _entered.length >= _max) return;
    setState(() {
      _entered += digit;
      _error = null;
    });
    final length = _length;
    if (length != null) {
      if (_entered.length == length) unawaited(_check(reportMismatch: true));
    } else if (_entered.length >= PinService.minLength) {
      unawaited(_check(reportMismatch: _entered.length == _max));
    }
  }

  void _onBackspace() {
    if (_done || _checking || _entered.isEmpty) return;
    setState(() {
      _entered = _entered.substring(0, _entered.length - 1);
      _error = null;
    });
  }

  Future<void> _check({required bool reportMismatch}) async {
    final attempt = _entered;
    if (reportMismatch) setState(() => _checking = true);
    bool ok;
    try {
      ok = await _pin.verify(attempt);
    } on PinUnavailableException {
      if (!mounted) return;
      unawaited(HapticFeedback.heavyImpact());
      setState(() {
        _checking = false;
        _error = widget.s.pinCheckFailed;
        _entered = '';
      });
      return;
    }
    if (!mounted) return;
    if (ok) {
      _done = true;
      setState(() => _checking = false);
      unawaited(HapticFeedback.mediumImpact());
      widget.onVerified();
      return;
    }
    // A silent try whose digits have since changed says nothing.
    if (!reportMismatch) return;
    unawaited(HapticFeedback.heavyImpact());
    setState(() {
      _checking = false;
      _error = widget.s.incorrectPin;
      _entered = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final showContinue = _length == null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        PinDots(length: _entered.length, error: _error != null, total: _max),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: WbColors.error, fontSize: 13),
            ),
          ),
        ],
        const SizedBox(height: 32),
        PinKeypad(onDigit: _onDigit, onBackspace: _onBackspace),
        if (showContinue) ...[
          const SizedBox(height: 16),
          SizedBox(
            width: 220,
            height: 48,
            child: FilledButton(
              onPressed: !_checking && _entered.length >= PinService.minLength
                  ? () => _check(reportMismatch: true)
                  : null,
              style: FilledButton.styleFrom(
                backgroundColor: context.accent,
                foregroundColor: WbColors.midnight,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: Text(widget.s.continueLabel),
            ),
          ),
        ],
      ],
    );
  }
}
