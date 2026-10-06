import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/bootstrap.dart';
import 'core/perf/frame_log.dart';

Future<void> main() async {
  await bootstrap();
  // Not awaited: when the Quick Settings tile wakes the process there is
  // no window yet, the engine never answers this call, and an await here
  // hung main() for good — the tile did nothing and the app opened to a
  // black screen (owner, 06.10).
  unawaited(SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]));
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF0B1020),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const ProviderScope(child: WavebreakApp()));
  startFrameLog();
}
