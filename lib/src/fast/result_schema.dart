import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import '../column_description.dart';
import '../converters.dart';
import '../utils/pg_datetime_codec.dart';

/// Decodes one non-null PostgreSQL field directly from a byte range.
///
/// [offset] and [length] refer to [bytes] and no byte slice is created by the
/// schema. A decoder may still allocate the value it returns (for example a
/// [String], [DateTime], JSON object, or the required safe copy of `bytea`).
typedef PgColumnDecoder = Object? Function(
    Uint8List bytes, int offset, int length);

typedef _RangeTextDecoder = String Function(
    Uint8List bytes, int offset, int length);

/// Column metadata and decoder functions shared by every row in a result set.
///
/// Decoder selection happens once, when the schema is built. Data-row decoding
/// therefore performs no OID switch and creates no byte sublist per cell.
class ResultSchema {
  static const int _formatText = 0;
  static const int _formatBinary = 1;

  static const int _oidBool = 16;
  static const int _oidBytea = 17;
  static const int _oidChar = 18;
  static const int _oidName = 19;
  static const int _oidInt8 = 20;
  static const int _oidInt2 = 21;
  static const int _oidInt4 = 23;
  static const int _oidText = 25;
  static const int _oidOid = 26;
  static const int _oidXid = 28;
  static const int _oidJson = 114;
  static const int _oidFloat4 = 700;
  static const int _oidFloat8 = 701;
  static const int _oidUnknown = 705;
  static const int _oidBpchar = 1042;
  static const int _oidVarchar = 1043;
  static const int _oidDate = 1082;
  static const int _oidTimestamp = 1114;
  static const int _oidTimestamptz = 1184;
  static const int _oidNumeric = 1700;
  static const int _oidUuid = 2950;
  static const int _oidJsonb = 3802;

  /// Immutable column descriptions in wire order.
  final List<ColumnDescription> columns;

  /// One already-resolved decoder for each entry in [columns].
  final List<PgColumnDecoder> decoders;

  /// Name lookup shared by all rows decoded with this schema.
  ///
  /// As with PostgreSQL row-to-map APIs generally, the last column wins when a
  /// result contains duplicate column names.
  final Map<String, int> nameToIndex;

  /// Per-column formats to request in Bind for the fastest supported decoding.
  ///
  /// A value is `1` for a supported binary codec and `0` for text fallback.
  final List<int> preferredResultFormats;

  /// OIDs for columns that do not have a complete binary decoder.
  ///
  /// This is resolved once with the preferred formats. It may contain the
  /// same OID more than once when that type appears in multiple columns.
  final List<int> unsupportedBinaryOids;

  final TypeConverter typeConverter;

  factory ResultSchema(
          List<ColumnDescription> columns, TypeConverter typeConverter) =>
      ResultSchema.fromColumns(columns, typeConverter);

  factory ResultSchema.fromColumns(
      List<ColumnDescription> columns, TypeConverter typeConverter) {
    final immutableColumns = List<ColumnDescription>.unmodifiable(columns);
    final indexes = <String, int>{};
    for (var i = 0; i < immutableColumns.length; i++) {
      indexes[immutableColumns[i].name] = i;
    }
    final immutableIndexes = Map<String, int>.unmodifiable(indexes);
    final preferred = List<int>.filled(
        immutableColumns.length, _formatText,
        growable: false);
    List<int>? unsupported;
    for (var i = 0; i < immutableColumns.length; i++) {
      final oid = immutableColumns[i].fieldType;
      if (supportsBinaryOid(oid)) {
        preferred[i] = _formatBinary;
      } else {
        (unsupported ??= <int>[]).add(oid);
      }
    }
    final immutablePreferred = List<int>.unmodifiable(preferred);
    final immutableUnsupported = unsupported == null
        ? const <int>[]
        : List<int>.unmodifiable(unsupported);
    return ResultSchema._build(immutableColumns, typeConverter,
        immutableIndexes, immutablePreferred, immutableUnsupported);
  }

  factory ResultSchema._build(
      List<ColumnDescription> columns,
      TypeConverter typeConverter,
      Map<String, int> nameToIndex,
      List<int> preferredResultFormats,
      List<int> unsupportedBinaryOids) {
    final textDecoder = _textDecoderFor(typeConverter.textCharset);
    final resolved = List<PgColumnDecoder>.generate(columns.length,
        (index) => _resolveDecoder(columns[index], typeConverter, textDecoder),
        growable: false);
    return ResultSchema._(columns, List<PgColumnDecoder>.unmodifiable(resolved),
        nameToIndex,
        preferredResultFormats,
        unsupportedBinaryOids,
        typeConverter);
  }

