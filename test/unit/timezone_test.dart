import 'dart:typed_data';

import 'package:dargres/src/column_description.dart';
import 'package:dargres/src/converters.dart';
import 'package:dargres/src/fast/result_schema.dart';
import 'package:dargres/src/server_info.dart';
import 'package:dargres/src/timezone_settings.dart';
import 'package:dargres/src/utils/pg_timezone/pg_timezone.dart';
import 'package:test/test.dart';

void main() {
  TypeConverter converter(TimeZoneSettings settings) =>
      TypeConverter('utf8', ServerInfo(timeZone: settings));

  const saoPaulo = TimeZoneSettings(
    'America/Sao_Paulo',
    forceDecodeTimestamptzAsUTC: false,
    useIanaTimeZoneDatabase: true,
  );

  group('timezone configuration', () {
    test('UTC configuration is const and remains the default fast path', () {
      const settings = TimeZoneSettings.utc();
      final value = converter(settings)
          .timestampTzIn('2024-07-12 15:00:00+00:00');

      expect(settings.useIanaTimeZoneDatabase, isFalse);
      expect(value, DateTime.utc(2024, 7, 12, 15));
      expect(value, isNot(isA<TZDateTime>()));
    });

    test('scope parser accepts full and compact names', () {
      expect(parsePgTimeZoneDatabaseScope('latest_all'),
          PgTimeZoneDatabaseScope.latestAll);
      expect(parsePgTimeZoneDatabaseScope('compact'),
          PgTimeZoneDatabaseScope.latest10y);
      expect(pgTimeZoneDatabaseScopeName(PgTimeZoneDatabaseScope.latest10y),
          'latest_10y');
    });
  });

  group('historical IANA timestamptz conversion', () {
    test('America/Sao_Paulo uses -03 in 2024', () {
      final value = converter(saoPaulo)
          .timestampTzIn('2024-07-12 15:00:00+00:00');

      expect(value, isA<TZDateTime>());
      expect(value!.toUtc(), DateTime.utc(2024, 7, 12, 15));
      expect(value.timeZoneOffset, const Duration(hours: -3));
      expect(value.hour, 12);
    });

    test('America/Sao_Paulo uses historical DST -02 in January 2000', () {
      final value = converter(saoPaulo)
          .timestampTzIn('2000-01-15 12:00:00+00:00');

      expect(value, isA<TZDateTime>());
      expect(value!.toUtc(), DateTime.utc(2000, 1, 15, 12));
      expect(value.timeZoneOffset, const Duration(hours: -2));
      expect(value.hour, 10);
    });

    test('compact database decodes recent instants', () {
      const compact = TimeZoneSettings(
        'America/Sao_Paulo',
        forceDecodeTimestamptzAsUTC: false,
        useIanaTimeZoneDatabase: true,
        ianaTimeZoneDatabaseScope: PgTimeZoneDatabaseScope.latest10y,
      );
      final value = converter(compact)
          .timestampTzIn('2024-07-12 15:00:00+00:00');

      expect(value, isA<TZDateTime>());
      expect(value!.timeZoneOffset, const Duration(hours: -3));
      expect(value.hour, 12);
    });

    test('binary fast decoder uses the same instant-specific transition', () {
      final schema = ResultSchema.fromColumns(
        <ColumnDescription>[
          ColumnDescription(0, 'at', 0, 0, 1184, 8, -1, 1),
        ],
        converter(saoPaulo),
      );
      final instant = DateTime.utc(2000, 1, 15, 12);
      const pgEpoch = 946684800000000;
      final bytes = ByteData(8)
        ..setInt64(
            0, instant.microsecondsSinceEpoch - pgEpoch, Endian.big);
      final value = schema.decodeColumn(0, bytes.buffer.asUint8List(), 0, 8);

      expect(value, isA<TZDateTime>());
      expect((value as DateTime).timeZoneOffset, const Duration(hours: -2));
      expect(value.hour, 10);
    });
  });

  group('PostgreSQL infinity', () {
    test('returns null by default for text date/time values', () {
      final utc = converter(const TimeZoneSettings.utc());
      expect(utc.dateIn('infinity'), isNull);
      expect(utc.timestampIn('-infinity'), isNull);
      expect(utc.timestampTzIn('infinity'), isNull);
    });

    test('throws when configured for text and binary values', () {
      const strict = TimeZoneSettings(
        'UTC',
        throwOnDateTimeInfinity: true,
      );
      final strictConverter = converter(strict);
      expect(() => strictConverter.timestampTzIn('infinity'),
          throwsFormatException);

      final schema = ResultSchema.fromColumns(
        <ColumnDescription>[
          ColumnDescription(0, 'at', 0, 0, 1184, 8, -1, 1),
        ],
        strictConverter,
      );
      final bytes = ByteData(8)..setInt64(0, 9223372036854775807);
      expect(
        () => schema.decodeColumn(0, bytes.buffer.asUint8List(), 0, 8),
        throwsFormatException,
      );
    });
  });
}
