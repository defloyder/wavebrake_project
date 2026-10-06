import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// P7: every user-facing string lives in AppStrings, in all 7 languages.
// Fails on (1) an empty value, (2) a translation whose {placeholders}
// differ from English, (3) a non-English value left identical to English
// (unless it is the same word in that language — the allowlist below),
// (4) Cyrillic text or Text('...')/label-like literals written straight
// into widgets instead of AppStrings.

const _blocks = {
  'en': 'const kEnglishStrings = AppStrings(',
  'ru': 'const kRussianStrings = AppStrings(',
  'es': 'const kSpanishStrings = AppStrings(',
  'de': 'const kGermanStrings = AppStrings(',
  'fr': 'const kFrenchStrings = AppStrings(',
  'pt': 'const kPortugueseStrings = AppStrings(',
  'tr': 'const kTurkishStrings = AppStrings(',
};

/// Keys whose English text is also correct in some other language
/// (brand names, units, words that are the same).
const _sameAsEnglishOk = {
  'languageName', 'faceIdTouchId', 'unitMs', 'unitMb', 'unitGb', 'mJitter',
  'mInternet', 'mStatus', 'mTabInfo', 'mTabRoute', 'mLive', 'densityNormal',
  'sphereMinimal', 'backgroundNormal', 'mTitle', 'unitMin',
  // The same word in that language (de Download/Version/Support, fr
  // Notifications/Session/Documents, pt Download/Interface, Auto, Test...).
  'auto', 'effectsAuto', 'navSpeedShort', 'speedTestDownload',
  'speedTestUpload', 'support', 'version', 'updates', 'groupRouting',
  'groupSystem', 'groupMotion', 'protectOn', 'notifications', 'sessionTitle',
  'groupLegal', 'groupInterface',
};

Map<String, Map<String, String>> _readStrings() {
  final lines = File('lib/core/i18n/app_strings.dart').readAsLinesSync();
  final out = <String, Map<String, String>>{};
  String? lang;
  String? key;
  final buffer = StringBuffer();
  final literal = RegExp(r"'((?:[^'\\]|\\.)*)'" '|' r'"((?:[^"\\]|\\.)*)"');

  void flush() {
    if (lang != null && key != null) {
      final text = buffer.toString();
      out[lang]![key!] = literal
          .allMatches(text)
          .map((m) => m.group(1) ?? m.group(2) ?? '')
          .join();
    }
    key = null;
    buffer.clear();
  }

  for (final line in lines) {
    final start = _blocks.entries.where((e) => line == e.value);
    if (start.isNotEmpty) {
      lang = start.first.key;
      out[lang] = {};
      continue;
    }
    if (lang == null) continue;
    if (line == ');') {
      flush();
      lang = null;
      continue;
    }
    final m = RegExp(r'^  (\w+):(.*)$').firstMatch(line);
    if (m != null) {
      flush();
      key = m.group(1);
      buffer.write(m.group(2));
    } else {
      buffer.write(line);
    }
  }
  return out;
}

Set<String> _placeholders(String s) =>
    RegExp(r'\{(\w+)\}').allMatches(s).map((m) => m.group(1)!).toSet();

void main() {
  final strings = _readStrings();

  test('all 7 languages have the same keys', () {
    final en = strings['en']!.keys.toSet();
    expect(en, isNotEmpty);
    for (final lang in _blocks.keys) {
      expect(strings[lang]!.keys.toSet(), en, reason: '$lang keys');
    }
  });

  test('no empty values, placeholders match English', () {
    final problems = <String>[];
    final en = strings['en']!;
    for (final lang in _blocks.keys) {
      strings[lang]!.forEach((key, value) {
        if (value.trim().isEmpty) problems.add('$lang.$key is empty');
        final want = _placeholders(en[key] ?? '');
        if (_placeholders(value).difference(want).isNotEmpty ||
            want.difference(_placeholders(value)).isNotEmpty) {
          problems.add('$lang.$key placeholders ${_placeholders(value)} != $want');
        }
      });
    }
    expect(problems, isEmpty, reason: problems.join('\n'));
  });

  test('no translation left in English', () {
    final en = strings['en']!;
    final problems = <String>[];
    for (final lang in _blocks.keys.where((l) => l != 'en')) {
      strings[lang]!.forEach((key, value) {
        if (_sameAsEnglishOk.contains(key)) return;
        if (value == en[key] && RegExp('[A-Za-z]{3}').hasMatch(value)) {
          problems.add('$lang.$key = "$value"');
        }
      });
    }
    expect(problems, isEmpty, reason: problems.join('\n'));
  });

  test('no user-facing text hardcoded in widgets', () {
    final cyrillic = RegExp('[Ѐ-ӿ]');
    // Literals passed straight to a visible text slot.
    final visible = RegExp(
        r'''(?:Text\(|title:|label:|subtitle:|hintText:|tooltip:|labelText:|message:)\s*['"]([^'"$]*[A-Za-z]{3}[^'"]*)['"]''');
    // Brand names, and examples of link formats (not words).
    const allowedLiterals = {'WAVEBREAK', 'OK', 'Google', 'Telegram'};
    final problems = <String>[];
    for (final file in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      final path = file.path.replaceAll('\\', '/');
      if (path.endsWith('core/i18n/app_strings.dart')) continue;
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        final code = line.trimLeft();
        if (code.startsWith('//') || code.startsWith('///')) continue;
        final noComment = line.split(' // ').first;
        if (cyrillic.hasMatch(noComment)) {
          problems.add('$path:${i + 1}: Cyrillic: ${code.trim()}');
        }
        for (final m in visible.allMatches(noComment)) {
          final text = m.group(1)!;
          if (allowedLiterals.contains(text) ||
              text.startsWith('WAVEBREAK ') ||
              text.contains('://')) {
            continue;
          }
          problems.add('$path:${i + 1}: literal "${m.group(1)}"');
        }
      }
    }
    expect(problems, isEmpty, reason: problems.join('\n'));
  });
}