  ResultSchema._(this.columns, this.decoders, this.nameToIndex,
      this.preferredResultFormats,
      this.unsupportedBinaryOids,
      this.typeConverter);

  int get columnCount => columns.length;

  /// Whether all result columns have complete binary decoders.
  bool get supportsAllBinary => unsupportedBinaryOids.isEmpty;

  bool get usesPreferredResultFormats {
    for (var i = 0; i < columns.length; i++) {
      if (columns[i].formatCode != preferredResultFormats[i]) return false;
    }
    return true;
  }

  /// Whether [oid] has a complete binary decoder in this schema.
  static bool supportsBinaryOid(int oid) {
    switch (oid) {
      case _oidBool:
      case _oidBytea:
      case _oidChar:
      case _oidName:
      case _oidInt8:
      case _oidInt2:
      case _oidInt4:
      case _oidText:
      case _oidOid:
      case _oidXid:
      case _oidJson:
      case _oidFloat4:
      case _oidFloat8:
      case _oidBpchar:
      case _oidVarchar:
      case _oidDate:
      case _oidTimestamp:
      case _oidTimestamptz:
      case _oidUuid:
      case _oidJsonb:
        return true;
      default:
        return false;
    }
  }

  /// Returns a schema whose column formats match [preferredResultFormats].
  ///
  /// The returned schema shares [nameToIndex] and the preferred-format list
  /// with this one. It only clones column metadata and resolves the changed
  /// decoders once.
  ResultSchema withPreferredBinary() =>
      withResultFormats(preferredResultFormats);

  /// Returns a schema using explicit per-column PostgreSQL format codes.
  ResultSchema withResultFormats(List<int> formats) {
    if (formats.length != columns.length) {
      throw ArgumentError.value(formats.length, 'formats.length',
          'Expected ${columns.length} result format codes.');
    }

    var changed = false;
    final cloned = List<ColumnDescription>.generate(columns.length, (index) {
      final format = formats[index];
      if (format != _formatText && format != _formatBinary) {
        throw ArgumentError.value(
            format, 'formats[$index]', 'Format code must be 0 or 1.');
      }
      final column = columns[index];
      if (column.formatCode == format) return column;
      changed = true;
      return ColumnDescription(
          column.index,
          column.name,
          column.fieldId,
          column.tableColNo,
          column.fieldType,
          column.dataSize,
          column.typeModifier,
          format);
    }, growable: false);

    if (!changed) return this;
    return ResultSchema._build(List<ColumnDescription>.unmodifiable(cloned),
        typeConverter,
        nameToIndex,
        preferredResultFormats,
        unsupportedBinaryOids);
  }

  /// Decodes a complete DataRow body into a fixed-length list.
  ///
  /// [baseOffset] points at the DataRow column-count field. [messageLength],
  /// when supplied, is the body length starting at that offset. This allows a
  /// caller to pass a larger receive buffer without creating a view.
  List<Object?> decodeRow(Uint8List bytes,
      {int baseOffset = 0, int? messageLength}) {
    final values = List<Object?>.filled(columns.length, null, growable: false);
    decodeRowInto(bytes, values,
        baseOffset: baseOffset, messageLength: messageLength);
    return values;
  }

  /// Decodes a complete DataRow body into a caller-owned, reusable list.
  void decodeRowInto(Uint8List bytes, List<Object?> values,
      {int baseOffset = 0, int? messageLength}) {
    if (values.length != columns.length) {
      throw ArgumentError.value(values.length, 'values.length',
          'Expected a fixed list with ${columns.length} entries.');
    }
    final end = _checkedMessageEnd(bytes, baseOffset, messageLength);
    var cursor = _readAndCheckColumnCount(bytes, baseOffset, end);

    for (var i = 0; i < columns.length; i++) {
      if (cursor + 4 > end) {
        throw const FormatException('Truncated DataRow field length.');
      }
      final length = _readInt32(bytes, cursor);
      cursor += 4;
      if (length == -1) {
        values[i] = null;
        continue;
      }
      if (length < 0 || cursor + length > end) {
        throw FormatException('Invalid DataRow field length $length.');
      }
      values[i] = decoders[i](bytes, cursor, length);
      cursor += length;
    }
    _checkMessageConsumed(cursor, end);
  }

