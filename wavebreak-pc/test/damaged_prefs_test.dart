import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wavebreak/app/bootstrap.dart';

void main() {
  test('a zeroed settings file is what broke the start, and it is set aside',
      () async {
    final dir = await Directory.systemTemp.createTemp('wb-prefs');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/shared_preferences.json');
    // What a power cut leaves: the file's length, no content.
    file.writeAsBytesSync(List.filled(240, 0));
    // The same decode shared_preferences_windows does on start.
    expect(() => json.decode(file.readAsStringSync()),
        throwsA(isA<FormatException>()));

    final moved = await setAsideDamagedPrefs(dir: dir);
    expect(moved, contains('shared_preferences.damaged-'));
    expect(file.existsSync(), isFalse);
    expect(File(moved!).lengthSync(), 240);
    // Nothing to move the second time.
    expect(await setAsideDamagedPrefs(dir: dir), isNull);
  });
}
