import 'dart:io';

// ignore: depend_on_referenced_packages
import 'package:fake_async/fake_async.dart';
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

  test('after start-up lines are written in batches; errors at once', () {
    fakeAsync((async) {
      FileLog.init();
      FileLog.startBuffering();
      final file = File(FileLog.path!);
      final stamp = DateTime.now().microsecondsSinceEpoch;
      FileLog.write('batched-a-$stamp');
      FileLog.write('batched-b-$stamp');
      expect(file.readAsStringSync(), isNot(contains('batched-a-$stamp')));
      async.elapse(const Duration(milliseconds: 600));
      final text = file.readAsStringSync();
      expect(text, contains('batched-a-$stamp'));
      expect(text, contains('batched-b-$stamp'));

      FileLog.write('pending-$stamp');
      FileLog.writeNow('fatal-$stamp');
      final now = file.readAsStringSync();
      expect(now, contains('pending-$stamp'));
      expect(now, contains('fatal-$stamp'));
    });
  });
}
