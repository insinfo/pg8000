import 'dart:convert';
import 'dart:typed_data';

import 'package:dargres/src/column_description.dart';
import 'package:dargres/src/converters.dart';
import 'package:dargres/src/fast/result_schema.dart';
import 'package:dargres/src/server_info.dart';
import 'package:dargres/src/timezone_settings.dart';
import 'package:test/test.dart';

void main() {
  late TypeConverter converter;

  setUp(() {
    converter =
        TypeConverter('utf8', ServerInfo(timeZone: TimeZoneSettings('UTC')));
  });

  group('ResultSchema text decoding', () {
    test('decodes fast scalar paths and compatible fallback paths', () {
      final specs = <_ColumnSpec>[
        _ColumnSpec('bool', 16, 't'),
        _ColumnSpec('int2', 21, '-32768'),
        _ColumnSpec('int4', 23, '2147483647'),
        _ColumnSpec('int8', 20, '-9223372036854775808'),
        _ColumnSpec('oid', 26, '4294967295'),
        _ColumnSpec('xid', 28, '2147483648'),
        _ColumnSpec('float4', 700, '-1.25e2'),
        _ColumnSpec('float8', 701, 'Infinity'),
        _ColumnSpec('text', 25, 'olá'),
        _ColumnSpec('name', 19, 'a_name'),
        _ColumnSpec('varchar', 1043, 'varchar value'),
        _ColumnSpec('bpchar', 1042, 'x   '),
        _ColumnSpec('char', 18, 'Z'),
        _ColumnSpec('bytea', 17, r'\x0001fe'),
        _ColumnSpec('uuid', 2950, '00112233-4455-6677-8899-aabbccddeeff'),
        _ColumnSpec('date', 1082, '2024-01-02'),
        _ColumnSpec('timestamp', 1114, '2024-01-02 03:04:05.123456'),
        _ColumnSpec('timestamptz', 1184, '2024-01-02 03:04:05+00:00'),
        _ColumnSpec('json', 114, '{"value":1}'),
        _ColumnSpec('jsonb', 3802, '[true,false]'),
        _ColumnSpec('unknown', 705, 'untyped'),
        _ColumnSpec('array_fallback', 1007, '{1,2,NULL}'),
        const _ColumnSpec.nullValue('null_value', 25),
      ];
      final schema = ResultSchema.fromColumns(
          _columns(specs.map((spec) => spec.oid).toList()), converter);
      final fields = specs
          .map<List<int>?>(
              (spec) => spec.value == null ? null : utf8.encode(spec.value!))
          .toList();
      final row = schema.decodeRow(_dataRow(fields));

      expect(row[0], isTrue);
      expect(row[1], -32768);
      expect(row[2], 2147483647);
      expect(row[3], -9223372036854775808);
      expect(row[4], 4294967295);
      expect(row[5], 2147483648);
      expect(row[6], -125.0);
      expect(row[7], double.infinity);
      expect(row.sublist(8, 13),
          <Object?>['olá', 'a_name', 'varchar value', 'x   ', 'Z']);
      expect(row[13], <int>[0, 1, 254]);
      expect(row[14], '00112233-4455-6677-8899-aabbccddeeff');
      expect(row[15], DateTime.utc(2024, 1, 2));
      expect(row[16], DateTime.utc(2024, 1, 2, 3, 4, 5, 123, 456));
      expect(row[17], DateTime.utc(2024, 1, 2, 3, 4, 5));
      expect(row[18], <String, dynamic>{'value': 1});
      expect(row[19], <bool>[true, false]);
      expect(row[20], 'untyped');
      expect(row[21], <int?>[1, 2, null]);
      expect(row[22], isNull);
    });

    test('decodes a range in a larger receive buffer', () {
      final schema = ResultSchema.fromColumns(
          <ColumnDescription>[_column(0, 23), _column(1, 25)], converter);
      final body = _dataRow(<List<int>?>[
        utf8.encode('42'),
        utf8.encode('buffer range'),
      ]);
      final receiveBuffer = Uint8List(body.length + 7)
        ..fillRange(0, 3, 0xaa)
        ..setRange(3, 3 + body.length, body)
        ..fillRange(3 + body.length, body.length + 7, 0xbb);

      expect(
          schema.decodeRow(receiveBuffer,
              baseOffset: 3, messageLength: body.length),
          <Object?>[42, 'buffer range']);
    });

    test('maps directly and duplicate names use the last column', () {
      final schema = ResultSchema.fromColumns(<ColumnDescription>[
        _column(0, 25, name: 'duplicate'),
        _column(1, 23, name: 'other'),
        _column(2, 25, name: 'duplicate'),
      ], converter);
      final body = _dataRow(<List<int>?>[
        utf8.encode('first'),
        utf8.encode('7'),
        utf8.encode('last'),
      ]);

      expect(schema.nameToIndex, <String, int>{'duplicate': 2, 'other': 1});
      expect(schema.decodeMap(body),
          <String, dynamic>{'duplicate': 'last', 'other': 7});

      final reused = <String, dynamic>{'stale': true};
      schema.decodeMapInto(body, reused);
      expect(reused, <String, dynamic>{'duplicate': 'last', 'other': 7});
    });
  });

  group('ResultSchema binary decoding', () {
    test('decodes all supported binary scalar OIDs', () {
      final oids = <int>[
        16,
        21,
        23,
        20,
        26,
        28,
        700,
        701,
        25,
        19,
        1043,
        1042,
        18,
        17,
        2950,
        1082,
        1114,
        1184,
        114,
        3802,
      ];
      final textSchema = ResultSchema.fromColumns(_columns(oids), converter);
      final schema = textSchema.withPreferredBinary();
      final uuid = Uint8List.fromList(<int>[
        0x00,
        0x11,
        0x22,
        0x33,
        0x44,
        0x55,
        0x66,
        0x77,
        0x88,
        0x99,
        0xaa,
        0xbb,
        0xcc,
        0xdd,
        0xee,
        0xff,
      ]);
      final body = _dataRow(<List<int>?>[
        <int>[1],
        _int16(-1234),
        _int32(-2000000000),
        _int64(5000000000),
        _uint32(0xffffffff),
        _uint32(0x80000000),
        _float32(1.5),
        _float64(-2.25),
        utf8.encode('texto'),
        utf8.encode('name'),
        utf8.encode('varchar'),
        utf8.encode('bp  '),
        utf8.encode('Q'),
        <int>[0, 1, 2, 255],
        uuid,
        _int32(1),
        _int64(1234567),
        _int64(-1),
        utf8.encode('{"binary":true}'),
        <int>[1, ...utf8.encode('[1,2,3]')],
      ]);
      final row = schema.decodeRow(body);

      expect(row[0], isTrue);
      expect(row[1], -1234);
      expect(row[2], -2000000000);
      expect(row[3], 5000000000);
      expect(row[4], 4294967295);
      expect(row[5], 2147483648);
      expect(row[6], closeTo(1.5, 0.00001));
      expect(row[7], -2.25);
      expect(row.sublist(8, 13),
          <Object?>['texto', 'name', 'varchar', 'bp  ', 'Q']);
      expect(row[13], isA<Uint8List>());
      expect(row[13], <int>[0, 1, 2, 255]);
      expect(row[14], '00112233-4455-6677-8899-aabbccddeeff');
      expect(row[15], DateTime.utc(2000, 1, 2));
      expect(row[16], DateTime.utc(2000, 1, 1, 0, 0, 1, 234, 567));
      expect(row[17], DateTime.utc(1999, 12, 31, 23, 59, 59, 999, 999));
      expect(row[18], <String, dynamic>{'binary': true});
      expect(row[19], <int>[1, 2, 3]);
    });

    test('bytea owns a safe copy of ephemeral receive bytes', () {
      final schema = ResultSchema.fromColumns(
              <ColumnDescription>[_column(0, 17)], converter)
          .withPreferredBinary();
      final source = Uint8List.fromList(<int>[10, 20, 30]);
      final decoded = schema.decodeColumn(0, source, 0, source.length);
      source.fillRange(0, source.length, 0);

      expect(decoded, isA<Uint8List>());
      expect(decoded, <int>[10, 20, 30]);
    });

    test('date and timestamp infinities become null', () {
      final schema = ResultSchema.fromColumns(<ColumnDescription>[
        _column(0, 1082),
        _column(1, 1082),
        _column(2, 1114),
        _column(3, 1184),
      ], converter)
          .withPreferredBinary();
      final row = schema.decodeRow(_dataRow(<List<int>?>[
        _int32(2147483647),
        _int32(-2147483648),
        _int64(9223372036854775807),
        _int64(-9223372036854775808),
      ]));

      expect(row, everyElement(isNull));
    });

    test('local date and timestamp preserve PostgreSQL civil components', () {
      final localConverter = TypeConverter(
          'utf8',
          ServerInfo(
              timeZone: TimeZoneSettings('UTC',
                  forceDecodeDateAsUTC: false,
                  forceDecodeTimestampAsUTC: false)));
      final schema = ResultSchema.fromColumns(<ColumnDescription>[
        _column(0, 1082),
        _column(1, 1114),
      ], localConverter)
          .withPreferredBinary();
      final target = DateTime.utc(2018, 6, 15, 12, 34, 56, 789, 123);
      const pgEpochMicroseconds = 946684800000000;
      final row = schema.decodeRow(_dataRow(<List<int>?>[
        _int32(target.difference(DateTime.utc(2000)).inDays),
        _int64(target.microsecondsSinceEpoch - pgEpochMicroseconds),
      ]));

      expect(row[0], DateTime(2018, 6, 15));
      expect(row[1], DateTime(2018, 6, 15, 12, 34, 56, 789, 123));
    });

    test('cached binary schema observes current server timezone', () {
      final serverInfo = ServerInfo(
          timeZone: const TimeZoneSettings(
        'America/Sao_Paulo',
        forceDecodeTimestamptzAsUTC: false,
        useIanaTimeZoneDatabase: true,
      ));
      final dynamicConverter = TypeConverter('utf8', serverInfo);
      final schema = ResultSchema.fromColumns(
              <ColumnDescription>[_column(0, 1184)], dynamicConverter)
          .withPreferredBinary();
      final instant = DateTime.utc(2024, 1, 15, 12);
      const pgEpochMicroseconds = 946684800000000;
      final body = _dataRow(<List<int>?>[
        _int64(instant.microsecondsSinceEpoch - pgEpochMicroseconds),
      ]);

      final saoPaulo = schema.decodeRow(body).single as DateTime;
      expect(saoPaulo.toUtc(), instant);
      expect(saoPaulo.timeZoneOffset, const Duration(hours: -3));

      serverInfo.timeZone =
          serverInfo.timeZone.copyWith(value: 'America/New_York');
      final newYork = schema.decodeRow(body).single as DateTime;
      expect(newYork.toUtc(), instant);
      expect(newYork.timeZoneOffset, const Duration(hours: -5));
      expect(newYork.hour, 7);
    });

    test('jsonb validates its binary version byte', () {
      final schema = ResultSchema.fromColumns(
              <ColumnDescription>[_column(0, 3802)], converter)
          .withPreferredBinary();
      final body = _dataRow(<List<int>?>[
        <int>[2, ...utf8.encode('{}')]
      ]);

      expect(() => schema.decodeRow(body), throwsFormatException);
    });

    test('unsupported binary OID is left as text', () {
      final schema = ResultSchema.fromColumns(
              <ColumnDescription>[_column(0, 900001)], converter)
          .withResultFormats(<int>[1]);

      expect(schema.decodeRow(_dataRow(<List<int>?>[utf8.encode('extension')])),
          <Object?>['extension']);
      expect(schema.preferredResultFormats, <int>[0]);
      expect(schema.supportsAllBinary, isFalse);
      expect(schema.unsupportedBinaryOids, <int>[900001]);
    });
  });

  group('ResultSchema format selection and validation', () {
    test('selects binary only for supported types and shares name lookup', () {
      final text = ResultSchema.fromColumns(<ColumnDescription>[
        _column(0, 23, name: 'id'),
        _column(1, 1700, name: 'numeric'),
        _column(2, 3802, name: 'document'),
        _column(3, 705, name: 'unknown'),
      ], converter);
      final binary = text.withPreferredBinary();

      expect(text.preferredResultFormats, <int>[1, 0, 1, 0]);
      expect(
          binary.columns.map((column) => column.formatCode), <int>[1, 0, 1, 0]);
      expect(identical(text.nameToIndex, binary.nameToIndex), isTrue);
      expect(
          identical(text.preferredResultFormats, binary.preferredResultFormats),
          isTrue);
      expect(text.supportsAllBinary, isFalse);
      expect(text.unsupportedBinaryOids, <int>[1700, 705]);
      expect(identical(text.unsupportedBinaryOids, binary.unsupportedBinaryOids),
          isTrue);
    });

    test('reports all-binary support without rescanning column formats', () {
      final schema = ResultSchema.fromColumns(<ColumnDescription>[
        _column(0, 23),
        _column(1, 25),
        _column(2, 3802),
      ], converter);

      expect(schema.supportsAllBinary, isTrue);
      expect(schema.unsupportedBinaryOids, isEmpty);
    });

    test('decodeRowInto reuses the supplied fixed list', () {
      final schema = ResultSchema.fromColumns(
          <ColumnDescription>[_column(0, 23), _column(1, 25)], converter);
      final values = List<Object?>.filled(2, null, growable: false);
      schema.decodeRowInto(
          _dataRow(<List<int>?>[utf8.encode('1'), utf8.encode('first')]),
          values);
      expect(values, <Object?>[1, 'first']);

      schema.decodeRowInto(
          _dataRow(<List<int>?>[utf8.encode('2'), utf8.encode('second')]),
          values);
      expect(values, <Object?>[2, 'second']);
    });

    test('rejects malformed DataRow bodies and format lists', () {
      final schema = ResultSchema.fromColumns(
          <ColumnDescription>[_column(0, 23)], converter);

      expect(() => schema.decodeRow(Uint8List.fromList(<int>[0, 2])),
          throwsFormatException);
      expect(
          () =>
              schema.decodeRow(Uint8List.fromList(<int>[0, 1, 0, 0, 0, 5, 0])),
          throwsFormatException);
      expect(
          () => schema.decodeRow(
              Uint8List.fromList(<int>[0, 1, 0xff, 0xff, 0xff, 0xfe])),
          throwsFormatException);
      expect(() => schema.withResultFormats(<int>[]), throwsArgumentError);
      expect(() => schema.withResultFormats(<int>[2]), throwsArgumentError);
      expect(
          () => schema.decodeRowInto(_dataRow(<List<int>?>[null]), <Object?>[]),
          throwsArgumentError);
    });
  });
}

