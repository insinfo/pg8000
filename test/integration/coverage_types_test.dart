// Type round trips through every decoding path: cold execution (text),
// warm cache hit (selective binary), the simple protocol (text) and strict
// binary (requireBinaryResults, or UnsupportedError for types without a
// binary decoder), plus Dart values sent as parameters.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dargres/dargres.dart';
import 'package:test/test.dart';

String _env(String name, String fallback) {
  final value = Platform.environment[name];
  return value == null || value.isEmpty ? fallback : value;
}

ConnectionSettings _settings({
  String textCharset = 'utf8',
  bool numericAsString = false,
  TimeZoneSettings? timeZone,
}) =>
    ConnectionSettings(
      user: _env('PGUSER', 'dart'),
      database: _env('PGDATABASE', 'postgres'),
      host: _env('PGHOST', 'localhost'),
      port: int.parse(_env('PGPORT', '5432')),
      password: _env('PGPASSWORD', 'dart'),
      textCharset: textCharset,
      numericAsString: numericAsString,
      timeZone: timeZone,
      commandTimeout: const Duration(seconds: 10),
    );

/// [value] rounded to the float4 PostgreSQL stores.
double _f32(double value) => (Float32List(1)..[0] = value)[0];

/// A float4 read as text is the double of its shortest decimal (`0.1`);
/// read as binary it is the exact float4 (`0.10000000149011612`).
Matcher _float4(double value) => anyOf(equals(value), equals(_f32(value)));

final _negativeZero = predicate<Object?>(
    (v) => v is double && v == 0 && v.isNegative, 'negative zero');

Uint8List _bytes(List<int> values) => Uint8List.fromList(values);

/// One value: `select <expr> as v` with [params].
class _Case {
  const _Case(this.name, this.expr, this.expected,
      {this.params = const [], this.binary = false});

  final String name;
  final String expr;

  /// A value (deep equality) or a Matcher.
  final Object? expected;
  final List<Object?> params;

  /// Whether every result column has a binary decoder (requireBinaryResults
  /// succeeds); otherwise it must fail with UnsupportedError.
  final bool binary;
}

int _distinct = 0;

Future<void> _check(CoreConnection c, _Case k) async {
  final sql = 'select ${k.expr} as v';
  final matcher = k.expected is Matcher ? k.expected : equals(k.expected);

  final cold = (await c.queryNamed(sql, k.params)).single[0];
  expect(cold, matcher, reason: '${k.name}: cold execution (text)');
  final warm = (await c.queryNamed(sql, k.params)).single[0];
  expect(warm, matcher, reason: '${k.name}: cache hit (selective binary)');

  if (k.params.isEmpty) {
    final simple = (await c.querySimple(sql)).single[0];
    expect(simple, matcher, reason: '${k.name}: simple protocol (text)');
  }

  // A distinct statement, so strict binary also runs cold and then warm.
  final strictSql = '$sql /* strict ${_distinct++} */';
  for (final round in ['cold', 'warm']) {
    final strict =
        c.queryMaps(strictSql, params: k.params, requireBinaryResults: true);
    if (k.binary) {
      expect((await strict).single['v'], matcher,
          reason: '${k.name}: strict binary ($round)');
    } else {
      await expectLater(strict, throwsUnsupportedError,
          reason: '${k.name}: no binary decoder ($round)');
    }
  }
  // The connection is still in sync.
  expect((await c.queryNamed('select 7::int4', const [])).single[0], 7);
}

void _cases(String description, List<_Case> cases,
    {ConnectionSettings Function()? settings}) {
  group(description, () {
    late CoreConnection connection;
    setUpAll(() async {
      connection = CoreConnection.fromSettings((settings ?? _settings)());
      await connection.connect();
    });
    tearDownAll(() => connection.close());

    for (final k in cases) {
      test(k.name, () => _check(connection, k));
    }
  });
}

const _int8Min = -9223372036854775808;
const _int8Max = 9223372036854775807;