  /// Decodes a DataRow directly into a newly-created map.
  ///
  /// No intermediate row list is allocated. Column-name strings come from the
  /// shared schema.
  Map<String, dynamic> decodeMap(Uint8List bytes,
      {int baseOffset = 0, int? messageLength}) {
    final result = <String, dynamic>{};
    decodeMapInto(bytes, result,
        baseOffset: baseOffset, messageLength: messageLength, clear: false);
    return result;
  }

  /// Decodes a DataRow into [result], optionally reusing an existing map.
  void decodeMapInto(Uint8List bytes, Map<String, dynamic> result,
      {int baseOffset = 0, int? messageLength, bool clear = true}) {
    if (clear) result.clear();
    final end = _checkedMessageEnd(bytes, baseOffset, messageLength);
    var cursor = _readAndCheckColumnCount(bytes, baseOffset, end);

    for (var i = 0; i < columns.length; i++) {
      if (cursor + 4 > end) {
        throw const FormatException('Truncated DataRow field length.');
      }
      final length = _readInt32(bytes, cursor);
      cursor += 4;
      Object? value;
      if (length == -1) {
        value = null;
      } else {
        if (length < 0 || cursor + length > end) {
          throw FormatException('Invalid DataRow field length $length.');
        }
        value = decoders[i](bytes, cursor, length);
        cursor += length;
      }
      result[columns[i].name] = value;
    }
    _checkMessageConsumed(cursor, end);
  }

  /// Decodes one non-null value using the already-resolved column decoder.
  Object? decodeColumn(
          int columnIndex, Uint8List bytes, int offset, int length) =>
      decoders[columnIndex](bytes, offset, length);

  int _readAndCheckColumnCount(Uint8List bytes, int offset, int end) {
    if (offset + 2 > end) {
      throw const FormatException('Truncated DataRow column count.');
    }
    final count = _readUint16(bytes, offset);
    if (count != columns.length) {
      throw FormatException(
          'DataRow has $count columns; schema has ${columns.length}.');
    }
    return offset + 2;
  }

  static int _checkedMessageEnd(
      Uint8List bytes, int baseOffset, int? messageLength) {
    if (baseOffset < 0 || baseOffset > bytes.length) {
      throw RangeError.range(baseOffset, 0, bytes.length, 'baseOffset');
    }
    final length = messageLength ?? bytes.length - baseOffset;
    if (length < 0 || length > bytes.length - baseOffset) {
      throw RangeError.range(
          length, 0, bytes.length - baseOffset, 'messageLength');
    }
    return baseOffset + length;
  }

  static void _checkMessageConsumed(int cursor, int end) {
    if (cursor != end) {
      throw FormatException(
          'DataRow contains ${end - cursor} trailing byte(s).');
    }
  }

  static PgColumnDecoder _resolveDecoder(ColumnDescription column,
      TypeConverter converter, _RangeTextDecoder textDecoder) {
    if (column.formatCode == _formatText) {
      return _resolveTextDecoder(column.fieldType, converter, textDecoder);
    }
    if (column.formatCode == _formatBinary) {
      return _resolveBinaryDecoder(column.fieldType, converter, textDecoder);
    }
    throw ArgumentError.value(column.formatCode, 'column.formatCode',
        'PostgreSQL format code must be 0 or 1.');
  }

  static PgColumnDecoder _resolveTextDecoder(
      int oid, TypeConverter converter, _RangeTextDecoder textDecoder) {
    switch (oid) {
      case _oidBool:
        return (bytes, offset, length) =>
            length > 0 && bytes[offset] == 0x74; // 't'
      case _oidInt2:
      case _oidInt4:
      case _oidInt8:
      case _oidOid:
      case _oidXid:
        return _parseTextInt;
      case _oidFloat4:
      case _oidFloat8:
      case _oidNumeric:
        return _parseTextDouble;
      case _oidChar:
      case _oidName:
      case _oidText:
      case _oidUnknown:
      case _oidBpchar:
      case _oidVarchar:
      case _oidUuid:
        return textDecoder;
      case _oidBytea:
        return (bytes, offset, length) =>
            converter.bytesIn(textDecoder(bytes, offset, length));
      case _oidDate:
        return (bytes, offset, length) =>
            converter.dateIn(textDecoder(bytes, offset, length));
      case _oidTimestamp:
        return (bytes, offset, length) =>
            converter.timestampIn(textDecoder(bytes, offset, length));
      case _oidTimestamptz:
        return (bytes, offset, length) =>
            converter.timestampTzIn(textDecoder(bytes, offset, length));
      case _oidJson:
      case _oidJsonb:
        return (bytes, offset, length) =>
            jsonDecode(textDecoder(bytes, offset, length));
      default:
        // Preserves all existing text conversions, including arrays and custom
        // types, while still resolving this fallback once per column.
        return (bytes, offset, length) => converter.decodeValuePg8000(
            textDecoder(bytes, offset, length), oid);
    }
  }

