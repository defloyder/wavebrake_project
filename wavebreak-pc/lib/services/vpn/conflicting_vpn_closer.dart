import 'dart:async';
import 'dart:io';

import '../../core/logging/app_logger.dart';

/// Closes other VPN / proxy clients before WAVEBREAK brings its tunnel up.
///
/// Two tunnels on Windows race for the default route, and a proxy client
/// that set the system proxy (Happ: 127.0.0.1:10809) keeps every browser
/// pointed at itself — WAVEBREAK then "connects" but nothing works, or
/// the other client simply wins. Field reports 01.10: users with Happ
/// running couldn't use the app at all until they found and quit Happ by
/// hand. The owner's call: on connect the app closes them itself.
///
/// Only consumer VPN/proxy clients known to take over the route or the
/// system proxy. Deliberately NOT: WireGuard (often a separate, wanted
/// tunnel — e.g. admin access), corporate VPNs (Cisco, GlobalProtect,
/// Forti), LAN tools (Radmin, Hamachi, ZeroTier, Tailscale). Generic
/// cores (xray.exe, sing-box.exe) aren't matched by name either — ours
/// has the same name — they go down with their app via `taskkill /T`.
class ConflictingVpnCloser {
  const ConflictingVpnCloser();

  /// Fired with the names of the apps that were closed, for the UI to tell
  /// the user what happened.
  static final StreamController<List<String>> _closed =
      StreamController<List<String>>.broadcast();
  static Stream<List<String>> get closed => _closed.stream;

  /// Closes whatever is running from [kConflictingApps]; returns the names
  /// of the apps closed (empty when there was nothing to do). Never throws.
  Future<List<String>> closeAll() async {
    if (!Platform.isWindows) return const [];
    try {
      final tasks = await Process.run('tasklist', ['/FO', 'CSV', '/NH']);
      final running = parseTasklistCsv('${tasks.stdout}');
      final services = await _runningServices();
      final apps = conflictingApps(running, services);
      if (apps.isEmpty) return const [];

      AppLogger.warn(
          'Closing other VPN/proxy apps before connecting: ${apps.map((a) => a.name).join(', ')}');
      for (final app in apps) {
        for (final service in app.services) {
          if (services.contains(service.toLowerCase())) {
            await _run('sc', ['stop', service]);
          }
        }
        for (final exe in app.processes) {
          if (running.contains(exe)) {
            await _run('taskkill', ['/F', '/T', '/IM', exe]);
          }
        }
      }
      await _resetLoopbackSystemProxy();
      // Let their TUN adapters and routes go away before ours comes up.
      await Future<void>.delayed(const Duration(milliseconds: 1500));

      final names = [for (final app in apps) app.name];
      _closed.add(names);
      return names;
    } catch (e) {
      AppLogger.warn('Closing other VPN apps failed: $e');
      return const [];
    }
  }

  static Future<Set<String>> _runningServices() async {
    final names = {
      for (final app in kConflictingApps) ...app.services,
    };
    final running = <String>{};
    for (final name in names) {
      final r = await Process.run('sc', ['query', name]);
      if ('${r.stdout}'.contains('RUNNING')) running.add(name.toLowerCase());
    }
    return running;
  }

  static Future<void> _run(String exe, List<String> args) async {
    final r = await Process.run(exe, args);
    AppLogger.info('$exe ${args.join(' ')} -> exit ${r.exitCode}');
  }

  /// A closed proxy client leaves the system proxy pointing at a port
  /// nobody listens on any more (127.0.0.1:10809 for Happ) and every
  /// browser stops loading. Turn it off — but only when it points at
  /// this machine; a real (corporate) proxy elsewhere is left alone.
  static Future<void> _resetLoopbackSystemProxy() async {
    const key =
        r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings';
    final enabled =
        await Process.run('reg', ['query', key, '/v', 'ProxyEnable']);
    if (!RegExp(r'ProxyEnable\s+REG_DWORD\s+0x1\b')
        .hasMatch('${enabled.stdout}')) {
      return;
    }
    final server =
        await Process.run('reg', ['query', key, '/v', 'ProxyServer']);
    final match =
        RegExp(r'ProxyServer\s+REG_SZ\s+(\S+)').firstMatch('${server.stdout}');
    if (match == null || !isLoopbackProxy(match.group(1)!)) return;
    AppLogger.warn(
        'System proxy still points at ${match.group(1)} — turning it off');
    await _run('reg',
        ['add', key, '/v', 'ProxyEnable', '/t', 'REG_DWORD', '/d', '0', '/f']);
  }
}

/// A VPN/proxy client: its display name, its process image names
/// (lower-case, as tasklist prints them, lower-cased) and its Windows
/// services.
class ConflictingApp {
  const ConflictingApp(this.name, this.processes, [this.services = const []]);
  final String name;
  final List<String> processes;
  final List<String> services;
}

const kConflictingApps = [
  ConflictingApp('Happ', ['happ.exe', 'happd.exe'], ['HappService']),
  ConflictingApp('v2rayN', ['v2rayn.exe']),
  ConflictingApp('Hiddify', ['hiddify.exe', 'hiddifycli.exe']),
  ConflictingApp('NekoBox', ['nekobox.exe', 'nekoray.exe']),
  ConflictingApp('Throne', ['throne.exe']),
  ConflictingApp('Clash', [
    'clash for windows.exe',
    'clash-verge.exe',
    'clash-verge-service.exe',
    'mihomo party.exe',
    'flclash.exe',
  ], [
    'clash_verge_service',
  ]),
  ConflictingApp('Karing', ['karing.exe', 'karingservice.exe']),
  ConflictingApp('AmneziaVPN', ['amneziavpn.exe', 'amneziavpn-service.exe'],
      ['AmneziaVPN-service']),
  ConflictingApp(
      'Outline', ['outline.exe', 'outlineservice.exe'], ['OutlineService']),
  ConflictingApp('Proton VPN', ['protonvpn.exe', 'protonvpn.client.exe']),
  ConflictingApp('NordVPN', ['nordvpn.exe']),
  ConflictingApp('ExpressVPN', ['expressvpn.exe']),
  ConflictingApp('Surfshark', ['surfshark.exe']),
  ConflictingApp('Windscribe', ['windscribe.exe']),
  ConflictingApp('Psiphon', ['psiphon3.exe']),
  ConflictingApp('Lantern', ['lantern.exe']),
];

/// Image names (lower-case) from `tasklist /FO CSV /NH` output.
Set<String> parseTasklistCsv(String csv) => {
      for (final line in csv.split('\n'))
        if (line.trim().startsWith('"'))
          line.trim().substring(1).split('"').first.toLowerCase(),
    };

/// The apps from [kConflictingApps] that have a running process (from
/// [running], lower-case image names) or a running service (from
/// [services], lower-case service names).
List<ConflictingApp> conflictingApps(
        Set<String> running, Set<String> services) =>
    [
      for (final app in kConflictingApps)
        if (app.processes.any(running.contains) ||
            app.services.any((s) => services.contains(s.toLowerCase())))
          app,
    ];

/// True when a WinINET ProxyServer value ("127.0.0.1:10809",
/// "http=localhost:8080;https=…") points at this machine.
bool isLoopbackProxy(String server) {
  final s = server.toLowerCase();
  return s.contains('127.0.0.1') ||
      s.contains('localhost') ||
      s.contains('[::1]') ||
      RegExp(r'(^|[=;])::1').hasMatch(s);
}
