import 'dart:async';
import 'dart:io';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/bootstrap.dart';
import 'app/startup_error.dart';
import 'core/logging/file_log.dart';

/// Start-up with a log from the very first line: a start that fails on
/// some machine (field report: a white window, no logs) leaves
/// %LOCALAPPDATA%\WAVEBREAK\logs\wavebreak-*.log and shows an error screen
/// with that path instead of a blank window.
Future<void> main() async {
  FileLog.init();
  FileLog.write('--- start: ${Platform.operatingSystemVersion}, '
      '${Platform.numberOfProcessors} CPUs, locale ${Platform.localeName}');
  var showedError = false;
  void fail(String where, Object error, StackTrace? stack) {
    FileLog.write('FATAL ($where): $error\n$stack');
    if (showedError) return;
    showedError = true;
    runApp(StartupErrorApp(error: '$where: $error'));
  }

  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    FileLog.write('binding ready');
    FlutterError.onError = (details) {
      FileLog.write('UI error: ${details.exceptionAsString()}\n${details.stack}');
      FlutterError.presentError(details);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      FileLog.write('Uncaught: $error\n$stack');
      return true;
    };
    // A widget that fails to build shows the reason and the log path, not
    // the grey release box (which looked like a blank white window).
    ErrorWidget.builder =
        (details) => StartupErrorView(error: details.exceptionAsString());

    try {
      await bootstrap().timeout(const Duration(seconds: 20));
    } catch (e, s) {
      fail('bootstrap', e, s);
      return;
    }
    FileLog.write('bootstrap done');
    try {
      await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
      SystemChrome.setSystemUIOverlayStyle(
        const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          systemNavigationBarColor: Color(0xFF0B1020),
          systemNavigationBarIconBrightness: Brightness.light,
        ),
      );
    } catch (e) {
      FileLog.write('system chrome skipped: $e');
    }

    var firstFrame = false;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      firstFrame = true;
      FileLog.write('first frame');
    });
    runApp(const ProviderScope(child: WavebreakApp()));
    FileLog.write('runApp');
    Timer(const Duration(seconds: 15), () {
      if (!firstFrame) {
        fail('first frame', 'no frame in 15 s (GPU or a blocked start)', null);
      }
    });
  }, (error, stack) => fail('zone', error, stack));
}