void main() {
  late CoreConnection admin;

  setUpAll(() async {
    admin = CoreConnection.fromSettings(_settings());
    await admin.connect();
    await admin.execute('drop type if exists cov_mood; '
        "create type cov_mood as enum ('sad', 'ok', 'happy')");
  });
  tearDownAll(() async {
    await admin.execute('drop type if exists cov_mood');
    await admin.close();
  });

  _cases('integers', [
    _Case('int2 min', '(-32768)::int2', -32768, binary: true),
    _Case('int2 max', '32767::int2', 32767, binary: true),
    _Case('int4 min', '(-2147483648)::int4', -2147483648, binary: true),
    _Case('int4 max', '2147483647::int4', 2147483647, binary: true),
    _Case('int8 min', '(-9223372036854775808)::int8', _int8Min, binary: true),
    _Case('int8 max', '9223372036854775807::int8', _int8Max, binary: true),
    _Case(r'int2 param', r'$1::int2', -32768, params: [-32768], binary: true),
    _Case(r'int8 params', r'$1::int8 + $2::int8', -1,
        params: [_int8Min, _int8Max], binary: true),
    _Case('int4 null param', r'$1::int4', null, params: [null], binary: true),
    _Case('oid', '4294967295::oid', 4294967295, binary: true),
    _Case('xid', "'123'::xid", 123, binary: true),
  ]);

  _cases('numeric as double', [
    _Case('numeric', '123456.789::numeric', 123456.789),
    _Case('numeric 0.1', '0.1::numeric', 0.1),
    _Case('numeric NaN', "'NaN'::numeric", isNaN),
    _Case('numeric Infinity', "'Infinity'::numeric", double.infinity),
    _Case('numeric -Infinity', "'-Infinity'::numeric", double.negativeInfinity),
    _Case('numeric param', r'$1::numeric', 1.5, params: [1.5]),
    _Case('numeric int param', r'$1::numeric', 12345678901234.0,
        params: [12345678901234]),
    _Case('numeric[]', "'{1.10,NULL,2}'::numeric[]", [1.1, null, 2.0]),
  ]);

  _cases(
      'numeric as string',
      [
        _Case(
            'numeric exact',
            '123456789012345678901234567890.123456789::numeric',
            '123456789012345678901234567890.123456789'),
        _Case('numeric keeps the scale', '1.10::numeric(10,2)', '1.10'),
        _Case('numeric NaN', "'NaN'::numeric", 'NaN'),
        _Case('numeric param', r'$1::numeric', '0.30', params: ['0.30']),
        _Case('numeric[]', "'{1.10,NULL,2}'::numeric[]", ['1.10', null, '2']),
      ],
      settings: () => _settings(numericAsString: true));

  _cases('floating point', [
    _Case('float8 0.1 + 0.2', '0.1::float8 + 0.2::float8', 0.1 + 0.2,
        binary: true),
    _Case('float8 pi', '3.141592653589793::float8', 3.141592653589793,
        binary: true),
    _Case('float8 max', '1.7976931348623157e308::float8', double.maxFinite,
        binary: true),
    _Case('float8 smallest normal', '2.2250738585072014e-308::float8',
        2.2250738585072014e-308,
        binary: true),
    _Case('float8 smallest subnormal', '5e-324::float8', double.minPositive,
        binary: true),
    _Case('float8 1e-7', '1e-7::float8', 1e-7, binary: true),
    _Case('float8 123456.789', '123456.789::float8', 123456.789, binary: true),
    _Case('float8 -0', "'-0'::float8", _negativeZero, binary: true),
    _Case('float8 NaN', "'NaN'::float8", isNaN, binary: true),
    _Case('float8 Infinity', "'Infinity'::float8", double.infinity,
        binary: true),
    _Case('float8 -Infinity', "'-Infinity'::float8", double.negativeInfinity,
        binary: true),
    _Case('float8 params', r'array[$1::float8, $2::float8, $3::float8]',
        [0.1 + 0.2, double.maxFinite, double.minPositive],
        params: [0.1 + 0.2, double.maxFinite, double.minPositive]),
    _Case('float8 NaN param', r'$1::float8', isNaN,
        params: [double.nan], binary: true),
    _Case('float8 -Infinity param', r'$1::float8', double.negativeInfinity,
        params: [double.negativeInfinity], binary: true),
    _Case('float4 max', '3.4028235e38::float4', _float4(3.4028235e38),
        binary: true),
    _Case('float4 smallest normal', '1.1754944e-38::float4',
        _float4(1.1754944e-38),
        binary: true),
    _Case('float4 0.1', '0.1::float4', _float4(0.1), binary: true),
    _Case('float4 param', r'$1::float4', _float4(2.7182817),
        params: [2.7182817], binary: true),
    _Case('float4 NaN', "'NaN'::float4", isNaN, binary: true),
    _Case('float4 -Infinity', "'-Infinity'::float4", double.negativeInfinity,
        binary: true),
  ]);

  _cases('bool, text, bytea, uuid', [
    _Case('bool true', 'true', true, binary: true),
    _Case('bool false param', r'$1::bool', false,
        params: [false], binary: true),
    _Case('bool null', 'null::bool', null, binary: true),
    _Case('text utf8', "'ação 日本語 😀 ''q'' \\ x'::text", "ação 日本語 😀 'q' \\ x",
        binary: true),
    _Case('text utf8 param', r'$1::text', 'ação 日本語 😀 "q" \\ \n\t',
        params: ['ação 日本語 😀 "q" \\ \n\t'], binary: true),
    _Case('text empty', "''::text", '', binary: true),
    _Case('text 100k', "repeat('ab', 50000)", 'ab' * 50000, binary: true),
    _Case('varchar', "'abc'::varchar(10)", 'abc', binary: true),
    _Case('bpchar is padded', "'ab'::char(4)", 'ab  ', binary: true),
    _Case('"char"', "'a'::\"char\"", 'a', binary: true),
    _Case('name', "'cov'::name", 'cov', binary: true),
    _Case('bytea', r"'\x00ff5c27'::bytea", _bytes([0, 255, 0x5c, 0x27]),
        binary: true),
    _Case('bytea empty', r"''::bytea", _bytes([]), binary: true),
    _Case('bytea param', r'$1::bytea', _bytes([0, 1, 92, 255]),
        params: [
          _bytes([0, 1, 92, 255])
        ],
        binary: true),
    _Case(
        'bytea 100k',
        r"decode(repeat('00ff', 50000), 'hex')",
        _bytes([
          for (var i = 0; i < 50000; i++) ...[0, 255]
        ]),
        binary: true),
    _Case('uuid is lower case', "'A0EEBC99-9C0B-4EF8-BB6D-6BB9BD380A11'::uuid",
        'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11',
        binary: true),
    _Case('uuid param', r'$1::uuid', 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11',
        params: ['A0EEBC99-9C0B-4EF8-BB6D-6BB9BD380A11'], binary: true),
  ]);

  _cases('json and jsonb', [
    for (final type in ['json', 'jsonb']) ...[
      _Case(
          '$type object',
          '\'{"a": [1, 2.5, {"b": null}], "c": "ç"}\'::$type',
          {
            'a': [
              1,
              2.5,
              {'b': null}
            ],
            'c': 'ç'
          },
          binary: true),
      _Case('$type array', "'[1, \"x\"]'::$type", [1, 'x'], binary: true),
      _Case('$type number', "'5'::$type", 5, binary: true),
      _Case('$type string', "'\"s\"'::$type", 's', binary: true),
      _Case('$type null is JSON null', "'null'::$type", null, binary: true),
      _Case(
          '$type Map param',
          '\$1::$type',
          {
            'k': [1, 'x', true]
          },
          params: [
            {
              'k': [1, 'x', true]
            }
          ],
          binary: true),
      _Case('$type encoded list param', '\$1::$type', [1, 2],
          params: [
            jsonEncode([1, 2])
          ],
          binary: true),
      _Case('$type[]', "array['{\"a\": 1}', '[1, 2]', '5', 'null']::$type[]", [
        {'a': 1},
        [1, 2],
        5,
        null
      ]),
    ],
  ]);

  _cases('date and time (UTC session)', [
    _Case('date', "'2024-02-29'::date", DateTime.utc(2024, 2, 29),
        binary: true),
    _Case('date BC', "'0044-03-15 BC'::date", DateTime.utc(-43, 3, 15),
        binary: true),
    _Case('date infinity is null', "'infinity'::date", null, binary: true),
    _Case('date param', r'$1::date', DateTime.utc(2024, 2, 29),
        params: [DateTime.utc(2024, 2, 29)], binary: true),
    _Case('date BC param', r'$1::date', DateTime.utc(-43, 3, 15),
        params: [DateTime.utc(-43, 3, 15)], binary: true),
    _Case('date year 0 param (1 BC)', r'$1::date', DateTime.utc(0, 1, 1),
        params: [DateTime.utc(0, 1, 1)], binary: true),
    _Case('date year 10000 param', r'$1::date', DateTime.utc(10000, 1, 2),
        params: [DateTime.utc(10000, 1, 2)], binary: true),
    _Case('timestamp micro', "'2026-10-19 14:30:15.123456'::timestamp",
        DateTime.utc(2026, 10, 19, 14, 30, 15, 123, 456),
        binary: true),
    _Case(
        'timestamp BC', "'0001-01-01 00:00:00 BC'::timestamp", DateTime.utc(0),
        binary: true),
    _Case('timestamp year 10000', "'10000-01-01 01:02:03'::timestamp",
        DateTime.utc(10000, 1, 1, 1, 2, 3),
        binary: true),
    _Case('timestamp -infinity is null', "'-infinity'::timestamp", null,
        binary: true),
    _Case('timestamp param', r'$1::timestamp',
        DateTime.utc(2026, 10, 19, 14, 30, 15, 123, 456),
        params: [DateTime.utc(2026, 10, 19, 14, 30, 15, 123, 456)],
        binary: true),
    _Case('timestamp BC param', r'$1::timestamp',
        DateTime.utc(-99, 12, 31, 23, 59, 59),
        params: [DateTime.utc(-99, 12, 31, 23, 59, 59)], binary: true),
    _Case('timestamptz offset', "'2024-07-12 15:00:00-03'::timestamptz",
        DateTime.utc(2024, 7, 12, 18),
        binary: true),
    _Case('timestamptz infinity is null', "'infinity'::timestamptz", null,
        binary: true),
    _Case('timestamptz local param keeps the instant', r'$1::timestamptz',
        DateTime.utc(2024, 7, 12, 18, 0, 0, 1),
        params: [DateTime.utc(2024, 7, 12, 18, 0, 0, 1).toLocal()],
        binary: true),
    _Case('timestamptz BC param', r'$1::timestamptz', DateTime.utc(-43, 3, 15),
        params: [DateTime.utc(-43, 3, 15)], binary: true),
    _Case('time', "'10:11:12.5'::time", '10:11:12.5'),
    _Case('timetz', "'10:11:12+03'::timetz", '10:11:12+03'),
    _Case('interval', "'1 year 2 mons 3 days 04:05:06.7'::interval",
        '1 year 2 mons 3 days 04:05:06.7'),
    _Case('time param', r'$1::time', '23:59:59.999999',
        params: ['23:59:59.999999']),
    _Case('interval param', r'$1::interval', '-1 days -00:00:01',
        params: ['-1 day -1 second']),
  ]);

  _cases('network and enum', [
    _Case('inet', "'192.168.0.1/24'::inet", '192.168.0.1/24'),
    _Case('inet v6', "'::1'::inet", '::1'),
    _Case('cidr', "'10.0.0.0/8'::cidr", '10.0.0.0/8'),
    _Case('inet param', r'$1::inet', '10.1.2.3', params: ['10.1.2.3']),
    _Case('inet[]', "'{10.0.0.1,NULL}'::inet[]", ['10.0.0.1', null]),
    _Case('cidr[]', "'{10.0.0.0/8}'::cidr[]", ['10.0.0.0/8']),
    _Case('enum', "'ok'::cov_mood", 'ok'),
    _Case('enum param', r'$1::cov_mood', 'happy', params: ['happy']),
  ]);

  _cases('arrays', [
    _Case('int2[]', "'{1,NULL,-32768}'::int2[]", [1, null, -32768]),
    _Case('int4[] param', r'$1::int4[]', [
      1,
      null,
      3
    ], params: [
      [1, null, 3]
    ]),
    _Case('int8[] param', r'$1::int8[]', [
      _int8Min,
      _int8Max
    ], params: [
      [_int8Min, _int8Max]
    ]),
    _Case('empty int4[]', "'{}'::int4[]", []),
    _Case('int4[] with explicit bounds', "'[0:1]={1,2}'::int4[]", [1, 2]),
    _Case(
        'text[][] with explicit bounds',
        r"""'[2:3][1:1]={{a},{"b,c"}}'::text[]""",
        [
          ['a'],
          ['b,c']
        ]),
    _Case('text[] param keeps special strings', r'$1::text[]', [
      'null',
      'NULL',
      'Null',
      'a b',
      'x"y',
      r'back\slash',
      '',
      '{}',
      ',',
      null,
      'ação 😀'
    ], params: [
      [
        'null',
        'NULL',
        'Null',
        'a b',
        'x"y',
        r'back\slash',
        '',
        '{}',
        ',',
        null,
        'ação 😀'
      ]
    ]),
    _Case('varchar[]', "'{a,\"b c\",NULL}'::varchar[]", ['a', 'b c', null]),
    _Case('bool[]', "'{t,f,NULL}'::bool[]", [true, false, null]),
    _Case('float8[] param with NaN and infinities', r'$1::float8[]', [
      1.5,
      isNaN,
      double.infinity,
      double.negativeInfinity,
      null
    ], params: [
      [1.5, double.nan, double.infinity, double.negativeInfinity, null]
    ]),
    _Case('float4[]', "'{1.5,NaN}'::float4[]", [1.5, isNaN]),
    _Case('bytea[] param', r'$1::bytea[]', [
      _bytes([1, 2, 255]),
      null,
      _bytes([])
    ], params: [
      [
        _bytes([1, 2, 255]),
        null,
        _bytes([])
      ]
    ]),
    _Case('uuid[]', "'{a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11,NULL}'::uuid[]",
        ['a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11', null]),
    _Case('date[]', "'{2024-01-01,NULL,infinity}'::date[]",
        [DateTime.utc(2024), null, null]),
    _Case('timestamp[] param', r'$1::timestamp[]', [
      DateTime.utc(2024, 1, 2, 3, 4, 5, 6),
      null
    ], params: [
      [DateTime.utc(2024, 1, 2, 3, 4, 5, 6), null]
    ]),
    _Case('timestamptz[] param', r'$1::timestamptz[]', [
      DateTime.utc(2024, 1, 2, 3, 4, 5)
    ], params: [
      [DateTime.utc(2024, 1, 2, 3, 4, 5).toLocal()]
    ]),
    _Case('timestamp[] BC param', r'$1::timestamp[]', [
      DateTime.utc(-43, 3, 15, 10),
      DateTime.utc(0)
    ], params: [
      [DateTime.utc(-43, 3, 15, 10), DateTime.utc(0)]
    ]),
    _Case('float4[] elements are the float4 value',
        "'{0.1,NULL}'::float4[]", [_f32(0.1), null]),
    _Case('bytea[][]', r"""'{{"\\x01"},{"\\x02ff"}}'::bytea[]""", [
      [
        _bytes([1])
      ],
      [
        _bytes([2, 255])
      ]
    ]),
    _Case('jsonb[][] with array elements',
        "array[array['[1]'::jsonb], array['{\"a\": []}'::jsonb]]", [
      [
        [1]
      ],
      [
        {'a': []}
      ]
    ]),
    _Case('time[]', "'{10:00,NULL}'::time[]", ['10:00:00', null]),
    _Case('interval[]', "'{1 day}'::interval[]", ['1 day']),
    _Case('int4[][]', "'{{1,2},{3,NULL}}'::int4[]", [
      [1, 2],
      [3, null]
    ]),
    _Case('int4[][] param', r'$1::int4[]', [
      [1, 2],
      [3, 4]
    ], params: [
      [
        [1, 2],
        [3, 4]
      ]
    ]),
    _Case('text[][]', "'{{a,b},{c,\"d e\"}}'::text[]", [
      ['a', 'b'],
      ['c', 'd e']
    ]),
    _Case('int4[][][]', "'{{{1}},{{2}}}'::int4[]", [
      [
        [1]
      ],
      [
        [2]
      ]
    ]),
    _Case('float8[][]', "'{{1.5},{NaN}}'::float8[]", [
      [1.5],
      [isNaN]
    ]),
  ]);

  _cases(
      'time zones: America/Sao_Paulo session, UTC materialization',
      [
        _Case('timestamptz', "'2024-07-12 15:00:00+00'::timestamptz",
            DateTime.utc(2024, 7, 12, 15),
            binary: true),
        _Case(
            'timestamptz before 1914 (LMT offset)',
            "'1900-01-01 12:00:00+00'::timestamptz",
            DateTime.utc(1900, 1, 1, 12),
            binary: true),
        _Case('timestamptz UTC param', r'$1::timestamptz',
            DateTime.utc(2024, 1, 15, 12),
            params: [DateTime.utc(2024, 1, 15, 12)], binary: true),
        _Case('timestamp is not shifted', "'2018-11-04 00:00:00'::timestamp",
            DateTime.utc(2018, 11, 4),
            binary: true),
        _Case(
            'timestamptz rendered by the session',
            "'2024-07-12 15:00:00+00'::timestamptz::text",
            '2024-07-12 12:00:00-03',
            binary: true),
      ],
      settings: () =>
          _settings(timeZone: const TimeZoneSettings('America/Sao_Paulo')));

  _cases(
      'time zones: IANA materialization',
      [
        _Case(
            'timestamptz offset',
            "'2024-07-12 15:00:00+00'::timestamptz",
            isA<DateTime>()
                .having((d) => d.toUtc(), 'utc', DateTime.utc(2024, 7, 12, 15))
                .having((d) => d.timeZoneOffset, 'offset',
                    const Duration(hours: -3)),
            binary: true),
        _Case(
            'timestamptz DST of 2000',
            "'2000-01-15 12:00:00+00'::timestamptz",
            isA<DateTime>()
                .having((d) => d.toUtc(), 'utc', DateTime.utc(2000, 1, 15, 12))
                .having((d) => d.timeZoneOffset, 'offset',
                    const Duration(hours: -2)),
            binary: true),
      ],
      settings: () => _settings(
          timeZone: const TimeZoneSettings('America/Sao_Paulo',
              forceDecodeTimestamptzAsUTC: false,
              useIanaTimeZoneDatabase: true)));

  _cases(
      'time zones: local materialization of date and timestamp',
      [
        _Case('date', "'2024-02-29'::date", DateTime(2024, 2, 29),
            binary: true),
        _Case('timestamp', "'2024-02-29 13:14:15.5'::timestamp",
            DateTime(2024, 2, 29, 13, 14, 15, 500),
            binary: true),
      ],
      settings: () => _settings(
          timeZone: const TimeZoneSettings('UTC',
              forceDecodeDateAsUTC: false, forceDecodeTimestampAsUTC: false)));

  _cases(
      'latin1 text charset',
      [
        _Case('text', "'ação Ñ'::text", 'ação Ñ', binary: true),
        _Case('text param', r'$1::text', 'çãé ÿ',
            params: ['çãé ÿ'], binary: true),
        _Case('text[] param', r'$1::text[]', [
          'ç',
          'ã é'
        ], params: [
          ['ç', 'ã é']
        ]),
      ],
      settings: () => _settings(textCharset: 'latin1'));

  _cases(
      'win1252 text charset',
      [
        _Case('text', "'€ ação “x”'::text", '€ ação “x”', binary: true),
        _Case('text param', r'$1::text', '€ ŠŽ',
            params: ['€ ŠŽ'], binary: true),
      ],
      settings: () => _settings(textCharset: 'win1252'));

  group('charset failures leave the connection usable', () {
    test('latin1: a character the client cannot encode', () async {
      final c = CoreConnection.fromSettings(_settings(textCharset: 'latin1'));
      await c.connect();
      addTearDown(c.close);
      await expectLater(
          c.queryNamed(r'select $1::text', ['日本']), throwsA(anything));
      await expectLater(
          c.queryNamed("select '日本'::text", const []), throwsA(anything));
      await expectLater(c.execute("select '日本'::text"), throwsA(anything));
      expect((await c.queryNamed('select 1::int4', const [])).single[0], 1);
      expect(await c.execute('select 1'), 1);
    });

    test('latin1: a server value without a latin1 equivalent (22P05)',
        () async {
      final c = CoreConnection.fromSettings(_settings(textCharset: 'latin1'));
      await c.connect();
      addTearDown(c.close);
      for (var i = 0; i < 2; i++) {
        await expectLater(
            c.queryNamed('select chr(26085)::text', const []),
            throwsA(isA<PostgresqlException>()
                .having((e) => e.serverErrorCode, 'SQLSTATE', '22P05')));
      }
      expect((await c.queryNamed('select 1::int4', const [])).single[0], 1);
    });
  });

  group('ascii text charset with non-ASCII server text', () {
    // The server keeps its encoding (no ascii client_encoding): a non-ASCII
    // NOTICE, as every localized one is, closed the connection.
    late CoreConnection c;
    final notices = <String>[];
    setUpAll(() async {
      c = CoreConnection.fromSettings(_settings(textCharset: 'ascii'));
      await c.connect();
      c.notices.listen((n) => notices.add('$n'));
    });
    tearDownAll(() => c.close());

    Future<void> next() async =>
        expect((await c.queryNamed('select 1::int4', const [])).single[0], 1);

    test('NOTICE', () async {
      await c.execute(r"do $$ begin raise notice 'n%', chr(231); end $$");
      await next();
      await Future<void>.delayed(Duration.zero);
      expect(notices, contains(contains('nç')));
    });

    test('ERROR', () async {
      await expectLater(
          c.execute(r"do $$ begin raise exception 'e%', chr(231); end $$"),
          throwsA(isA<PostgresqlException>()
              .having((e) => e.message, 'message', 'eç')));
      await next();
    });

    test('notification payload', () async {
      final payload = c.notifications.first;
      await c.execute('listen cov_ascii');
      await c.execute("select pg_notify('cov_ascii', 'p' || chr(231))");
      expect(
          ((await payload.timeout(const Duration(seconds: 5)))
              as Map)['payload'],
          'pç');
      await c.execute('unlisten cov_ascii');
      await next();
    });

    test('ParameterStatus', () async {
      await c.execute(
          "select set_config('application_name', 'a' || chr(231), false)");
      // PostgreSQL escapes it (a\xc3\xa7); the connection must survive.
      expect(c.serverInfo.rawParams['application_name'], startsWith('a'));
      await next();
    });

    test('a non-ASCII value fails only its query', () async {
      await expectLater(
          c.queryNamed('select chr(231)', const []), throwsFormatException);
      await expectLater(
          c.querySimple('select chr(231)'), throwsFormatException);
      await next();
    });
  });

  group('infinity with throwOnDateTimeInfinity', () {
    late CoreConnection c;
    setUpAll(() async {
      c = CoreConnection.fromSettings(_settings(
          timeZone:
              const TimeZoneSettings('UTC', throwOnDateTimeInfinity: true)));
      await c.connect();
    });
    tearDownAll(() => c.close());

    for (final expr in [
      "'infinity'::date",
      "'-infinity'::timestamp",
      "'infinity'::timestamptz"
    ]) {
      test(expr, () async {
        final sql = 'select $expr as v';
        for (var i = 0; i < 2; i++) {
          await expectLater(c.queryNamed(sql, const []), throwsFormatException);
        }
        await expectLater(c.querySimple(sql), throwsFormatException);
        await expectLater(c.queryMaps(sql, requireBinaryResults: true),
            throwsFormatException);
        expect((await c.queryNamed('select 1::int4', const [])).single[0], 1);
      });
    }
  });

  group('float4 text and binary agree', () {
    // Text (the shortest decimal, '0.1') is read as a float4 and widened:
    // the same double as the binary format. It used to be 0.1 cold and
    // 0.10000000149011612 warm.
    test('cold, simple and warm/strict results', () async {
      final c = CoreConnection.fromSettings(_settings());
      await c.connect();
      addTearDown(c.close);
      const sql = 'select 0.1::float4 as v';
      expect((await c.querySimple(sql)).single[0], _f32(0.1));
      expect((await c.queryNamed(sql, const [])).single[0], _f32(0.1));
      expect((await c.queryNamed(sql, const [])).single[0], _f32(0.1));
      expect((await c.queryMaps(sql, requireBinaryResults: true)).single['v'],
          _f32(0.1));
    });
  });

  group('every type in one row', () {
    test('text, warm and strict decoders agree column by column', () async {
      final c = CoreConnection.fromSettings(_settings());
      await c.connect();
      addTearDown(c.close);
      const sql = "select 1::int2 a, 2::int4 b, 3::int8 c, 1.5::float4 d, "
          "2.5::float8 e, true f, 'x'::text g, '\\x01'::bytea h, "
          "'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11'::uuid i, '{}'::jsonb j, "
          "'2024-01-01'::date k, '2024-01-01 01:02:03'::timestamp l, "
          "'2024-01-01 01:02:03+00'::timestamptz m, 1.25::numeric n, "
          "'01:02'::time o, '{1,2}'::int4[] p, null::text q";
      final cold = (await c.queryMaps(sql)).single;
      final warm = (await c.queryMaps(sql)).single;
      expect(warm, cold);
      expect(cold['n'], 1.25);
      expect(cold['o'], '01:02:00');
      expect(cold['p'], [1, 2]);
      expect(cold['q'], isNull);
      expect(cold['h'], [1]);
    });
  });
}
