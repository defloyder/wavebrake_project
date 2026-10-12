import 'package:flutter_test/flutter_test.dart';
import 'package:wavebreak/core/i18n/app_strings.dart';

void main() {
  test('days left agree with the number (owner list, 12.10)', () {
    final ru = stringsFor(AppLanguage.ru);
    expect(ru.daysLeft(1), '1 день остался');
    expect(ru.daysLeft(21), '21 день остался');
    expect(ru.daysLeft(2), '2 дня осталось');
    expect(ru.daysLeft(4), '4 дня осталось');
    expect(ru.daysLeft(5), '5 дней осталось');
    expect(ru.daysLeft(11), '11 дней осталось');
    expect(ru.daysLeft(12), '12 дней осталось');
    expect(ru.daysLeft(0), '0 дней осталось');
    final en = stringsFor(AppLanguage.en);
    expect(en.daysLeft(1), '1 day remaining');
    expect(en.daysLeft(30), '30 days remaining');
    for (final l in AppLanguage.values) {
      expect(stringsFor(l).daysLeft(7), startsWith('7 '), reason: l.name);
    }
  });
}
