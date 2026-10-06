import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/bootstrap.dart';
import 'features/tv/tv_app.dart';

/// Dedicated entry point; the phone application keeps its portrait UI.
Future<void> main() async {
  await bootstrap();
  runApp(const ProviderScope(child: WavebreakTvApp()));
}
