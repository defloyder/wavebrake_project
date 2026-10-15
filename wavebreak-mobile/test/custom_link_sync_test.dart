import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wavebreak/core/storage/prefs_store.dart';
import 'package:wavebreak/services/core_api/mock_backend.dart';
import 'package:wavebreak/services/custom_servers/custom_link_sync.dart';
import 'package:wavebreak/services/custom_servers/custom_server_controller.dart';

import 'test_helpers.dart';

final t0 = DateTime.utc(2026, 10, 15, 12);
DateTime at(int minutes) => t0.add(Duration(minutes: minutes));

void main() {
  twoDevices();
  group('merge: the latest change per link wins', () {
    test('links added on different devices both stay', () {
      final merged = mergeLinkEntries(
        [LinkEntry('vless://a@h:1#A', at(0))],
        [LinkEntry('trojan://b@h:2#B', at(1))],
        at(2),
      );
      expect([for (final e in merged) e.link],
          ['vless://a@h:1#A', 'trojan://b@h:2#B']);
    });

    test('a removal after the add reaches the other device', () {
      final merged = mergeLinkEntries(
        [LinkEntry('vless://a@h:1', at(0), at(5))],
        [LinkEntry('vless://a@h:1', at(0))],
        at(6),
      );
      expect(merged.single.removed, at(5));
    });

    test('added again after the removal: back', () {
      final merged = mergeLinkEntries(
        [LinkEntry('vless://a@h:1', at(0), at(5))],
        [LinkEntry('vless://a@h:1', at(7))],
        at(8),
      );
      expect(merged.single.removed, isNull);
    });

    test('the same link under another #name is one link', () {
      final merged = mergeLinkEntries(
        [LinkEntry('vless://a@h:1#Germany', at(0))],
        [LinkEntry('vless://a@h:1#DE', at(1))],
        at(2),
      );
      expect(merged, hasLength(1));
    });

    test('old removals are forgotten after 60 days', () {
      final merged = mergeLinkEntries(
          [LinkEntry('vless://a@h:1', at(0), at(1))],
          [],
          at(1).add(const Duration(days: 61)));
      expect(merged, isEmpty);
    });
  });

  group("this device's changes since the last sync", () {
    test('a link removed here is marked removed', () {
      final mine = localLinkEntries(
          [LinkEntry('vless://a@h:1', at(0))], const [], at(10));
      expect(mine.single.removed, at(10));
    });

    test('a link added here is added', () {
      final mine =
          localLinkEntries(const [], ['https://sub.example/x'], at(10));
      expect(mine.single.link, 'https://sub.example/x');
      expect(mine.single.added, at(10));
      expect(mine.single.removed, isNull);
    });

    test('unchanged stays as it was', () {
      final e = LinkEntry('vless://a@h:1', at(0));
      expect(
          localLinkEntries([e], ['vless://a@h:1'], at(10)).single.added, at(0));
    });
  });

  test('document round trip', () {
    final doc = LinkDoc(3, [
      LinkEntry('vless://a@h:1', at(0)),
      LinkEntry('vless://b@h:1', at(0), at(2)),
    ]);
    final back = LinkDoc.fromJson(doc.toJson());
    expect(back.version, 3);
    expect(back.entries[1].removed, at(2));
    expect(
        LinkDoc.fromJson({
          'version': 1,
          'entries': [
            {'link': ''}
          ]
        }).entries,
        isEmpty);
  });
}

/// Two devices of one account, one after the other on this test's single
/// storage: a fresh storage is the second device.
void twoDevices() {
  test('a link added on one device reaches the other; a removal comes back',
      () async {
    final backend = MockCoreBackend();
    ProviderContainer device() {
      final c = ProviderContainer(overrides: mockCoreOverrides(backend));
      addTearDown(c.dispose);
      return c;
    }

    // Device A: sync on, a link added.
    await setUpTestEnvironment();
    await PrefsStore.setBool(PrefsStore.syncCustomLinks, true);
    final a = device();
    expect(
        await a
            .read(customServersProvider.notifier)
            .addFromLink('vless://u@de.example:443?security=tls#Germany'),
        isNull);
    await a.read(customLinkSyncProvider).sync();
    expect((backend.customLinksDoc['entries'] as List), hasLength(1));

    // Device B: nothing of its own; turning sync on brings the link.
    await setUpTestEnvironment();
    final b = device();
    await b.read(customLinkSyncProvider).setEnabled(true);
    final onB = b.read(customServersProvider);
    expect(onB, hasLength(1));
    expect(onB.single.sourceLink, contains('de.example'));

    // Removed on B: the server's list says removed, for A to follow.
    await b
        .read(customServersProvider.notifier)
        .removeGroup(onB.single.id, fromSync: true);
    await b.read(customLinkSyncProvider).sync();
    final entries = backend.customLinksDoc['entries'] as List;
    expect(entries, hasLength(1));
    expect((entries.single as Map)['removed'], isNotNull);
  });
}