  static PgColumnDecoder _resolveBinaryDecoder(
      int oid, TypeConverter converter, _RangeTextDecoder textDecoder) {
    switch (oid) {
      case _oidBool:
        return (bytes, offset, length) {
          _expectLength(oid, length, 1);
          return bytes[offset] != 0;
        };
      case _oidInt2:
        return (bytes, offset, length) {
          _expectLength(oid, length, 2);
          return _readInt16(bytes, offset);
        };
      case _oidInt4:
        return (bytes, offset, length) {
          _expectLength(oid, length, 4);
          return _readInt32(bytes, offset);
        };
      case _oidInt8:
        return (bytes, offset, length) {
          _expectLength(oid, length, 8);
          return _readInt64(bytes, offset);
        };
      case _oidOid:
      case _oidXid:
        return (bytes, offset, length) {
          _expectLength(oid, length, 4);
          return _readUint32(bytes, offset);
        };
      case _oidFloat4:
        return _binaryFloat32Decoder(oid);
      case _oidFloat8:
        return _binaryFloat64Decoder(oid);
      case _oidChar:
      case _oidName:
      case _oidText:
      case _oidBpchar:
      case _oidVarchar:
        return textDecoder;
      case _oidBytea:
        return (bytes, offset, length) {
          final result = Uint8List(length);
          result.setRange(0, length, bytes, offset);
          return result;
        };
      case _oidUuid:
        return _binaryUuidDecoder(oid);
      case _oidDate:
        return _binaryDateDecoder(oid, converter);
      case _oidTimestamp:
        return _binaryTimestampDecoder(oid, converter, false);
      case _oidTimestamptz:
        return _binaryTimestampDecoder(oid, converter, true);
      case _oidJson:
        return (bytes, offset, length) =>
            jsonDecode(textDecoder(bytes, offset, length));
      case _oidJsonb:
        return (bytes, offset, length) {
          if (length < 1) {
            throw const FormatException('Empty binary jsonb value.');
          }
          final version = bytes[offset];
          if (version != 1) {
            throw FormatException('Unsupported binary jsonb version $version.');
          }
          return jsonDecode(textDecoder(bytes, offset + 1, length - 1));
        };
      default:
        // Unknown and extension OIDs are deliberately kept as text. This is
        // also a safe fallback if a server returns binary unexpectedly.
        return textDecoder;
    }
  }

  static PgColumnDecoder _binaryFloat32Decoder(int oid) {
    // One scratch object per column, allocated when the schema is resolved.
    // Copying four bytes avoids a ByteData view allocation for every cell.
    final scratch = ByteData(4);
    return (bytes, offset, length) {
      _expectLength(oid, length, 4);
      scratch.setUint8(0, bytes[offset]);
      scratch.setUint8(1, bytes[offset + 1]);
      scratch.setUint8(2, bytes[offset + 2]);
      scratch.setUint8(3, bytes[offset + 3]);
      return scratch.getFloat32(0, Endian.big);
    };
  }

  static PgColumnDecoder _binaryFloat64Decoder(int oid) {
    final scratch = ByteData(8);
    return (bytes, offset, length) {
      _expectLength(oid, length, 8);
      for (var i = 0; i < 8; i++) {
        scratch.setUint8(i, bytes[offset + i]);
      }
      return scratch.getFloat64(0, Endian.big);
    };
  }

  static PgColumnDecoder _binaryUuidDecoder(int oid) {
    const hex = '0123456789abcdef';
    final output = Uint8List(36);
    output[8] = 0x2d;
    output[13] = 0x2d;
    output[18] = 0x2d;
    output[23] = 0x2d;
    return (bytes, offset, length) {
      _expectLength(oid, length, 16);
      var source = 0;
      var target = 0;
      while (source < 16) {
        if (target == 8 || target == 13 || target == 18 || target == 23) {
          target++;
        }
        final byte = bytes[offset + source++];
        output[target++] = hex.codeUnitAt(byte >> 4);
        output[target++] = hex.codeUnitAt(byte & 0x0f);
      }
      return String.fromCharCodes(output);
    };
  }

