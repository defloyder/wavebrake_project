/// A small YAML reader — enough for subscription profiles (Clash/Mihomo
/// configs): block mappings and sequences by indentation, flow `{...}` /
/// `[...]` collections, quoted and plain scalars, `#` comments, `|`/`>`
/// block scalars. Not a full YAML implementation (no anchors, tags or
/// multi-document streams): what a subscription panel emits is covered,
/// without pulling in a YAML package.
///
/// Returns maps as `Map<String, Object?>`, sequences as `List<Object?>`,
/// scalars as `String`, `int`, `double`, `bool` or null. Throws
/// [FormatException] on input it can't read.
Object? parseMiniYaml(String source) {
  final lines = <_Line>[];
  var n = 0;
  for (final raw in source.replaceAll('\r\n', '\n').split('\n')) {
    n++;
    if (raw.trim() == '---' || raw.trim() == '...') continue;
    final text = _stripComment(raw).trimRight();
    if (text.trim().isEmpty) continue;
    final indent = text.length - text.trimLeft().length;
    lines.add(_Line(indent, text.trimLeft(), n));
  }
  if (lines.isEmpty) return null;
  final parser = _Parser(lines);
  final value = parser.block(lines.first.indent);
  return value;
}

class _Line {
  _Line(this.indent, this.text, this.number);
  final int indent;
  final String text;
  final int number;
}

String _stripComment(String line) {
  String? quote;
  for (var i = 0; i < line.length; i++) {
    final c = line[i];
    if (quote != null) {
      if (c == '\\' && quote == '"') {
        i++;
      } else if (c == quote) {
        quote = null;
      }
      continue;
    }
    if (c == '"' || c == "'") {
      // A quote only opens a quoted scalar at the start of a value.
      final before = line.substring(0, i).trimRight();
      if (before.isEmpty ||
          before.endsWith(':') ||
          before.endsWith('-') ||
          before.endsWith(',') ||
          before.endsWith('[') ||
          before.endsWith('{')) {
        quote = c;
      }
      continue;
    }
    if (c == '#' && (i == 0 || line[i - 1] == ' ' || line[i - 1] == '\t')) {
      return line.substring(0, i);
    }
  }
  return line;
}

class _Parser {
  _Parser(this.lines);
  final List<_Line> lines;
  int pos = 0;

  _Line? get current => pos < lines.length ? lines[pos] : null;

  Object? block(int indent) {
    final line = current;
    if (line == null) return null;
    if (_isSeqItem(line.text)) return sequence(line.indent);
    return mapping(line.indent);
  }

  static bool _isSeqItem(String text) => text == '-' || text.startsWith('- ');

  List<Object?> sequence(int indent) {
    final out = <Object?>[];
    while (true) {
      final line = current;
      if (line == null || line.indent != indent || !_isSeqItem(line.text)) {
        break;
      }
      final rest = line.text.substring(1).trimLeft();
      if (rest.isEmpty) {
        pos++;
        final next = current;
        out.add(next != null && next.indent > indent ? block(next.indent) : null);
        continue;
      }
      if (_mappingColon(rest) >= 0 && !rest.startsWith('{') && !rest.startsWith('[')) {
        // "- key: value" starts a mapping whose keys line up with "key".
        final column = indent + (line.text.length - rest.length);
        lines[pos] = _Line(column, rest, line.number);
        out.add(mapping(column));
        continue;
      }
      pos++;
      out.add(inline(rest, line.number));
    }
    return out;
  }

  Map<String, Object?> mapping(int indent) {
    final out = <String, Object?>{};
    while (true) {
      final line = current;
      if (line == null || line.indent != indent || _isSeqItem(line.text)) break;
      final colon = _mappingColon(line.text);
      if (colon < 0) {
        throw FormatException('line ${line.number}: expected "key: value"');
      }
      final key = _scalarString(line.text.substring(0, colon).trim());
      final valueText = line.text.substring(colon + 1).trim();
      pos++;
      if (valueText.isEmpty) {
        final next = current;
        if (next != null &&
            (next.indent > indent ||
                (next.indent == indent && _isSeqItem(next.text)))) {
          out[key] = block(next.indent);
        } else {
          out[key] = null;
        }
      } else if (valueText == '|' ||
          valueText == '>' ||
          valueText.startsWith('|-') ||
          valueText.startsWith('>-')) {
        final parts = <String>[];
        while (current != null && current!.indent > indent) {
          parts.add(current!.text);
          pos++;
        }
        out[key] = valueText.startsWith('|') ? parts.join('\n') : parts.join(' ');
      } else {
        out[key] = inline(valueText, line.number);
      }
    }
    return out;
  }

  /// A value on one line; a flow collection may continue on the next lines.
  Object? inline(String text, int number) {
    var s = text;
    if (s.startsWith('{') || s.startsWith('[')) {
      while (!_balanced(s) && current != null) {
        s = '$s ${current!.text}';
        pos++;
      }
      final flow = _Flow(s, number);
      final value = flow.value();
      return value;
    }
    return _scalar(s);
  }
}

