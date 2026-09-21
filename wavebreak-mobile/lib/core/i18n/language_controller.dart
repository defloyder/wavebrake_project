import 'dart:ui' show PlatformDispatcher;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/prefs_store.dart';
import 'app_strings.dart';

final languageProvider =
    NotifierProvider<LanguageController, AppLanguage>(LanguageController.new);

final stringsProvider = Provider<AppStrings>((ref) {
  return stringsFor(ref.watch(languageProvider));
});

class LanguageController extends Notifier<AppLanguage> {
  @override
  AppLanguage build() {
    final saved = PrefsStore.getString(PrefsStore.language);
    if (saved != null) {
      return AppLanguage.values.firstWhere(
        (lang) => lang.name == saved,
        orElse: () => AppLanguage.ru,
      );
    }
    // No preference saved yet — a fresh install follows the device's own
    // language when it's one we support, and falls back to Russian
    // (not English) otherwise, matching where this product actually
    // launched first.
    final deviceCode = PlatformDispatcher.instance.locale.languageCode;
    return AppLanguage.values.firstWhere(
      (lang) => lang.name == deviceCode,
      orElse: () => AppLanguage.ru,
    );
  }

  Future<void> setLanguage(AppLanguage language) async {
    state = language;
    await PrefsStore.setString(PrefsStore.language, language.name);
  }
}
