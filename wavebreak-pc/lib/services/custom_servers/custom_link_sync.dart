import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../core/logging/app_logger.dart';
import '../../core/storage/prefs_store.dart';
import '../providers.dart';
import 'custom_server_controller.dart';

/// One of the user's own links in the synced list: when it was added and,
/// once removed on some device, when.
class LinkEntry {
  const LinkEntry(this.link, this.added, [this.removed]);

  final String link;
  final DateTime added;
  final DateTime? removed;

  DateTime get changed => removed ?? added;
  String get key => CustomServerController.sameLinkKey(link);

  Map<String, dynamic> toJson() => {
        'link': link,
        'added': added.toUtc().toIso8601String(),
        if (removed != null) 'removed': removed!.toUtc().toIso8601String(),
      };

  static LinkEntry? fromJson(Object? j) {
    if (j is! Map) return null;
    final link = j['link'];
    final added = DateTime.tryParse('${j['added']}');
    if (link is! String || link.isEmpty || added == null) return null;
    return LinkEntry(link, added, DateTime.tryParse('${j['removed'] ?? ''}'));
  }
}

/// The synced list as Core keeps it ([version] guards concurrent writes).
class LinkDoc {
  const LinkDoc(this.version, this.entries);

  final int version;
  final List<LinkEntry> entries;

  static const empty = LinkDoc(0, []);

  Map<String, dynamic> toJson() => {
        'version': version,
        'entries': [for (final e in entries) e.toJson()],
      };

  static LinkDoc fromJson(Object? j) {
    if (j is! Map) return empty;
    final raw = j['entries'];
    return LinkDoc(
      (j['version'] as num?)?.toInt() ?? 0,
      [
        if (raw is List)
          for (final e in raw)
            if (LinkEntry.fromJson(e) case final entry?) entry,
      ],
    );
  }
}

/// Removals are remembered this long so every device hears of them.
const _tombstoneKeep = Duration(days: 60);

/// The two lists as one: per link the latest change wins (a removal over
/// an add made at the same moment); removals older than 60 days dropped.
List<LinkEntry> mergeLinkEntries(
    Iterable<LinkEntry> a, Iterable<LinkEntry> b, DateTime now) {
  final byKey = <String, LinkEntry>{};
  for (final e in [...a, ...b]) {
    final prev = byKey[e.key];
    if (prev == null ||
        e.changed.isAfter(prev.changed) ||
        (e.changed.isAtSameMomentAs(prev.changed) && e.removed != null)) {
      byKey[e.key] = e;
    }
  }
  return [
    for (final e in byKey.values)
      if (e.removed == null || now.difference(e.removed!) < _tombstoneKeep) e,
  ];
}

/// This device's view as entries: what it synced last time, with links
/// removed here since marked removed and links added here since added.
List<LinkEntry> localLinkEntries(
    List<LinkEntry> lastSynced, Iterable<String> localLinks, DateTime now) {
  final local = {
    for (final l in localLinks) CustomServerController.sameLinkKey(l): l
  };
  final out = <LinkEntry>[];
  final seen = <String>{};
  for (final e in lastSynced) {
    seen.add(e.key);
    final here = local.containsKey(e.key);
    if (e.removed == null && !here) {
      out.add(LinkEntry(e.link, e.added, now));
    } else if (e.removed != null && here) {
      out.add(LinkEntry(local[e.key]!, now));
    } else {
      out.add(e);
    }
  }
  for (final MapEntry(:key, :value) in local.entries) {
    if (!seen.contains(key)) out.add(LinkEntry(value, now));
  }
  return out;
}

/// "Sync my links" (owner, 15.10; off by default): the links and
/// subscriptions added by hand reach every device of the account, removals
/// too. Core keeps them sealed (GET/PUT /v1/me/custom-links). Shared
/// subscriptions (share codes) aren't part of it — they hold a device slot.
class CustomLinkSync {
  CustomLinkSync(this._ref);

