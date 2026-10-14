/// What a node's name says, the way providers actually write them:
/// "🇩🇪 Germany, Frankfurt (CDN)" (WAVEBREAK), "🇩🇪 Германия | VLESS | 2",
/// "[NL] Amsterdam 🚀", "DE-Frankfurt • Reality", "Turkey Istanbul #3".
///
/// - The country: a flag emoji, else a country name (English or Russian)
///   or a two-letter code in the text.
/// - The place: the first remaining word group (the city), else the
///   country; node numbers stay with it ("Frankfurt 2"), so two nodes of
///   one city remain two rows.
/// - Protocol and transport words (VLESS, Reality, gRPC, WS…) are dropped:
///   the app shows the protocol from the link itself.
/// - A "(note)" is kept for the place: "Amsterdam (CDN)".
class NodeLabel {
  const NodeLabel({
    required this.countryCode,
    required this.country,
    required this.place,
  });

  /// ISO 3166 alpha-2, upper case; null when nothing names a country.
  final String? countryCode;
  final String country;

  /// The place, with its "(note)" if any — LocationItem.city.
  final String place;
}

NodeLabel parseNodeLabel(String label) {
  var text = label.trim();
  var code = flagCodeIn(text);

  // "(CDN)", "(Direct-TLS)": the note for the place — the last one, as
  // WAVEBREAK writes them; a protocol word in it is still a note (it
  // tells the variants of one place apart).
  String note = '';
  final paren = RegExp(r'\s*\(([^()]*)\)\s*$').firstMatch(text);
  if (paren != null) {
    final inner = paren.group(1)!.trim();
    if (inner.isNotEmpty) note = '($inner)';
    text = text.substring(0, paren.start);
  }

  // "[DE]" / "[VLESS]" / "[Premium]".
  final extras = <String>[];
  text = text.replaceAllMapped(RegExp(r'\[([^\[\]]*)\]'), (m) {
    final inner = m.group(1)!.trim();
    final asCode = _codeToken(inner);
    if (asCode != null) {
      code ??= asCode;
    } else if (inner.isNotEmpty && !_isProtocolWord(inner)) {
      extras.add(inner);
    }
    return ' | ';
  });

  // Emoji and pictographs out (flags were read above).
  text = text.replaceAll(_emoji, ' ');

  final tokens = <String>[];
  for (var raw in text.split(_separators)) {
    raw = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
    // A group that is only protocol words ("| VLESS | Reality |") goes.
    if (raw.isEmpty || raw.split(' ').every(_isProtocolWord)) continue;
    tokens.add(raw);
  }
  tokens.addAll(extras);

  String? country;
  final rest = <String>[];
  for (final t in tokens) {
    if (country == null) {
      final byName = _countryByName[t.toLowerCase()];
      final byCode = byName == null ? _codeToken(t) : null;
      // "NL-1", "DE2": a code with a node number.
      final m = RegExp(r'^([A-Za-z]{2})[\s\-_]?(\d+)$').firstMatch(t);
      final byCodeNum = byName == null && byCode == null && m != null
          ? _codeToken(m.group(1)!)
          : null;
      final found = byName ?? byCode ?? byCodeNum;
      if (found != null && (code == null || code == found)) {
        code ??= found;
        country = byName != null ? t : _englishName[found] ?? found;
        if (byCodeNum != null) rest.add(m!.group(2)!);
        continue;
      }
    }
    // "DE-Frankfurt", "NL_Amsterdam": a code glued to the city.
    if (country == null) {
      final m = RegExp(r'^([A-Za-z]{2})[-_](\D.*)$').firstMatch(t);
      final found = m == null ? null : _codeToken(m.group(1)!);
      if (found != null && (code == null || code == found)) {
        code ??= found;
        country = _englishName[found] ?? found;
        rest.add(m!.group(2)!.trim());
        continue;
      }
    }
    // "Germany Frankfurt", "Турция Стамбул": a country name leading a group.
    if (country == null) {
      final words = t.split(' ');
      if (words.length > 1) {
        final head = _countryByName[words.first.toLowerCase()];
        if (head != null && (code == null || code == head)) {
          code ??= head;
          country = words.first;
          rest.add(words.skip(1).join(' '));
          continue;
        }
      }
    }
    rest.add(t);
  }

  // A flag but no name: the country by its code.
  country ??= code == null ? null : (_englishName[code] ?? code);

  // Node numbers ("#3", "2") apart from the words: "Istanbul #3" →
  // "Istanbul 3".
  final named = <String>[];
  final numbers = <String>[];
  for (final t in rest) {
    // With a country found the name is structured: protocol words inside
    // a group go too ("Germany VLESS Reality"); a free name ("TUIC node")
    // stays whole.
    final words =
        t.split(' ').where((w) => code == null || !_isProtocolWord(w)).toList();
    numbers.addAll(
        words.where(_isNumber).map((w) => w.replaceAll(RegExp('[#№]'), '')));
    final text = words.where((w) => !_isNumber(w)).join(' ').trim();
    if (text.isNotEmpty) named.add(text);
  }
  String place;
  if (named.isNotEmpty) {
    place = named.first;
    if (named.length > 1) place = '$place ${named.skip(1).join(' ')}';
  } else {
    place = country ?? label.trim();
  }
  if (numbers.isNotEmpty) place = '$place ${numbers.join(' ')}';
  // Nothing names a country: the whole place is the name.
  country ??= place;
  return NodeLabel(
    countryCode: code,
    country: country,
    place: note.isEmpty ? place : '$place $note',
  );
}

