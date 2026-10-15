import 'package:flutter_test/flutter_test.dart';
import 'package:wavebreak/core/i18n/app_strings.dart';
import 'package:wavebreak/features/shared/subscription_section.dart';
import 'package:wavebreak/services/core_api/models.dart';

LocationItem _loc(String id, String country, String city,
        {bool available = true, String? rawLink = 'vless://x@h:1#x'}) =>
    LocationItem(
      id: id,
      countryCode: country.substring(0, 2).toUpperCase(),
      country: country,
      city: city,
      available: available,
      rawLink: rawLink,
    );

void main() {
  group('autoTagsFor / autoCandidates', () {
    final istanbul = _loc('1', 'Turkey', 'Istanbul');
    final germany = _loc('2', 'Germany', '');
    final moscow = _loc('3', 'Russia', 'Moscow');
    final lte = _loc('4', 'Russia', 'LTE (БС)');

    test('no exclude: the plain row balances across everyone eligible', () {
      final servers = [istanbul, germany, moscow, lte];
      expect(autoTagsFor(servers), [null]);
      expect(autoCandidates(servers, null), servers);
    });

    test(
        'exclude drops the matching location from the plain row\'s own pool, '
        'not just from a tagged one', () {
      final servers = [istanbul, germany, moscow, lte];
      expect(autoTagsFor(servers, exclude: 'LTE'), [null]);
      expect(autoCandidates(servers, null, exclude: 'LTE'),
          [istanbul, germany, moscow]);
    });

    test('excluded location is also missing from the eligibility count', () {
      // Only two real candidates once LTE is excluded from a two-node list
      // — still enough for the row; one real node would not be.
      final servers = [istanbul, lte];
      expect(autoTagsFor(servers, exclude: 'LTE'), const []);
    });

    test('unavailable or linkless servers never enter any pool', () {
      final down = _loc('5', 'France', 'Paris', available: false);
      final noLink = _loc('6', 'Spain', 'Madrid', rawLink: null);
      final servers = [istanbul, germany, moscow, down, noLink];
      expect(autoCandidates(servers, null), [istanbul, germany, moscow]);
    });

    test('a tag still only narrows, independent of exclude', () {
      final lte2 = _loc('7', 'Russia', 'LTE (extra)');
      final servers = [istanbul, lte, lte2];
      expect(autoTagsFor(servers), [null, 'LTE']);
      expect(autoCandidates(servers, 'LTE'), [lte, lte2]);
    });

    test(
        'the real WAVEBREAK section excludes every Russia-based location '
        '(every one currently chains egress through Istanbul rather than '
        'reaching the internet directly, a restricted-network bypass, not '
        'an interchangeable "pick fastest" candidate — owner, 15.10: Moscow '
        'flagged after LTE alone was excluded here) from its plain row\'s '
        'own candidate pool, not just a subset of them', () {
      final sections = buildSubscriptionSections(
        wavebreakLocations: [istanbul, germany, moscow, lte],
        customGroups: const [],
        s: kRussianStrings,
      );
      final wavebreak = sections.first;
      expect(wavebreak.autoExclude, 'Russia');
      expect(wavebreak.autoTags, [null]);
      expect(autoCandidates(wavebreak.servers, null, exclude: wavebreak.autoExclude),
          [istanbul, germany]);
    });
  });

  group('service-only nodes stay out of auto select (owner, 15.10)', () {
    final nl = _loc('n', 'Netherlands', 'Amsterdam');
    final de = _loc('d', 'Germany', 'Frankfurt');
    final yt = _loc('y', 'Netherlands', 'YouTube без рекламы');
    final ru = _loc('r', 'Russia', 'Ютуб без рекламы');
    final gpt = _loc('g', 'USA', 'ChatGPT');
    final noAds = _loc('a', 'Finland', 'No Ads');

    test('recognised by name', () {
      for (final l in [yt, ru, gpt, noAds]) {
        expect(isServiceNode(l), isTrue, reason: l.city);
      }
      for (final l in [nl, de, _loc('x', 'Kazakhstan', 'Almaty')]) {
        expect(isServiceNode(l), isFalse, reason: l.city);
      }
    });

    test('never a candidate, and not counted for the row', () {
      final servers = [yt, nl, ru, de, gpt];
      expect(autoCandidates(servers, null), [nl, de]);
      expect(autoTagsFor([yt, nl, ru]), isEmpty);
    });
  });
}
