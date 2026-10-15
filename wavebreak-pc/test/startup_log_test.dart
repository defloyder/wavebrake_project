import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wavebreak/app/startup_error.dart';
import 'package:wavebreak/core/logging/file_log.dart';

void main() {
  test('the start-up log lands in %LOCALAPPDATA%/WAVEBREAK/logs', () {
    FileLog.init();
    final marker = 'test-marker-${DateTime.now().microsecondsSinceEpoch}';
    FileLog.write(marker);
    expect(FileLog.path, isNotNull);
    expect(FileLog.path!, contains('WAVEBREAK'));
    expect(File(FileLog.path!).readAsStringSync(), contains(marker));
  });

  testWidgets('a failed start shows the error and the logs folder',
      (tester) async {
    await tester.pumpWidget(const StartupErrorApp(error: 'boom'));
    expect(find.textContaining('WAVEBREAK'), findsWidgets);
    expect(find.text(FileLog.directory), findsOneWidget);
    expect(find.textContaining('boom'), findsOneWidget);
  });
}