  final Ref _ref;
  bool _running = false;
  bool _again = false;
  Timer? _debounce;

  static bool get enabled => PrefsStore.getBool(PrefsStore.syncCustomLinks);

  static LinkDoc get _saved {
    final raw = PrefsStore.getString(PrefsStore.customLinksSynced);
    if (raw == null || raw.isEmpty) return LinkDoc.empty;
    try {
      return LinkDoc.fromJson(jsonDecode(raw));
    } catch (_) {
      return LinkDoc.empty;
    }
  }

  /// After a local add or removal: soon, once.
  void schedule() {
    if (!enabled) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), () => unawaited(sync()));
  }

  Future<void> setEnabled(bool on) async {
    await PrefsStore.setBool(PrefsStore.syncCustomLinks, on);
    if (on) {
      await sync();
    } else {
      // Off: forget what was synced; turning it on again starts from this
      // device's own list.
      await PrefsStore.setString(PrefsStore.customLinksSynced, null);
    }
  }

  Future<void> sync() async {
    if (!enabled || PrefsStore.getBool(PrefsStore.guestMode)) return;
    if (_running) {
      _again = true;
      return;
    }
    _running = true;
    try {
      await _syncOnce();
    } catch (e) {
      AppLogger.warn('link sync failed: $e');
    } finally {
      _running = false;
      if (_again) {
        _again = false;
        unawaited(sync());
      }
    }
  }

  Future<void> _syncOnce() async {
    final gateway = _ref.read(coreGatewayProvider);
    final servers = _ref.read(customServersProvider.notifier);
    List<String> localLinks() => [
          for (final g in _ref.read(customServersProvider))
            if (!g.sharedWithMe) g.sourceLink,
        ];
    final now = DateTime.now().toUtc();
    final mine = localLinkEntries(_saved.entries, localLinks(), now);

    LinkDoc? stored;
    List<LinkEntry> merged = mine;
    for (var attempt = 0; attempt < 3 && stored == null; attempt++) {
      final remote = LinkDoc.fromJson(await gateway.customLinks());
      merged = mergeLinkEntries(mine, remote.entries, now);
      try {
        final version = await gateway
            .putCustomLinks(LinkDoc(remote.version, merged).toJson());
        stored = LinkDoc(version, merged);
      } on AppException catch (e) {
        if (e.statusCode != 409) rethrow; // another device wrote first
      }
    }
    if (stored == null) return;

    // This device catches up: links added elsewhere are added here, links
    // removed elsewhere removed here.
    final here = {
      for (final l in localLinks()) CustomServerController.sameLinkKey(l)
    };
    for (final e in merged) {
      if (e.removed == null && !here.contains(e.key)) {
        final error = await servers.addFromLink(e.link, fromSync: true);
        if (error != null && error != 'duplicate') {
          AppLogger.warn('link sync: could not add a synced link ($error)');
        }
      } else if (e.removed != null && here.contains(e.key)) {
        for (final g in [..._ref.read(customServersProvider)]) {
          if (!g.sharedWithMe &&
              CustomServerController.sameLinkKey(g.sourceLink) == e.key) {
            await servers.removeGroup(g.id, fromSync: true);
          }
        }
      }
    }
    // Remembered as synced: only what this device really has (and the
    // removals). A link that couldn't be added here now (its server
    // unreachable) must not read as "removed here" next time — it's simply
    // tried again.
    final hereNow = {
      for (final l in localLinks()) CustomServerController.sameLinkKey(l)
    };
    final kept = LinkDoc(stored.version, [
      for (final e in merged)
        if (e.removed != null || hereNow.contains(e.key)) e,
    ]);
    await PrefsStore.setString(
        PrefsStore.customLinksSynced, jsonEncode(kept.toJson()));
  }
}

final customLinkSyncProvider = Provider<CustomLinkSync>((ref) {
  final sync = CustomLinkSync(ref);
  ref.onDispose(() => sync._debounce?.cancel());
  return sync;
});
