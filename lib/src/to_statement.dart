/// Placeholder style used when rewriting SQL to PostgreSQL `$n` parameters.
class PlaceholderIdentifier {
  final String value;

  const PlaceholderIdentifier(this.value);

  /// Named colon parameters, for example `WHERE id = :id`.
  static const colon = PlaceholderIdentifier(':');

  /// Positional question-mark parameters, for example `WHERE id = ?`.
  ///
  /// This mode is explicit because PostgreSQL also uses `?`, `?|`, and `?&`
  /// as JSON operators. SQL using those operators should keep [pgDefault].
  static const onlyQuestionMark = PlaceholderIdentifier('?');

  /// Named at-sign parameters, for example `WHERE id = @id`.
  static const atSign = PlaceholderIdentifier('@');

  /// Native PostgreSQL positional parameters: `$1`, `$2`, and so on.
  static const pgDefault = PlaceholderIdentifier(r'$#');
}

/// Rewrites named parameters to PostgreSQL `$n` parameters.
///
/// Repeated names reuse the same position. Placeholder-like text inside SQL
/// strings, quoted identifiers, comments, and dollar-quoted bodies is kept
/// verbatim. Returns the rewritten SQL followed by the ordered values.
List<dynamic> toStatement(
  String query,
  Map params, {
  String placeholderIdentifier = ':',
}) {
  if (placeholderIdentifier.length != 1) {
    throw ArgumentError.value(
      placeholderIdentifier,
      'placeholderIdentifier',
      'A named placeholder identifier must contain one character.',
    );
  }

  final positions = <String, int>{};
  final values = <dynamic>[];
  final rewritten = _rewriteSqlPlaceholders(
    query,
    placeholderIdentifier,
    named: true,
    replacement: (name) {
      final existing = positions[name];
      if (existing != null) return '\$$existing';
      if (!params.containsKey(name)) {
        throw ArgumentError(
          "SQL contains the placeholder '$name', but params has no such key.",
        );
      }
      values.add(params[name]);
      final position = values.length;
      positions[name] = position;
      return '\$$position';
    },
  );
  return <dynamic>[rewritten, values];
}

/// Rewrites explicit question-mark parameters to PostgreSQL `$n` parameters.
String toStatement2(String query) {
  var position = 0;
  return _rewriteSqlPlaceholders(
    query,
    '?',
    named: false,
    replacement: (_) => '\$${++position}',
  );
}

String _rewriteSqlPlaceholders(
  String query,
  String marker, {
  required bool named,
  required String Function(String name) replacement,
}) {
  if (!query.contains(marker)) return query;

  final markerCodeUnit = marker.codeUnitAt(0);
  final length = query.length;
  StringBuffer? output;
  var copyFrom = 0;
  var index = 0;

  while (index < length) {
    final codeUnit = query.codeUnitAt(index);

    if (codeUnit == 0x27) {
      index = _skipSingleQuoted(query, index);
      continue;
    }
    if (codeUnit == 0x22) {
      index = _skipDoubleQuoted(query, index);
      continue;
    }
    if (codeUnit == 0x2d &&
        index + 1 < length &&
        query.codeUnitAt(index + 1) == 0x2d) {
      index = _skipLineComment(query, index + 2);
      continue;
    }
    if (codeUnit == 0x2f &&
        index + 1 < length &&
        query.codeUnitAt(index + 1) == 0x2a) {
      index = _skipBlockComment(query, index + 2);
      continue;
    }
    if (codeUnit == 0x24) {
      final afterDollarQuote = _afterDollarQuote(query, index);
      if (afterDollarQuote != index) {
        index = afterDollarQuote;
        continue;
      }
    }

    if (codeUnit != markerCodeUnit) {
      index++;
      continue;
    }

    var end = index + 1;
    var name = '';
    if (named) {
      if ((index > 0 && query.codeUnitAt(index - 1) == markerCodeUnit) ||
          end >= length ||
          !_isPlaceholderNameCodeUnit(query.codeUnitAt(end))) {
        index++;
        continue;
      }
      while (end < length &&
          _isPlaceholderNameCodeUnit(query.codeUnitAt(end))) {
        end++;
      }
      name = query.substring(index + 1, end);
    }

    final target = output ??= StringBuffer();
    target.write(query.substring(copyFrom, index));
    target.write(replacement(name));
    copyFrom = end;
    index = end;
  }

  if (output == null) return query;
  output.write(query.substring(copyFrom));
  return output.toString();
}

int _skipSingleQuoted(String query, int index) {
  index++;
  while (index < query.length) {
    final current = query.codeUnitAt(index);
    if (current == 0x5c && index + 1 < query.length) {
      index += 2;
    } else if (current == 0x27) {
      if (index + 1 < query.length && query.codeUnitAt(index + 1) == 0x27) {
        index += 2;
      } else {
        return index + 1;
      }
    } else {
      index++;
    }
  }
  return index;
}

int _skipDoubleQuoted(String query, int index) {
  index++;
  while (index < query.length) {
    if (query.codeUnitAt(index) == 0x22) {
      if (index + 1 < query.length && query.codeUnitAt(index + 1) == 0x22) {
        index += 2;
      } else {
        return index + 1;
      }
    } else {
      index++;
    }
  }
  return index;
}

int _skipLineComment(String query, int index) {
  while (index < query.length && query.codeUnitAt(index) != 0x0a) {
    index++;
  }
  return index;
}

int _skipBlockComment(String query, int index) {
  var depth = 1;
  while (index < query.length && depth != 0) {
    if (index + 1 < query.length &&
        query.codeUnitAt(index) == 0x2f &&
        query.codeUnitAt(index + 1) == 0x2a) {
      depth++;
      index += 2;
    } else if (index + 1 < query.length &&
        query.codeUnitAt(index) == 0x2a &&
        query.codeUnitAt(index + 1) == 0x2f) {
      depth--;
      index += 2;
    } else {
      index++;
    }
  }
  return index;
}

int _afterDollarQuote(String query, int index) {
  final length = query.length;
  var delimiterEnd = index + 1;
  if (delimiterEnd >= length) return index;

  if (query.codeUnitAt(delimiterEnd) != 0x24) {
    if (!_isDollarQuoteTagStart(query.codeUnitAt(delimiterEnd))) return index;
    delimiterEnd++;
    while (delimiterEnd < length &&
        _isDollarQuoteTagPart(query.codeUnitAt(delimiterEnd))) {
      delimiterEnd++;
    }
    if (delimiterEnd >= length || query.codeUnitAt(delimiterEnd) != 0x24) {
      return index;
    }
  }

  final delimiter = query.substring(index, delimiterEnd + 1);
  final bodyEnd = query.indexOf(delimiter, delimiterEnd + 1);
  return bodyEnd < 0 ? index : bodyEnd + delimiter.length;
}

bool _isPlaceholderNameCodeUnit(int codeUnit) =>
    (codeUnit >= 0x30 && codeUnit <= 0x39) ||
    (codeUnit >= 0x41 && codeUnit <= 0x5a) ||
    codeUnit == 0x5f ||
    (codeUnit >= 0x61 && codeUnit <= 0x7a);

bool _isDollarQuoteTagStart(int codeUnit) =>
    (codeUnit >= 0x41 && codeUnit <= 0x5a) ||
    codeUnit == 0x5f ||
    (codeUnit >= 0x61 && codeUnit <= 0x7a) ||
    codeUnit >= 0x80;

bool _isDollarQuoteTagPart(int codeUnit) =>
    _isDollarQuoteTagStart(codeUnit) ||
    (codeUnit >= 0x30 && codeUnit <= 0x39);
