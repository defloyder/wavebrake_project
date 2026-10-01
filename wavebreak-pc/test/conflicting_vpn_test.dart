// Pure functions only — nothing here lists or closes real processes.
import 'package:flutter_test/flutter_test.dart';
import 'package:wavebreak/services/vpn/conflicting_vpn_closer.dart';

void main() {
  test('tasklist CSV gives lower-case image names', () {
    const csv = '"System Idle Process","0","Services","0","8 K"\r\n'
        '"Happ.exe","18520","Console","3","171 196 K"\r\n'
        '"happd.exe","7568","Services","0","30 632 K"\r\n'
        '"sing-box.exe","900","Console","3","50 000 K"\r\n';
    expect(parseTasklistCsv(csv),
        {'system idle process', 'happ.exe', 'happd.exe', 'sing-box.exe'});
  });

  test(
      'Happ is found by process or by its service; our own and LAN tools are not',
      () {
    final apps = conflictingApps({
      'happ.exe',
      'sing-box.exe',
      'wavebreak.exe',
      'radmin_vpn.exe',
      'wireguard.exe'
    }, const {});
    expect(apps.map((a) => a.name), ['Happ']);

    expect(conflictingApps(const {}, {'happservice'}).map((a) => a.name),
        ['Happ']);
    expect(conflictingApps({'explorer.exe'}, const {}), isEmpty);
  });

  test('only a proxy on this machine counts as loopback', () {
    expect(isLoopbackProxy('127.0.0.1:10809'), isTrue);
    expect(isLoopbackProxy('http=localhost:8080;https=localhost:8080'), isTrue);
    expect(isLoopbackProxy('[::1]:1080'), isTrue);
    expect(isLoopbackProxy('proxy.corp.example:3128'), isFalse);
    expect(isLoopbackProxy('10.0.0.5:8080'), isFalse);
  });
}