class _ColumnSpec {
  final String name;
  final int oid;
  final String? value;

  const _ColumnSpec(this.name, this.oid, this.value);

  const _ColumnSpec.nullValue(this.name, this.oid) : value = null;
}

List<ColumnDescription> _columns(List<int> oids, {int format = 0}) =>
    List<ColumnDescription>.generate(
        oids.length, (index) => _column(index, oids[index], format: format),
        growable: false);

ColumnDescription _column(int index, int oid, {String? name, int format = 0}) =>
    ColumnDescription(
        index, name ?? 'column_$index', 0, 0, oid, -1, -1, format);

Uint8List _dataRow(List<List<int>?> fields) {
  final builder = BytesBuilder(copy: false)..add(_uint16(fields.length));
  for (final field in fields) {
    if (field == null) {
      builder.add(_int32(-1));
    } else {
      builder
        ..add(_int32(field.length))
        ..add(field);
    }
  }
  return builder.takeBytes();
}

Uint8List _uint16(int value) =>
    (ByteData(2)..setUint16(0, value, Endian.big)).buffer.asUint8List();

Uint8List _int16(int value) =>
    (ByteData(2)..setInt16(0, value, Endian.big)).buffer.asUint8List();

Uint8List _int32(int value) =>
    (ByteData(4)..setInt32(0, value, Endian.big)).buffer.asUint8List();

Uint8List _uint32(int value) =>
    (ByteData(4)..setUint32(0, value, Endian.big)).buffer.asUint8List();

Uint8List _int64(int value) =>
    (ByteData(8)..setInt64(0, value, Endian.big)).buffer.asUint8List();

Uint8List _float32(double value) =>
    (ByteData(4)..setFloat32(0, value, Endian.big)).buffer.asUint8List();

Uint8List _float64(double value) =>
    (ByteData(8)..setFloat64(0, value, Endian.big)).buffer.asUint8List();