/// The first flag emoji in [label] as an ISO code.
String? flagCodeIn(String label) {
  final runes = label.runes.toList();
  for (var i = 0; i + 1 < runes.length; i++) {
    final a = runes[i], b = runes[i + 1];
    if (a >= 0x1F1E6 && a <= 0x1F1FF && b >= 0x1F1E6 && b <= 0x1F1FF) {
      return String.fromCharCodes([a - 0x1F1E6 + 65, b - 0x1F1E6 + 65]);
    }
  }
  return null;
}

final _emoji = RegExp(
    r'[\u{1F1E6}-\u{1F1FF}\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}'
    r'\u{2B00}-\u{2BFF}\u{FE0F}\u{200D}\u{20E3}\u{2300}-\u{23FF}]',
    unicode: true);

final _separators =
    RegExp(r'\s*(?:[|•·,;/\\»→]|\s[-–—_]\s|^[-–—]\s|\s[-–—]$)\s*');

bool _isNumber(String t) => RegExp(r'^(#|№)?\d{1,4}$').hasMatch(t);

const _protocolWords = {
  'vless',
  'vmess',
  'trojan',
  'ss',
  'shadowsocks',
  'ssr',
  'hysteria',
  'hysteria2',
  'hy2',
  'tuic',
  'reality',
  'xtls',
  'vision',
  'xtls-rprx-vision',
  'grpc',
  'ws',
  'websocket',
  'tcp',
  'udp',
  'xhttp',
  'splithttp',
  'httpupgrade',
  'h2',
  'http2',
  'quic',
  'tls',
  'wireguard',
  'wg',
  'socks',
  'socks5',
  'naive',
  'anytls',
  'vpn',
  'proxy',
};

bool _isProtocolWord(String w) {
  final s = w.toLowerCase().replaceAll(RegExp(r'^[\[(]+|[\])]+$'), '');
  if (_protocolWords.contains(s)) return true;
  // "VLESS-Reality", "vless+ws".
  final parts = s.split(RegExp(r'[-+]'));
  return parts.length > 1 && parts.every(_protocolWords.contains);
}

/// "DE", "de", "UK" → ISO code when it is a country we know.
String? _codeToken(String t) {
  final s = t.trim().toUpperCase();
  if (s.length != 2) return null;
  if (s == 'UK') return 'GB';
  return _englishName.containsKey(s) ? s : null;
}

const _englishName = {
  'AE': 'UAE',
  'AM': 'Armenia',
  'AR': 'Argentina',
  'AT': 'Austria',
  'AU': 'Australia',
  'AZ': 'Azerbaijan',
  'BE': 'Belgium',
  'BG': 'Bulgaria',
  'BR': 'Brazil',
  'BY': 'Belarus',
  'CA': 'Canada',
  'CH': 'Switzerland',
  'CL': 'Chile',
  'CN': 'China',
  'CY': 'Cyprus',
  'CZ': 'Czechia',
  'DE': 'Germany',
  'DK': 'Denmark',
  'EE': 'Estonia',
  'EG': 'Egypt',
  'ES': 'Spain',
  'FI': 'Finland',
  'FR': 'France',
  'GB': 'United Kingdom',
  'GE': 'Georgia',
  'GR': 'Greece',
  'HK': 'Hong Kong',
  'HR': 'Croatia',
  'HU': 'Hungary',
  'ID': 'Indonesia',
  'IE': 'Ireland',
  'IL': 'Israel',
  'IN': 'India',
  'IS': 'Iceland',
  'IT': 'Italy',
  'JP': 'Japan',
  'KG': 'Kyrgyzstan',
  'KR': 'South Korea',
  'KZ': 'Kazakhstan',
  'LT': 'Lithuania',
  'LU': 'Luxembourg',
  'LV': 'Latvia',
  'MD': 'Moldova',
  'MX': 'Mexico',
  'MY': 'Malaysia',
  'NL': 'Netherlands',
  'NO': 'Norway',
  'NZ': 'New Zealand',
  'PH': 'Philippines',
  'PL': 'Poland',
  'PT': 'Portugal',
  'RO': 'Romania',
  'RS': 'Serbia',
  'RU': 'Russia',
  'SA': 'Saudi Arabia',
  'SE': 'Sweden',
  'SG': 'Singapore',
  'SI': 'Slovenia',
  'SK': 'Slovakia',
  'TH': 'Thailand',
  'TR': 'Turkey',
  'TW': 'Taiwan',
  'UA': 'Ukraine',
  'US': 'USA',
  'UZ': 'Uzbekistan',
  'VN': 'Vietnam',
  'ZA': 'South Africa',
};

