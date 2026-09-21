import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/wb_colors.dart';

/// Row of dots showing how many digits of a PIN have been entered so far —
/// shared between the lock screen and the PIN setup flow so both read as
/// the same control.
class PinDots extends StatelessWidget {
  const PinDots({super.key, required this.length, this.error = false});

  final int length;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final color = error ? WbColors.error : WbColors.waveCyan;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(6, (i) {
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
