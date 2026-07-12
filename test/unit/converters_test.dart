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
      expect(typeConverter.dateIn('2022-03-02'), equals(DateTime.parse('2022-03-02 00:00:00.000Z')));
    });

    test('test_null_out', () {
      expect(typeConverter.nullOut('null'), equals(null));
    });

    test('test_array_out bool', () {
      expect(typeConverter.arrayOut([true, false, null]),
          equals("{true,false,NULL}"));
    });

    test('test_array_out DateTime', () {
      expect(typeConverter.arrayOut([DateTime(2022, 3, 2)]),
          equals("{2022-03-02T00:00:00.000}"));
    });

    test('test_array_out bytes (Uint8List)', () {
      expect(
          typeConverter.arrayOut(
              [Uint8List.fromList("\x00\x01\x02\x03\x02\x01\x00".codeUnits)]),
          equals('{"\\\\x00010203020100"}'));
    });

    test('test_array_out List<int>', () {
      expect(typeConverter.arrayOut([1, 2, 3]), equals("{1,2,3}"));
    });

    test('test_array_out List<int> multidimensional', () {
      expect(
          typeConverter.arrayOut([
            [1, 2],
            [3, 4]
          ]),
          equals("{{1,2},{3,4}}"));
    });

    test('test_array_out int2[] with null', () {
      expect(typeConverter.arrayOut([1, null, 3]), equals("{1,NULL,3}"));
    });

    test('test_array_out int4[]', () {
      expect(typeConverter.arrayOut([7000000000, 2, 3]),
          equals("{7000000000,2,3}"));
    });

    test('test_array_out float8[]', () {
      expect(typeConverter.arrayOut([1.1, 2.2, 3.3]), equals("{1.1,2.2,3.3}"));
    });

    test('test_array_out float8[]', () {
      expect(typeConverter.arrayOut(["Veni", "vidi", "vici"]),
          equals("{Veni,vidi,vici}"));
    });

    test('test_numeric_out float', () {
      expect(typeConverter.numericOut(1.1), equals("1.1"));
    });

    test('test_string_out', () {
      expect(typeConverter.stringOut("hello \u0173 world"),
          equals("hello \u0173 world"));
    });

    test('test_string_in', () {
      expect(typeConverter.stringIn("hello \u0173 world"),
          equals("hello \u0173 world"));
    });

    test('test_array_string_escape', () {
      expect(typeConverter.arrayStringEscape('"'), equals('"\\""'));
    });

    test('test_array_string_escape', () {
      expect(typeConverter.arrayStringEscape("\r"), equals('"\r"'));
    });

    test('test_timestamptz_in', () {
      //+01:30
      expect(typeConverter.timestampTzIn("2022-10-08 15:01:39+00:00"),
          equals(DateTime.parse("2022-10-08 15:01:39+00:00")));
    });

    test('Windows-1252 encodes and decodes its non-Latin-1 characters', () {
      const bytes = <int>[
        0x80, 0x82, 0x83, 0x84, 0x85, 0x86, 0x87, 0x88, 0x89,
        0x8a, 0x8b, 0x8c, 0x8e, 0x91, 0x92, 0x93, 0x94, 0x95,
        0x96, 0x97, 0x98, 0x99, 0x9a, 0x9b, 0x9c, 0x9e, 0x9f,
      ];
      const text =
          '€‚ƒ„…†‡ˆ‰Š‹ŒŽ'
          '‘’“”•–—˜™š›œžŸ';

      expect(typeConverter.charsetDecode(bytes, 'win1252'), text);
      expect(typeConverter.charsetEncode(text, 'win1252'), bytes);
    });

    test('Windows-1252 preserves ASCII and its direct Latin-1 block', () {
      const text = 'Dargres - Olá, ação! £ÿ';
      final bytes = typeConverter.charsetEncode(text, 'win1252');
      expect(typeConverter.charsetDecode(bytes, 'win1252'), text);
    });

    test('Windows-1252 rejects undefined bytes and unsupported characters', () {
      expect(() => typeConverter.charsetDecode(<int>[0x81], 'win1252'),
          throwsFormatException);
      expect(() => typeConverter.charsetDecode(<int>[256], 'win1252'),
          throwsFormatException);
      expect(() => typeConverter.charsetEncode('Ā', 'win1252'),
          throwsFormatException);
    });
  });
}