  static PgColumnDecoder _binaryDateDecoder(int oid, TypeConverter converter) {
    // Keep the ServerInfo identity, not the current immutable settings object.
    // PostgreSQL emits ParameterStatus after SET TIME ZONE and CoreConnection
    // replaces serverInfo.timeZone. Cached schemas must observe that update.
    final serverInfo = converter.serverInfo;
    return (bytes, offset, length) {
      _expectLength(oid, length, 4);
      final days = _readInt32(bytes, offset);
      try {
        return PgDateTimeCodec.decodeDate(days, timeZone: serverInfo.timeZone);
      } on ArgumentError {
        return null;
      }
    };
  }

  static PgColumnDecoder _binaryTimestampDecoder(
      int oid, TypeConverter converter, bool withTimeZone) {
    final integerDatetimes =
        converter.serverInfo.integerDatetimes?.toLowerCase() != 'off';
    final readFloat = integerDatetimes ? null : _binaryFloat64Decoder(oid);
    // A schema can outlive SET TIME ZONE in the statement cache. Reading the
    // mutable ServerInfo holder costs no allocation and prevents a cached
    // binary decoder from retaining obsolete TimeZoneSettings.
    final serverInfo = converter.serverInfo;
    return (bytes, offset, length) {
      final timeZone = serverInfo.timeZone;
      int microseconds;
      if (integerDatetimes) {
        _expectLength(oid, length, 8);
        microseconds = _readInt64(bytes, offset);
      } else {
        final seconds = readFloat!(bytes, offset, length) as double;
        if (seconds.isInfinite) {
          return PgDateTimeCodec.handleInfinity(
              withTimeZone ? 'timestamptz' : 'timestamp', timeZone);
        }
        if (seconds.isNaN) return null;
        microseconds = (seconds * Duration.microsecondsPerSecond).round();
      }

      try {
        return withTimeZone
            ? PgDateTimeCodec.decodeTimestamptz(microseconds,
                timeZone: timeZone)
            : PgDateTimeCodec.decodeTimestamp(microseconds,
                timeZone: timeZone);
      } on ArgumentError {
        return null;
      }
    };
  }

  static int _parseTextInt(Uint8List bytes, int offset, int length) {
    if (length == 0) throw const FormatException('Empty integer value.');
    final end = offset + length;
    var cursor = offset;
    var negative = false;
    final first = bytes[cursor];
    if (first == 0x2d || first == 0x2b) {
      negative = first == 0x2d;
      cursor++;
      if (cursor == end) throw const FormatException('Invalid integer value.');
    }
    var value = 0;
    while (cursor < end) {
      final digit = bytes[cursor++] - 0x30;
      if (digit < 0 || digit > 9) {
        throw const FormatException('Invalid integer value.');
      }
      value = value * 10 + digit;
    }
    return negative ? -value : value;
  }

  static double _parseTextDouble(Uint8List bytes, int offset, int length) {
    if (_asciiEquals(bytes, offset, length, 'NaN')) return double.nan;
    if (_asciiEquals(bytes, offset, length, 'Infinity')) {
      return double.infinity;
    }
    if (_asciiEquals(bytes, offset, length, '-Infinity')) {
      return double.negativeInfinity;
    }
    if (length == 0) throw const FormatException('Empty floating value.');

    final end = offset + length;
    var cursor = offset;
    var negative = false;
    if (bytes[cursor] == 0x2d || bytes[cursor] == 0x2b) {
      negative = bytes[cursor] == 0x2d;
      cursor++;
    }

    var value = 0.0;
    var digits = 0;
    while (cursor < end) {
      final digit = bytes[cursor] - 0x30;
      if (digit < 0 || digit > 9) break;
      value = value * 10.0 + digit;
      digits++;
      cursor++;
    }

    if (cursor < end && bytes[cursor] == 0x2e) {
      cursor++;
      var scale = 0.1;
      while (cursor < end) {
        final digit = bytes[cursor] - 0x30;
        if (digit < 0 || digit > 9) break;
        value += digit * scale;
        scale *= 0.1;
        digits++;
        cursor++;
      }
    }
    if (digits == 0) {
      throw const FormatException('Invalid floating value.');
    }

    if (cursor < end && (bytes[cursor] == 0x65 || bytes[cursor] == 0x45)) {
      cursor++;
      var exponentNegative = false;
      if (cursor < end && (bytes[cursor] == 0x2d || bytes[cursor] == 0x2b)) {
        exponentNegative = bytes[cursor] == 0x2d;
        cursor++;
      }
      if (cursor == end) {
        throw const FormatException('Invalid floating exponent.');
      }
      var exponent = 0;
      var exponentDigits = 0;
      while (cursor < end) {
        final digit = bytes[cursor++] - 0x30;
        if (digit < 0 || digit > 9) {
          throw const FormatException('Invalid floating exponent.');
        }
        exponent = exponent * 10 + digit;
        exponentDigits++;
      }
      if (exponentDigits == 0) {
        throw const FormatException('Invalid floating exponent.');
      }
      final factor = math.pow(10.0, exponent).toDouble();
      value = exponentNegative ? value / factor : value * factor;
    }
    if (cursor != end) {
      throw const FormatException('Invalid floating value.');
    }
    return negative ? -value : value;
  }

