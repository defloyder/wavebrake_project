import 'package:flutter_test/flutter_test.dart';
import 'package:wavebreak/core/i18n/app_strings.dart';
import 'package:wavebreak/features/settings/about_screen.dart';

void main() {
  test('legal pages open on the site in the app language', () {
    expect(legalPageUrl('privacy', AppLanguage.ru),
        'https://wavebreak.com.tr/privacy');
    expect(legalPageUrl('terms', AppLanguage.tr),
        'https://wavebreak.com.tr/tr/terms');
    expect(legalPageUrl('privacy', AppLanguage.de),
        'https://wavebreak.com.tr/en/privacy');
  });
}
