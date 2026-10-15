import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wavebreak/core/storage/prefs_store.dart';
import 'package:wavebreak/features/settings/split_tunnel_screen.dart';
import 'package:wavebreak/services/split_tunnel/split_tunnel.dart';

import 'test_helpers.dart';

class _FakeStore implements SplitTunnelStore {
  _FakeStore(this._apps, this.saved, this._always);
  final List<SplitApp> _apps;
  Set<String> saved;
  final Set<String> _always;
  int saves = 0;

  @override
  Future<List<SplitApp>> apps() async => _apps;
  @override
  Future<Set<String>> load() async => {...saved};
  @override
  Future<void> save(Set<String> ids) async {
    saved = {...ids};
    saves++;
  }

  @override
  Future<Set<String>> alwaysDirect() async => _always;
}

void main() {
  setUp(setUpTestEnvironment);

  group('Windows program names', () {
    test('file names, lower-case, with .exe, once, sorted', () {
      expect(
        normalizeProcessNames([
          r'C:\Program Files\Google\Chrome\Application\Chrome.EXE',
          ' telegram ',
          '"Discord.exe"',
          'chrome.exe',
          '',
          '   ',
        ]),
        ['chrome.exe', 'discord.exe', 'telegram.exe'],
      );
    });

    test("WAVEBREAK's own programs are never sent past its tunnel", () {
      expect(
        normalizeProcessNames([
          'wavebreak.exe',
          'sing-box',
          'xray.exe',
          'cloak-client-proxy.exe',
          'steam.exe'
        ]),
        ['steam.exe'],
      );
    });

    test('saved programs feed the sing-box start', () async {
      await PrefsStore.setStringList(
          PrefsStore.splitBypassProcesses, ['Steam.exe', 'telegram']);
      expect(SplitTunnelStore.savedProcesses(), ['steam.exe', 'telegram.exe']);
    });
  });

  group('Windows app listing', () {
    test('one object or an array; icons decoded; own programs dropped', () {
      final icon = base64Encode([1, 2, 3]);
      final one = parseWindowsApps(jsonEncode(
          {'name': 'Telegram.exe', 'label': 'Telegram Desktop', 'icon': icon}));
      expect(one.single.id, 'telegram.exe');
      expect(one.single.label, 'Telegram Desktop');
      expect(one.single.icon, Uint8List.fromList([1, 2, 3]));

      final many = parseWindowsApps(jsonEncode([
        {'name': 'wavebreak.exe', 'label': 'WAVEBREAK'},
        {'name': 'steam.exe', 'label': ''},
        {'name': 'chrome.exe', 'label': 'Google Chrome', 'icon': 'not base64!'},
        {'name': 'chrome.exe', 'label': 'Google Chrome'},
      ]));
      expect([for (final a in many) a.id], ['chrome.exe', 'steam.exe']);
      expect(many.last.label, 'steam.exe');
      expect(many.first.icon, isNull);
    });

    test('garbage or nothing lists nothing', () {
      expect(parseWindowsApps(''), isEmpty);
      expect(parseWindowsApps('Get-Process : access denied'), isEmpty);
    });

    test('saved programs that are not running are still listed', () {
      final merged = mergeSavedPrograms(
          [const SplitApp(id: 'chrome.exe', label: 'Google Chrome')],
          ['chrome.exe', 'steam.exe']);
      expect([for (final a in merged) a.id], ['chrome.exe', 'steam.exe']);
    });
  });

  group('screen', () {
    Future<_FakeStore> pump(WidgetTester tester, _FakeStore store) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [splitTunnelStoreProvider.overrideWithValue(store)],
        child: const MaterialApp(home: SplitTunnelScreen()),
      ));
      await _frames(tester);
      return store;
    }

    final apps = [
      const SplitApp(id: 'ru.sberbankmobile', label: 'СберБанк'),
      const SplitApp(id: 'org.telegram.messenger', label: 'Telegram'),
      const SplitApp(id: 'com.wildberries.ru', label: 'Wildberries'),
      const SplitApp(
          id: 'com.android.settings', label: 'Settings', system: true),
    ];

    testWidgets('switching an app off sends it directly and saves at once',
        (tester) async {
      final store =
          await pump(tester, _FakeStore(apps, {}, {'com.wildberries.ru'}));
      // System apps hidden until asked for.
      expect(find.text('Settings'), findsNothing);

      final sber = find.ancestor(
          of: find.text('СберБанк'), matching: find.byType(InkWell));
      await tester.tap(sber.first);
      await _frames(tester);
      expect(store.saved, {'ru.sberbankmobile'});
      expect(store.saves, 1);

      await tester.tap(find
          .ancestor(of: find.text('СберБанк'), matching: find.byType(InkWell))
          .first);
      await _frames(tester);
      expect(store.saved, isEmpty);
    });

    testWidgets('built-in direct apps are locked', (tester) async {
      final store =
          await pump(tester, _FakeStore(apps, {}, {'com.wildberries.ru'}));
      await tester.tap(find.text('Wildberries'));
      await _frames(tester);
      expect(store.saves, 0);
      expect(find.text('Always directly: it refuses to work with a VPN'),
          findsOneWidget);
    });

    testWidgets('search narrows the list', (tester) async {
      await pump(tester, _FakeStore(apps, {}, {}));
      await tester.enterText(find.byType(TextField).first, 'tele');
      await _frames(tester);
      expect(find.text('Telegram'), findsOneWidget);
      expect(find.text('СберБанк'), findsNothing);
    });
  });
}

/// The page's ocean background never settles: a few frames instead.
Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}