const _countryByName = {
  'uae': 'AE',
  'emirates': 'AE',
  'оаэ': 'AE',
  'эмираты': 'AE',
  'armenia': 'AM',
  'армения': 'AM',
  'argentina': 'AR',
  'аргентина': 'AR',
  'austria': 'AT',
  'австрия': 'AT',
  'australia': 'AU',
  'австралия': 'AU',
  'azerbaijan': 'AZ',
  'азербайджан': 'AZ',
  'belgium': 'BE',
  'бельгия': 'BE',
  'bulgaria': 'BG',
  'болгария': 'BG',
  'brazil': 'BR',
  'бразилия': 'BR',
  'belarus': 'BY',
  'беларусь': 'BY',
  'canada': 'CA',
  'канада': 'CA',
  'switzerland': 'CH',
  'швейцария': 'CH',
  'chile': 'CL',
  'чили': 'CL',
  'china': 'CN',
  'китай': 'CN',
  'cyprus': 'CY',
  'кипр': 'CY',
  'czechia': 'CZ',
  'czech': 'CZ',
  'чехия': 'CZ',
  'germany': 'DE',
  'германия': 'DE',
  'deutschland': 'DE',
  'denmark': 'DK',
  'дания': 'DK',
  'estonia': 'EE',
  'эстония': 'EE',
  'egypt': 'EG',
  'египет': 'EG',
  'spain': 'ES',
  'испания': 'ES',
  'finland': 'FI',
  'финляндия': 'FI',
  'france': 'FR',
  'франция': 'FR',
  'united kingdom': 'GB',
  'uk': 'GB',
  'britain': 'GB',
  'england': 'GB',
  'великобритания': 'GB',
  'англия': 'GB',
  'georgia': 'GE',
  'грузия': 'GE',
  'greece': 'GR',
  'греция': 'GR',
  'hong kong': 'HK',
  'hongkong': 'HK',
  'гонконг': 'HK',
  'croatia': 'HR',
  'хорватия': 'HR',
  'hungary': 'HU',
  'венгрия': 'HU',
  'indonesia': 'ID',
  'индонезия': 'ID',
  'ireland': 'IE',
  'ирландия': 'IE',
  'israel': 'IL',
  'израиль': 'IL',
  'india': 'IN',
  'индия': 'IN',
  'iceland': 'IS',
  'исландия': 'IS',
  'italy': 'IT',
  'италия': 'IT',
  'japan': 'JP',
  'япония': 'JP',
  'kyrgyzstan': 'KG',
  'киргизия': 'KG',
  'кыргызстан': 'KG',
  'korea': 'KR',
  'south korea': 'KR',
  'корея': 'KR',
  'kazakhstan': 'KZ',
  'казахстан': 'KZ',
  'lithuania': 'LT',
  'литва': 'LT',
  'luxembourg': 'LU',
  'люксембург': 'LU',
  'latvia': 'LV',
  'латвия': 'LV',
  'moldova': 'MD',
  'молдова': 'MD',
  'mexico': 'MX',
  'мексика': 'MX',
  'malaysia': 'MY',
  'малайзия': 'MY',
  'netherlands': 'NL',
  'holland': 'NL',
  'нидерланды': 'NL',
  'голландия': 'NL',
  'norway': 'NO',
  'норвегия': 'NO',
  'new zealand': 'NZ',
  'philippines': 'PH',
  'poland': 'PL',
  'польша': 'PL',
  'portugal': 'PT',
  'португалия': 'PT',
  'romania': 'RO',
  'румыния': 'RO',
  'serbia': 'RS',
  'сербия': 'RS',
  'russia': 'RU',
  'россия': 'RU',
  'saudi arabia': 'SA',
  'sweden': 'SE',
  'швеция': 'SE',
  'singapore': 'SG',
  'сингапур': 'SG',
  'slovenia': 'SI',
  'словения': 'SI',
  'slovakia': 'SK',
  'словакия': 'SK',
  'thailand': 'TH',
  'таиланд': 'TH',
  'turkey': 'TR',
  'türkiye': 'TR',
  'turkiye': 'TR',
  'турция': 'TR',
  'taiwan': 'TW',
  'тайвань': 'TW',
  'ukraine': 'UA',
  'украина': 'UA',
  'usa': 'US',
  'united states': 'US',
  'america': 'US',
  'сша': 'US',
  'америка': 'US',
  'uzbekistan': 'UZ',
  'узбекистан': 'UZ',
  'vietnam': 'VN',
  'вьетнам': 'VN',
  'south africa': 'ZA',
};
