import 'dart:typed_data';

import 'package:dargres/src/converters.dart';
import 'package:dargres/src/server_info.dart';
import 'package:dargres/src/timezone_settings.dart';
import 'package:test/test.dart';

void main() {
  late TypeConverter typeConverter;

  setUp(() async {
    typeConverter =
        TypeConverter('utf8', ServerInfo(timeZone: TimeZoneSettings('UTC')));
  });

  group('TypeConverter', () {
    test('test_date_in', () {
      expect(typeConverter.date_in('2022-03-02'), equals(DateTime.parse('2022-03-02 00:00:00.000Z')));
    });

    test('test_null_out', () {
      expect(typeConverter.null_out('null'), equals(null));
    });

    test('test_array_out bool', () {
      expect(typeConverter.array_out([true, false, null]),
          equals("{true,false,NULL}"));
    });

    test('test_array_out DateTime', () {
      expect(typeConverter.array_out([DateTime(2022, 3, 2)]),
          equals("{2022-03-02T00:00:00.000}"));
    });

    test('test_array_out bytes (Uint8List)', () {
      expect(
          typeConverter.array_out(
              [Uint8List.fromList("\x00\x01\x02\x03\x02\x01\x00".codeUnits)]),
          equals('{"\\\\x00010203020100"}'));
    });

    test('test_array_out List<int>', () {
      expect(typeConverter.array_out([1, 2, 3]), equals("{1,2,3}"));
    });

    test('test_array_out List<int> multidimensional', () {
      expect(
          typeConverter.array_out([
            [1, 2],
            [3, 4]
          ]),
          equals("{{1,2},{3,4}}"));
    });

    test('test_array_out int2[] with null', () {
      expect(typeConverter.array_out([1, null, 3]), equals("{1,NULL,3}"));
    });

    test('test_array_out int4[]', () {
      expect(typeConverter.array_out([7000000000, 2, 3]),
          equals("{7000000000,2,3}"));
    });

    test('test_array_out float8[]', () {
      expect(typeConverter.array_out([1.1, 2.2, 3.3]), equals("{1.1,2.2,3.3}"));
    });

    test('test_array_out float8[]', () {
      expect(typeConverter.array_out(["Veni", "vidi", "vici"]),
          equals("{Veni,vidi,vici}"));
    });

    test('test_numeric_out float', () {
      expect(typeConverter.numeric_out(1.1), equals("1.1"));
    });

    test('test_string_out', () {
      expect(typeConverter.string_out("hello \u0173 world"),
          equals("hello \u0173 world"));
    });

    test('test_string_in', () {
      expect(typeConverter.string_in("hello \u0173 world"),
          equals("hello \u0173 world"));
    });

    test('test_array_string_escape', () {
      expect(typeConverter.array_string_escape('"'), equals('"\\""'));
    });

    test('test_array_string_escape', () {
      expect(typeConverter.array_string_escape("\r"), equals('"\r"'));
    });

    test('test_timestamptz_in', () {
      //+01:30
      expect(typeConverter.timestamptz_in("2022-10-08 15:01:39+00:00"),
          equals(DateTime.parse("2022-10-08 15:01:39+00:00")));
    });
  });
}
