import 'dart:convert';

/// Schemes recognized as individual servers inside a subscription body.
/// `http(s)` is deliberately excluded here: a subscription may contain
/// ordinary web URLs (support pages, etc.) that are not proxies.
const subscriptionSchemes = [
  'vless', 'vmess', 'trojan', 'ss', 'hysteria2', 'hy2', 'tuic',
  'wireguard', 'wg', 'socks', 'socks5',
];

/// Splits a subscription body — base64 of newline-separated links, or the
/// links as plain text — into the share-link lines it contains, in order.
/// Lines with other schemes (or no scheme) are skipped.
List<String> extractShareLinks(String body) {
  var text = body.trim();
  if (!text.contains('://')) {
    try {
      final decoded = utf8.decode(base64.decode(base64.normalize(text)));
      if (decoded.contains('://')) text = decoded;
    } catch (_) {
      // Not base64 — use the raw body as-is.
    }
  }
  final links = <String>[];
  for (final rawLine in text.split(RegExp(r'[\r\n]+'))) {
    final line = rawLine.trim();
    if (line.isEmpty) continue;
    final schemeEnd = line.indexOf('://');
    if (schemeEnd <= 0) continue;
    if (!subscriptionSchemes.contains(line.substring(0, schemeEnd).toLowerCase())) {
      continue;
    }
    links.add(line);
  }
  return links;
}
