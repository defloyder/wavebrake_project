import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/i18n/app_strings.dart';
import '../../core/theme/wb_colors.dart';

/// Full-screen QR scanner. Pops with the raw scanned string as soon as one
/// barcode is recognized, or null if the user backs out. Needs a real
/// camera — verify on an actual Android/iOS device, not a desktop browser.
class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key, required this.s});

  final AppStrings s;

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  // A previous attempt here explicitly requested a modest cameraResolution
  // (1280x720), on the theory that CameraX's default "highest supported"
  // selection was asking for a stream combination this device's HAL
  // doesn't support. Confirmed on-device that was wrong: it didn't fix
  // anything and the detailed error view (below) showed it hit a DIFFERENT
  // native NullPointerException inside mobile_scanner's own resolution
  // code (`getResolution()` in MobileScanner.kt) instead — worse, not
  // better. Left at the package default here; see the real error surfaced
  // by errorBuilder below for whatever this device is actually hitting.
  MobileScannerController _newController() => MobileScannerController();

  late MobileScannerController _controller = _newController();
  bool _handled = false;
  MobileScannerException? _error;
  bool _errorReported = false;

  void _onDetect(BarcodeCapture capture) {
    if (_handled || capture.barcodes.isEmpty) return;
    final value = capture.barcodes.first.rawValue;
    if (value == null || value.isEmpty) return;
    _handled = true;
    Navigator.of(context).pop(value);
  }

  void _onError(BuildContext context, MobileScannerException error) {
    // Reported via the ValueListenable the widget already watches, not a
    // callback — recorded here purely so retry can tell the user something
    // more useful than the package's own generic label. Guarded by
    // _errorReported: errorBuilder runs on every rebuild while an error is
    // active, and scheduling a fresh setState from each one (via a fresh
    // postFrameCallback) would rebuild forever instead of settling.
    if (!mounted || _errorReported) return;
    _errorReported = true;
    setState(() => _error = error);
  }

  Future<void> _retry() async {
    final old = _controller;
    setState(() {
      _error = null;
      _errorReported = false;
      _controller = _newController();
    });
    await old.dispose();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WbColors.midnight,
      appBar: AppBar(
        backgroundColor: WbColors.midnight,
        title: Text(widget.s.qrCode),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            key: ValueKey(_controller),
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) {
              // Deferred out of build(): MobileScanner's own
              // ValueListenableBuilder is what surfaces this error, so
              // calling setState from directly inside its builder would
              // rebuild the same widget while Flutter is still building it.
              WidgetsBinding.instance
                  .addPostFrameCallback((_) => _onError(context, error));
              return _ScanErrorView(
                s: widget.s,
                error: error,
                onRetry: _retry,
              );
            },
          ),
          if (_error == null)
            Center(
              child: Container(
                width: 240,
                height: 240,
                decoration: BoxDecoration(
                  border: Border.all(color: WbColors.waveCyan, width: 2),
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ScanErrorView extends StatelessWidget {
  const _ScanErrorView({required this.s, required this.error, required this.onRetry});

  final AppStrings s;
  final MobileScannerException error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final detail = error.errorDetails?.message;
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.videocam_off_rounded, color: WbColors.ice60, size: 40),
              const SizedBox(height: 16),
              Text(
                error.errorCode.message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: WbColors.ice),
              ),
              if (detail != null && detail.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  detail,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: WbColors.ice60, fontSize: 12),
                ),
              ],
              const SizedBox(height: 20),
              OutlinedButton(
                onPressed: onRetry,
                child: Text(s.tryAgain),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
