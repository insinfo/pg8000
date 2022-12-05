library postgresql.substitute;

import 'dart:collection';
import 'charcode/ascii.dart';
import 'utils/pair.dart';
//import 'package:rikulo_commons/util.dart';

const int _TOKEN_TEXT = 1;
const int _TOKEN_IDENT = 3;

class _Token {
  _Token(this.type, this.value, [this.typeName]);
  final int type;
  final String value;
  final String typeName;

  @override
  String toString() =>
      '${['?', 'Text', 'At', 'Ident'][type]} "$value" "$typeName"';
}

typedef String _ValueEncoder(String identifier, String type);

bool isIdentifier(int charCode) =>
    (charCode >= $a && charCode <= $z) ||
    (charCode >= $A && charCode <= $Z) ||
    (charCode >= $0 && charCode <= $9) ||
    (charCode == $underscore);

bool isDigit(int charCode) => (charCode >= $0 && charCode <= $9);

class ParseException {
  ParseException(this.message, [this.source, this.index]);
  final String message;
  final String source;
  final int index;

  @override
  String toString() => (source == null || index == null)
      ? message
      : '$message At character: $index, in source "$source"';
}

String substitute(
    String source, values, String encodeValue(value, String type)) {
  _ValueEncoder valueEncoder;
  if (values is List)
    valueEncoder = _createListValueEncoder(values, encodeValue);
  else if (values is Map)
    valueEncoder = _createMapValueEncoder(values, encodeValue);
  else if (values == null)
    valueEncoder = _nullValueEncoder;
  else
    throw ArgumentError('Unexpected type.');

  final buf = StringBuffer(), s = _Scanner(source), cache = HashMap();

  while (s.hasMore()) {
    var t = s.read();
    if (t.type == _TOKEN_IDENT) {
      final id = t.value, typeName = t.typeName, key = new Pair(id, typeName);
      buf.write(cache[key] ?? (cache[key] = valueEncoder(id, typeName)));
    } else {
      buf.write(t.value);
    }
  }

  return buf.toString();
}

String _nullValueEncoder(value, String type) => throw new ParseException(
    'Template contains a parameter, but no values were passed.');

_ValueEncoder _createListValueEncoder(
        List list, String encodeValue(value, String type)) =>
    (String identifier, String type) {
      int i = int.tryParse(identifier) ??
          (throw new ParseException('Expected integer parameter.'));

      if (i < 0 || i >= list.length)
        throw ParseException('Substitution token out of range.');

      return encodeValue(list[i], type);
    };

_ValueEncoder _createMapValueEncoder(
        Map map, String encodeValue(value, String type)) =>
    (String identifier, String type) {
      final val = map[identifier];
      if (val == null && !map.containsKey(identifier))
        throw ParseException("Substitution token not passed: $identifier.");

      return encodeValue(val, type);
    };

class _Scanner {
  _Scanner(String source)
      : //_source = source,
        _r = new _CharReader(source) {
    if (_r.hasMore()) _t = _read();
  }

  //final String _source;
  final _CharReader _r;
  _Token _t;

  bool hasMore() => _t != null;

  _Token peek() => _t;

  _Token read() {
    var t = _t;
    _t = _r.hasMore() ? _read() : null;
    return t;
  }

  _Token _read() {
    assert(_r.hasMore());

    // '@@', '@ident', or '@ident:type'
    if (_r.peek() == $at) {
      _r.read();

      if (!_r.hasMore()) throw new ParseException('Unexpected end of input.');

      // '@@' or '@>' operator and '<@ '
      if (!isIdentifier(_r.peek())) {
        final s = new String.fromCharCode(_r.read());
        return new _Token(_TOKEN_TEXT, '@$s');
      }

      // Identifier
      var ident = _r.readWhile(isIdentifier);

      // Optional type modifier
      var type;
      if (_r.peek() == $colon) {
        _r.read();
        type = _r.readWhile(isIdentifier);
      }
      return new _Token(_TOKEN_IDENT, ident, type);
    }

    // Read plain text
    var text = _readText();
    return new _Token(_TOKEN_TEXT, text);
  }

  String _readText() {
    int esc;
    bool backslash = false;
    int ndollar;
    return _r.readWhile((int c) {
      if (backslash) {
        backslash = false;
      } else if (c == $backslash) {
        backslash = true;
      } else if (esc == null) {
        switch (c) {
          case $at:
            return false; //found!
          case $single_quote:
          case $quot:
          case $dollar:
            esc = c;
            if (c == $dollar) ndollar = 3; //$tag$string$tag$
            break;
        }
      } else if (c == esc) {
        if (c != $dollar || --ndollar == 0) esc = null;
      }

      return true;
    });
  }
}

class _CharReader {
  _CharReader(String source)
      : _source = source,
        _codes = source.codeUnits;

  final String _source;
  final List<int> _codes;
  int _i = 0;

  bool hasMore() => _i < _codes.length;

  int read() => hasMore() ? _codes[_i++] : 0;
  int peek() => hasMore() ? _codes[_i] : 0;

  String readWhile(bool test(int charCode)) {
    if (!hasMore())
      throw new ParseException('Unexpected end of input.', _source, _i);

    int start = _i;

    while (hasMore() && test(peek())) {
      read();
    }

    return String.fromCharCodes(_codes.sublist(start, _i));
  }
}
