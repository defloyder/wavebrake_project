import 'package:flutter_test/flutter_test.dart';
import 'package:wavebreak/services/vpn/stuck_flows.dart';

Map<String, dynamic> conn(String id, int up, int down,
        {String start = '2026-10-14T10:00:00Z', String host = 'x.org'}) =>
    {
      'id': id,
      'upload': up,
      'download': down,
      'start': start,
      'metadata': {
        'network': 'tcp',
        'host': host,
        'destinationIP': '1.2.3.4',
        'destinationPort': '443',
      },
    };

void main() {
  final t0 = DateTime.utc(2026, 10, 14, 10, 0, 1);

  test('opened, spoke first, never answered: closed after 15 s', () {
    final s = StuckFlows();
    expect(s.observe([conn('a', 500, 0)], t0), isEmpty);
    final out =
        s.observe([conn('a', 500, 0)], t0.add(const Duration(seconds: 16)));
    expect(out.keys, ['a']);
  });

  test('a quiet connection after an ack is left alone', () {
    final s = StuckFlows();
    s.observe([conn('b', 100, 900)], t0);
    // An ack goes out, nothing comes back: one burst only.
    s.observe([conn('b', 140, 900)], t0.add(const Duration(seconds: 5)));
    final out =
        s.observe([conn('b', 140, 900)], t0.add(const Duration(seconds: 60)));
    expect(out, isEmpty);
  });

  test('two unanswered requests: closed', () {
    final s = StuckFlows();
    s.observe([conn('c', 100, 900)], t0);
    s.observe([conn('c', 300, 900)], t0.add(const Duration(seconds: 5)));
    s.observe([conn('c', 500, 900)], t0.add(const Duration(seconds: 12)));
    final out =
        s.observe([conn('c', 500, 900)], t0.add(const Duration(seconds: 26)));
    expect(out.keys, ['c']);
  });

  test('an upload is left alone', () {
    final s = StuckFlows();
    s.observe([conn('d', 100, 900)], t0);
    s.observe([conn('d', 100000, 900)], t0.add(const Duration(seconds: 5)));
    s.observe([conn('d', 200000, 900)], t0.add(const Duration(seconds: 12)));
    final out = s
        .observe([conn('d', 200000, 900)], t0.add(const Duration(seconds: 40)));
    expect(out, isEmpty);
  });
}
