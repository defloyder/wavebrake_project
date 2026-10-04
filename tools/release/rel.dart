// Release bookkeeping for tools/release/release.sh — the parts that need
// JSON: the shared release history (releases.json, committed, so both
// machines see the same thing), the next free version numbers, and the
// update manifests. Run with `dart run tools/release/rel.dart <command>`.
//
//   next <android|windows> [name]
//       Prints `NAME CODE RB_NAME RB_CODE RB_COMMIT` for the next release:
//       CODE is above every code ever taken (history and the live
//       manifests), the rollback is the last published release rebuilt
//       with CODE+1. NAME defaults to the last name with its last number
//       bumped (Android 1.2.4.5 -> 1.2.4.6, Windows 1.0.11 -> 1.0.12).
//   take <android|windows> CODE
//       Marks codes up to CODE as used (a staged build consumes its
//       numbers even if it's never published).
//   record <android|windows> NAME CODE COMMIT RB_NAME RB_CODE RB_COMMIT
//       Adds a published release to the history.
//   manifest <android|windows> NAME CODE RB_NAME RB_CODE OUT_FILE
//       Writes version.json / version-windows.json.
//   cert
//       Prints the expected signing certificate SHA-256.
import 'dart:convert';
import 'dart:io';

final _historyFile = File.fromUri(Platform.script.resolve('releases.json'));
const _mirror = 'https://dl.wavebreak.com.tr/downloads';
const _site = 'https://wavebreak.com.tr/downloads';

Future<void> main(List<String> args) async {
  if (args.isEmpty) _fail('usage: rel.dart <next|take|record|manifest|cert> ...');
  final history = jsonDecode(await _historyFile.readAsString()) as Map<String, dynamic>;
  switch (args[0]) {
    case 'cert':
      stdout.writeln(history['expectedCertSha256']);
    case 'next':
      await _next(history, _platform(args, 1), args.length > 2 ? args[2] : null);
    case 'take':
      final p = _platform(args, 1);
      final code = int.parse(args[2]);
      final h = history[p] as Map<String, dynamic>;
      if (code > (h['maxCode'] as int)) h['maxCode'] = code;
      await _save(history);
    case 'record':
      final p = _platform(args, 1);
      final h = history[p] as Map<String, dynamic>;
      final releases = (h['releases'] as List).cast<Map<String, dynamic>>();
      releases.insert(0, {
        'name': args[2],
        'code': int.parse(args[3]),
        'commit': args[4],
        'rollback': {'name': args[5], 'code': int.parse(args[6]), 'commit': args[7]},
        'published': DateTime.now().toIso8601String().substring(0, 10),
      });
      h['releases'] = releases;
      final rb = int.parse(args[6]);
      if (rb > (h['maxCode'] as int)) h['maxCode'] = rb;
      await _save(history);
    case 'manifest':
      _manifest(_platform(args, 1), args[2], int.parse(args[3]), args[4],
          int.parse(args[5]), args[6]);
    default:
      _fail('unknown command ${args[0]}');
  }
}

String _platform(List<String> args, int i) {
  if (args.length <= i || !{'android', 'windows'}.contains(args[i])) {
    _fail('platform must be android or windows');
  }
  return args[i];
}

Future<void> _next(Map<String, dynamic> history, String p, String? name) async {
  final h = history[p] as Map<String, dynamic>;
  final releases = (h['releases'] as List).cast<Map<String, dynamic>>();
  if (releases.isEmpty) _fail('no published $p release in releases.json');
  final last = releases.first;
  var maxCode = h['maxCode'] as int;
  final file = p == 'android' ? 'version.json' : 'version-windows.json';
  for (final base in [_mirror, _site]) {
    final live = await _getJson('$base/$file');
    if (live == null) continue;
    for (final c in [live['versionCode'], (live['rollback'] as Map?)?['versionCode']]) {
      if (c is int && c > maxCode) maxCode = c;
    }
  }
  final code = maxCode + 1;
  final newName = name ?? _bump(last['name'] as String);
  if (p == 'windows' && newName.split('.').length != 3) {
    _fail('Windows version must be three numbers (got $newName): a four-part '
        'name makes Flutter stamp the exe 1.0.0 with no build number.');
  }
  stdout.writeln('$newName $code ${last['name']} ${code + 1} ${last['commit']}');
}

String _bump(String name) {
  final parts = name.split('.');
  parts[parts.length - 1] = '${int.parse(parts.last) + 1}';
  return parts.join('.');
}

void _manifest(String p, String name, int code, String rbName, int rbCode, String out) {
  final m = <String, dynamic>{};
  if (p == 'android') {
    m['versionCode'] = code;
    m['versionName'] = name;
    m['url'] = '$_mirror/wavebreak-android-$name.apk';
    m['mirrors'] = ['$_site/wavebreak-android.apk'];
    m['abis'] = {
      for (final abi in ['arm64-v8a', 'armeabi-v7a'])
        abi: [
          '$_mirror/wavebreak-android-$name-$abi.apk',
          '$_site/wavebreak-android-$name-$abi.apk',
        ],
    };
    m['rollback'] = {
      'fromVersionCode': code,
      'versionCode': rbCode,
      'versionName': rbName,
      'url': '$_mirror/wavebreak-android-rollback-$rbName.apk',
      'mirrors': ['$_site/wavebreak-android-rollback.apk'],
    };
  } else {
    m['versionCode'] = code;
    m['versionName'] = name;
    m['url'] = '$_mirror/wavebreak-windows-$name-setup.exe';
    m['mirrors'] = ['$_site/wavebreak-windows.exe'];
    m['rollback'] = {
      'fromVersionCode': code,
      'versionCode': rbCode,
      'versionName': rbName,
      'url': '$_mirror/wavebreak-windows-rollback-$rbName-setup.exe',
      'mirrors': ['$_site/wavebreak-windows-rollback.exe'],
    };
  }
  File(out).writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(m)}\n');
}

Future<Map<String, dynamic>?> _getJson(String url) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final req = await client.getUrl(Uri.parse('$url?t=${DateTime.now().millisecondsSinceEpoch}'));
    final res = await req.close().timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) return null;
    return jsonDecode(await res.transform(utf8.decoder).join()) as Map<String, dynamic>;
  } catch (_) {
    return null;
  } finally {
    client.close(force: true);
  }
}

Future<void> _save(Map<String, dynamic> history) => _historyFile
    .writeAsString('${const JsonEncoder.withIndent('  ').convert(history)}\n');

Never _fail(String message) {
  stderr.writeln('rel.dart: $message');
  exit(1);
}
