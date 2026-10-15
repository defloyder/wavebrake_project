import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/prefs_store.dart';

/// One app the user can send past the tunnel: an Android package or a
/// Windows program ("chrome.exe").
class SplitApp {
  const SplitApp({
    required this.id,
    required this.label,
    this.icon,
    this.system = false,
  });

  final String id;
  final String label;
  final Uint8List? icon;

  /// Came with the phone (hidden unless asked for).
  final bool system;
}

/// Split tunneling (owner, 15.10; like Happ): which apps go directly,
/// not through the VPN. Applies when the tunnel is (re)started.
///
/// - Android: per app, by package — VpnService's addDisallowedApplication;
///   the choice lives natively (SplitTunnel.kt) so the VPN service reads it
///   even when started by the Quick Settings tile. Wildberries and Ozon are
///   always direct (they refuse to work behind a VPN).
/// - Windows: per program, by process name — a sing-box route rule. Not on
///   the Xray beta engine.
abstract class SplitTunnelStore {
  Future<List<SplitApp>> apps();
  Future<Set<String>> load();
  Future<void> save(Set<String> ids);

  /// Always direct, whatever the user picks.
  Future<Set<String>> alwaysDirect();

  /// The Windows programs saved for the next sing-box start (read
  /// synchronously while the config is written).
  static List<String> savedProcesses() => normalizeProcessNames(
      PrefsStore.getStringList(PrefsStore.splitBypassProcesses));
}

final splitTunnelStoreProvider = Provider<SplitTunnelStore>(
    (ref) => Platform.isWindows ? WindowsSplitTunnel() : AndroidSplitTunnel());

class AndroidSplitTunnel implements SplitTunnelStore {
  static const _channel = MethodChannel('app.wavebreak/split');

  @override
  Future<List<SplitApp>> apps() async {
    final raw = await _channel.invokeListMethod<Map>('installedApps') ?? [];
    return [
      for (final m in raw)
        SplitApp(
          id: m['id'] as String,
          label: (m['label'] as String?) ?? m['id'] as String,
          icon: m['icon'] as Uint8List?,
          system: m['system'] == true,
        ),
    ];
  }

  @override
  Future<Set<String>> load() async =>
      (await _channel.invokeListMethod<String>('bypass') ?? []).toSet();

  @override
  Future<void> save(Set<String> ids) =>
      _channel.invokeMethod('setBypass', {'packages': ids.toList()});

  @override
  Future<Set<String>> alwaysDirect() async =>
      (await _channel.invokeListMethod<String>('alwaysDirect') ?? []).toSet();
}

class WindowsSplitTunnel implements SplitTunnelStore {
  /// Programs with a window right now, with their icon and description.
  /// Saved ones that aren't running are listed too (by name).
  @override
  Future<List<SplitApp>> apps() async {
    const script = r'''
Add-Type -AssemblyName System.Drawing
Get-Process | Where-Object { $_.MainWindowHandle -ne 0 -and $_.Path } |
  Sort-Object Path -Unique | ForEach-Object {
    $icon = $null
    try {
      $ic = [System.Drawing.Icon]::ExtractAssociatedIcon($_.Path)
      $ms = New-Object IO.MemoryStream
      $ic.ToBitmap().Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
      $icon = [Convert]::ToBase64String($ms.ToArray())
    } catch {}
    [pscustomobject]@{ name = [IO.Path]::GetFileName($_.Path); label = $_.Description; icon = $icon }
  } | ConvertTo-Json -Compress
''';
    var running = <SplitApp>[];
    try {
      final r = await Process.run(
          'powershell', ['-NoProfile', '-NonInteractive', '-Command', script]);
      running = parseWindowsApps('${r.stdout}');
    } catch (_) {}
    final saved = SplitTunnelStore.savedProcesses();
    return mergeSavedPrograms(running, saved);
  }

  @override
  Future<Set<String>> load() async => SplitTunnelStore.savedProcesses().toSet();

  @override
  Future<void> save(Set<String> ids) => PrefsStore.setStringList(
      PrefsStore.splitBypassProcesses, normalizeProcessNames(ids));

  @override
  Future<Set<String>> alwaysDirect() async => const {};
}

/// Our own programs: the tunnel handles their traffic itself.
const _ownPrograms = {
  'wavebreak.exe',
  'sing-box.exe',
  'xray.exe',
  'cloak-client-proxy.exe',
  'wavebreak-launcher.exe',
};

/// "C:\Program Files\Google\Chrome.EXE", " telegram " → "chrome.exe",
/// "telegram.exe": lower-case file names with .exe, each once, sorted;
/// blanks and WAVEBREAK's own programs dropped.
List<String> normalizeProcessNames(Iterable<String> names) {
  final out = <String>{};
  for (final raw in names) {
    var n = raw.trim().replaceAll('"', '');
    if (n.isEmpty) continue;
    n = n.split(RegExp(r'[\\/]')).last.toLowerCase();
    if (n.isEmpty) continue;
    if (!n.endsWith('.exe')) n = '$n.exe';
    if (_ownPrograms.contains(n)) continue;
    out.add(n);
  }
  return out.toList()..sort();
}

/// The PowerShell listing (one object or an array) → apps, our own
/// programs left out.
List<SplitApp> parseWindowsApps(String json) {
  final text = json.trim();
  if (text.isEmpty) return const [];
  final Object? decoded;
  try {
    decoded = jsonDecode(text);
  } catch (_) {
    return const [];
  }
  final items = decoded is List ? decoded : [decoded];
  final apps = <String, SplitApp>{};
  for (final item in items) {
    if (item is! Map) continue;
    final names = normalizeProcessNames(['${item['name'] ?? ''}']);
    if (names.isEmpty) continue;
    final id = names.single;
    final label = '${item['label'] ?? ''}'.trim();
    Uint8List? icon;
    final b64 = item['icon'];
    if (b64 is String && b64.isNotEmpty) {
      try {
        icon = base64Decode(b64);
      } catch (_) {}
    }
    apps.putIfAbsent(id,
        () => SplitApp(id: id, label: label.isEmpty ? id : label, icon: icon));
  }
  final list = apps.values.toList()
    ..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
  return list;
}

/// Running programs plus the saved ones that aren't running now.
List<SplitApp> mergeSavedPrograms(List<SplitApp> running, List<String> saved) {
  final ids = {for (final a in running) a.id};
  return [
    ...running,
    for (final id in saved)
      if (!ids.contains(id)) SplitApp(id: id, label: id),
  ];
}
