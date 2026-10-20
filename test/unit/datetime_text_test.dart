import 'package:dargres/src/converters.dart';
import 'package:dargres/src/server_info.dart';
import 'package:dargres/src/timezone_settings.dart';
import 'package:dargres/src/to_statement.dart';
import 'package:test/test.dart';

void main() {
  TypeConverter converter([TimeZoneSettings? settings]) => TypeConverter(
      'utf8', ServerInfo(timeZone: settings ?? const TimeZoneSettings.utc()));

  group('date/time text decoding is independent of the OS time zone', () {
    test('timestamp at midnight of a Brazilian DST start keeps 00:00', () {
      // 00:00 did not exist locally on these days in America/Sao_Paulo; a
      // local DateTime parse moved them to 01:00.
      for (final day in ['2003-11-04', '2017-10-15', '2018-11-04']) {
        final value = converter().timestampIn('$day 00:00:00')!;
        final parts = day.split('-').map(int.parse).toList();
        expect(value, DateTime.utc(parts[0], parts[1], parts[2]), reason: day);
      }
    });

    test('timestamp keeps microseconds and five-digit years', () {
      expect(converter().timestampIn('2026-10-19 14:30:15.123456'),
          DateTime.utc(2026, 10, 19, 14, 30, 15, 0, 123456));
      expect(converter().timestampIn('2026-10-19 14:30:15.5'),
          DateTime.utc(2026, 10, 19, 14, 30, 15, 500));
      expect(converter().timestampIn('10000-01-01 00:00:00'),
          DateTime.utc(10000));
    });

    test('BC dates use astronomical years like the binary decoder', () {
      expect(converter().dateIn('0001-01-01 BC'), DateTime.utc(0));
      expect(converter().dateIn('0044-03-15 BC'), DateTime.utc(-43, 3, 15));
      expect(converter().timestampIn('0044-03-15 12:00:00 BC'),
          DateTime.utc(-43, 3, 15, 12));
    });

    test('timestamptz accepts offsets with minutes and seconds', () {
      expect(converter().timestampTzIn('2026-10-19 14:30:15.123456-03'),
          DateTime.utc(2026, 10, 19, 17, 30, 15, 0, 123456));
      expect(converter().timestampTzIn('2026-10-19 14:30:15+05:30'),
          DateTime.utc(2026, 10, 19, 9, 0, 15));
      // Local mean time of America/Sao_Paulo before 1914.
      expect(converter().timestampTzIn('1900-01-01 00:00:00-03:06:28'),
          DateTime.utc(1900, 1, 1, 3, 6, 28));
      expect(converter().timestampTzIn('0044-03-15 12:00:00+00 BC'),
          DateTime.utc(-43, 3, 15, 12));
    });

    test('local materialization keeps the civil components', () {
      const local = TimeZoneSettings('UTC',
          forceDecodeTimestampAsUTC: false, forceDecodeDateAsUTC: false);
      expect(converter(local).timestampIn('2026-10-19 14:30:15'),
          DateTime(2026, 10, 19, 14, 30, 15));
      expect(converter(local).dateIn('2026-10-19'), DateTime(2026, 10, 19));
    });

    test('malformed and infinite values decode as null', () {
      expect(converter().timestampIn('19/10/2026 14:30'), isNull);
      expect(converter().dateIn('2026-13-01'), isNull);
      expect(converter().timestampIn('infinity'), isNull);
      expect(converter().dateIn('-infinity'), isNull);
    });

    test('date arrays use the same decoder', () {
      expect(converter().dateArrayIn('{2026-01-01,"0001-01-01 BC",NULL}'),
          <DateTime?>[DateTime.utc(2026), DateTime.utc(0), null]);
    });
  });

  group('numericAsString', () {
    TypeConverter numericConverter(bool asString) => TypeConverter(
        'utf8', ServerInfo(timeZone: const TimeZoneSettings.utc()),
        numericAsString: asString);

    test('keeps the exact server text when enabled', () {
      expect(numericConverter(true).decodeValuePg8000(
              '12345678901234567.89', TypeConverter.numeric),
          '12345678901234567.89');
      expect(
          numericConverter(true)
              .decodeValuePg8000('{1.10,NULL}', TypeConverter.numericArray),
          <String?>['1.10', null]);
    });

    test('defaults to double', () {
      expect(numericConverter(false).decodeValuePg8000('1.10', TypeConverter.numeric),
          1.1);
    });
  });

  group('placeholders and backslashes', () {
    test('a backslash ends a standard-conforming literal', () {
      expect(toStatement2(r"select 'C:\' caminho, ? p"),
          r"select 'C:\' caminho, $1 p");
    });

    test('E-strings still treat backslash as an escape', () {
      expect(toStatement2(r"select E'it\'s ?', ? p"), r"select E'it\'s ?', $1 p");
      expect(toStatement2(r"select e'\\', ? p"), r"select e'\\', $1 p");
    });

    test('an identifier ending in e is not an E-string prefix', () {
      expect(toStatement2(r"select name'\' , ? p"), r"select name'\' , $1 p");
    });

    test('non-standard strings keep the legacy backslash escape', () {
      expect(
          toStatement2(r"select 'it\'s ?', ? p",
              standardConformingStrings: false),
          r"select 'it\'s ?', $1 p");
    });
  });

  group('DateTime parameters carry their zone', () {
    test('UTC values end with Z', () {
      expect(converter().dateTimeOut(DateTime.utc(2024, 3, 10, 12, 34, 56, 789, 123)),
          '2024-03-10T12:34:56.789123Z');
    });

    test('local values carry their offset (it was left out)', () {
      final value = _FixedOffsetDateTime(
          DateTime.utc(2024, 3, 10, 15, 34, 56, 7), const Duration(hours: -3));
      expect(converter().dateTimeOut(value), '2024-03-10T12:34:56.007-03:00');
      final halfHour = _FixedOffsetDateTime(
          DateTime.utc(2024, 1, 1, 12), const Duration(minutes: -30));
      expect(converter().dateTimeOut(halfHour), '2024-01-01T11:30:00.000-00:30');
    });
  });
}

/// A local DateTime with a chosen offset (the platform zone may be anything).
class _FixedOffsetDateTime implements DateTime {
  _FixedOffsetDateTime(DateTime utc, this.timeZoneOffset)
      : _local = utc.add(timeZoneOffset);

  final DateTime _local;
  @override
  final Duration timeZoneOffset;

  @override
  bool get isUtc => false;
  @override
  int get year => _local.year;
  @override
  int get month => _local.month;
  @override
  int get day => _local.day;
  @override
  int get hour => _local.hour;
  @override
  int get minute => _local.minute;
  @override
  int get second => _local.second;
  @override
  int get millisecond => _local.millisecond;
  @override
  int get microsecond => _local.microsecond;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
