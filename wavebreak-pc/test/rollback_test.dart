import 'package:flutter_test/flutter_test.dart';

import 'package:wavebreak/services/update/update_service.dart';

void main() {
  test('a rollback entry is read only when it is complete and goes up', () {
    final ok = RollbackInfo.fromJson({
      'fromVersionCode': 20,
      'versionCode': 21,
      'versionName': '1.1.7',
      'url': 'https://example.test/rollback.apk',
    });
    expect(ok, isNotNull);
    expect(ok!.asUpdate.versionCode, 21);
    expect(ok.asUpdate.versionName, '1.1.7');

    // Android can't install a lower versionCode: such an entry is ignored.
    expect(RollbackInfo.fromJson({'fromVersionCode': 20, 'versionCode': 19, 'url': 'u'}), isNull);
    expect(RollbackInfo.fromJson({'fromVersionCode': 20, 'versionCode': 21}), isNull);
    expect(RollbackInfo.fromJson(null), isNull);
    expect(RollbackInfo.fromJson('x'), isNull);
  });
}
