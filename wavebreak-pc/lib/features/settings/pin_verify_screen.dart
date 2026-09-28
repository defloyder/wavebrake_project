import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/language_controller.dart';
import '../../core/theme/wb_colors.dart';
import '../shared/ocean_background.dart';
import '../shared/pin_keypad.dart';

/// Asks for the CURRENT PIN before a sensitive change (bug 7: changing or
/// removing the PIN used to need no proof at all). Pops `true` only when
/// the entered PIN matches; `null` if the user backs out.
Future<bool?> showPinVerifyScreen(BuildContext context) {
  return Navigator.of(context, rootNavigator: true).push<bool>(
    MaterialPageRoute(builder: (_) => const _PinVerifyScreen()),
  );
}

class _PinVerifyScreen extends ConsumerStatefulWidget {
  const _PinVerifyScreen();

  @override
  ConsumerState<_PinVerifyScreen> createState() => _PinVerifyScreenState();
}

class _PinVerifyScreenState extends ConsumerState<_PinVerifyScreen> {
  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    return Scaffold(
      backgroundColor: WbColors.midnight,
      body: OceanBackground(
        illuminate: true,
        child: SafeArea(
          child: Column(
            children: [
              Align(
                alignment: Alignment.topRight,
                child: IconButton(
                  icon: const Icon(Icons.close_rounded, color: WbColors.ice60),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                s.enterPin,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              PinEntry(s: s, onVerified: () => Navigator.of(context).pop(true)),
              const Spacer(),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