  static bool _asciiEquals(
      Uint8List bytes, int offset, int length, String value) {
    if (length != value.length) return false;
    for (var i = 0; i < length; i++) {
      if (bytes[offset + i] != value.codeUnitAt(i)) return false;
    }
    return true;
  }

  static _RangeTextDecoder _textDecoderFor(String charset) {
    switch (charset.toLowerCase().replaceAll('-', '_')) {
      case 'ascii':
      case 'sql_ascii':
        return (bytes, offset, length) =>
            ascii.decoder.convert(bytes, offset, offset + length);
      case 'latin1':
      case 'iso_8859_1':
        return (bytes, offset, length) =>
            latin1.decoder.convert(bytes, offset, offset + length);
      case 'win1252':
      case 'windows_1252':
        return _decodeWindows1252;
      case 'utf8':
      case 'utf_8':
      case 'unicode':
        return (bytes, offset, length) =>
            utf8.decoder.convert(bytes, offset, offset + length);
      default:
        const decoder = Utf8Decoder(allowMalformed: true);
        return (bytes, offset, length) =>
            decoder.convert(bytes, offset, offset + length);
    }
  }

  static String _decodeWindows1252(Uint8List bytes, int offset, int length) {
    const replacements = <int>[
      0x20ac,
      -1,
      0x201a,
      0x0192,
      0x201e,
      0x2026,
      0x2020,
      0x2021,
      0x02c6,
      0x2030,
      0x0160,
      0x2039,
      0x0152,
      -1,
      0x017d,
      -1,
      -1,
      0x2018,
      0x2019,
      0x201c,
      0x201d,
      0x2022,
      0x2013,
      0x2014,
      0x02dc,
      0x2122,
      0x0161,
      0x203a,
      0x0153,
      -1,
      0x017e,
      0x0178,
    ];
    final codePoints = List<int>.filled(length, 0, growable: false);
    for (var i = 0; i < length; i++) {
      final byte = bytes[offset + i];
      if (byte >= 0x80 && byte <= 0x9f) {
        final replacement = replacements[byte - 0x80];
        if (replacement < 0) {
          throw FormatException(
              'Invalid Windows-1252 byte 0x${byte.toRadixString(16)}.');
        }
        codePoints[i] = replacement;
      } else {
        codePoints[i] = byte;
      }
    }
    return String.fromCharCodes(codePoints);
  }

  static void _expectLength(int oid, int actual, int expected) {
    if (actual != expected) {
      throw FormatException(
          'Binary OID $oid has length $actual; expected $expected.');
    }
  }

  static int _readUint16(Uint8List bytes, int offset) =>
      (bytes[offset] << 8) | bytes[offset + 1];

  static int _readInt16(Uint8List bytes, int offset) {
    final value = _readUint16(bytes, offset);
    return value >= 0x8000 ? value - 0x10000 : value;
  }

  static int _readUint32(Uint8List bytes, int offset) =>
      bytes[offset] * 0x1000000 +
      bytes[offset + 1] * 0x10000 +
      bytes[offset + 2] * 0x100 +
      bytes[offset + 3];

  static int _readInt32(Uint8List bytes, int offset) {
    final value = _readUint32(bytes, offset);
    return value >= 0x80000000 ? value - 0x100000000 : value;
  }

  static int _readInt64(Uint8List bytes, int offset) {
    final high = _readInt32(bytes, offset);
    final low = _readUint32(bytes, offset + 4);
    return high * 0x100000000 + low;
  }
}