/// Index of the ": " (or trailing ":") separating a key, outside quotes
/// and flow brackets; -1 when the text isn't a mapping entry.
int _mappingColon(String text) {
  String? quote;
  var depth = 0;
  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    if (quote != null) {
      if (c == '\\' && quote == '"') {
        i++;
      } else if (c == quote) {
        quote = null;
      }
      continue;
    }
    if ((c == '"' || c == "'") && i == 0) {
      quote = c;
    } else if (c == '{' || c == '[') {
      if (i == 0) return -1;
      depth++;
    } else if (c == '}' || c == ']') {
      depth--;
    } else if (c == ':' && depth == 0) {
      if (i == text.length - 1 || text[i + 1] == ' ') return i;
    }
  }
  return -1;
}

bool _balanced(String s) {
  var depth = 0;
  String? quote;
  for (var i = 0; i < s.length; i++) {
    final c = s[i];
    if (quote != null) {
      if (c == '\\' && quote == '"') {
        i++;
      } else if (c == quote) {
        quote = null;
      }
      continue;
    }
    if (c == '"' || c == "'") {
      quote = c;
    } else if (c == '{' || c == '[') {
      depth++;
    } else if (c == '}' || c == ']') {
      depth--;
    }
  }
  return depth <= 0;
}

class _Flow {
  _Flow(this.s, this.number);
  final String s;
  final int number;
  int i = 0;

  Never _fail(String what) =>
      throw FormatException('line $number: $what in flow collection');

  void _ws() {
    while (i < s.length && (s[i] == ' ' || s[i] == '\t')) {
      i++;
    }
  }

  Object? value() {
    _ws();
    if (i >= s.length) _fail('unexpected end');
    final c = s[i];
    if (c == '{') return _map();
    if (c == '[') return _list();
    if (c == '"' || c == "'") return _quoted();
    final start = i;
    while (i < s.length && !',}]'.contains(s[i])) {
      i++;
    }
    return _scalar(s.substring(start, i).trim());
  }

  Map<String, Object?> _map() {
    i++; // {
    final out = <String, Object?>{};
    while (true) {
      _ws();
      if (i >= s.length) _fail('unclosed {');
      if (s[i] == '}') {
        i++;
        return out;
      }
      final String key;
      if (s[i] == '"' || s[i] == "'") {
        key = _quoted();
      } else {
        final start = i;
        while (i < s.length && s[i] != ':' && s[i] != ',' && s[i] != '}') {
          i++;
        }
        key = s.substring(start, i).trim();
      }
      _ws();
      Object? v;
      if (i < s.length && s[i] == ':') {
        i++;
        _ws();
        v = (i < s.length && (s[i] == ',' || s[i] == '}')) ? null : value();
      }
      out[key] = v;
      _ws();
      if (i < s.length && s[i] == ',') i++;
    }
  }

  List<Object?> _list() {
    i++; // [
    final out = <Object?>[];
    while (true) {
      _ws();
      if (i >= s.length) _fail('unclosed [');
      if (s[i] == ']') {
        i++;
        return out;
      }
      out.add(value());
      _ws();
      if (i < s.length && s[i] == ',') i++;
    }
  }

  String _quoted() {
    final q = s[i];
    final start = i;
    i++;
    while (i < s.length) {
      if (q == '"' && s[i] == '\\') {
        i += 2;
        continue;
      }
      if (s[i] == q) {
        if (q == "'" && i + 1 < s.length && s[i + 1] == "'") {
          i += 2;
          continue;
        }
        i++;
        return _scalarString(s.substring(start, i));
      }
      i++;
    }
    _fail('unclosed quote');
  }
}

Object? _scalar(String raw) {
  final s = raw.trim();
  if (s.isEmpty || s == '~' || s == 'null' || s == 'Null' || s == 'NULL') {
    return null;
  }
  if (s.startsWith('"') || s.startsWith("'")) return _scalarString(s);
  switch (s) {
    case 'true':
    case 'True':
    case 'TRUE':
      return true;
    case 'false':
    case 'False':
    case 'FALSE':
      return false;
  }
  if (RegExp(r'^[-+]?\d+$').hasMatch(s)) return int.tryParse(s) ?? s;
  if (RegExp(r'^[-+]?\d*\.\d+$').hasMatch(s)) return double.tryParse(s) ?? s;
  return s;
}

/// A key or quoted scalar as a string (quotes removed, escapes resolved).
String _scalarString(String raw) {
  final s = raw.trim();
  if (s.length >= 2 && s.startsWith("'") && s.endsWith("'")) {
    return s.substring(1, s.length - 1).replaceAll("''", "'");
  }
  if (s.length >= 2 && s.startsWith('"') && s.endsWith('"')) {
    final body = s.substring(1, s.length - 1);
    final out = StringBuffer();
    for (var i = 0; i < body.length; i++) {
      final c = body[i];
      if (c != '\\' || i + 1 >= body.length) {
        out.write(c);
        continue;
      }
      final e = body[++i];
      switch (e) {
        case 'n':
          out.write('\n');
        case 't':
          out.write('\t');
        case 'r':
          out.write('\r');
        case 'u':
          if (i + 4 < body.length) {
            final code = int.tryParse(body.substring(i + 1, i + 5), radix: 16);
            if (code != null) {
              out.writeCharCode(code);
              i += 4;
              break;
            }
          }
          out.write('u');
        default:
          out.write(e);
      }
    }
    return out.toString();
  }
  return s;
}
