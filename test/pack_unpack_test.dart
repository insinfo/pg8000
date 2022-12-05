import 'package:pg8000/src/pack_unpack.dart';
import 'package:test/test.dart';

void main() {
  //TypeConverter typeConverter;

  setUp(() async {
    //typeConverter = TypeConverter('utf8', null);
  });

  group('pack_unpack', () {
    test('i_pack_fast write Int32', () {
      expect(i_pack_fast(21474830), equals([1, 71, 174, 14]));
    });

    test('i_unpack_fast read Int32', () {
      expect(i_unpack_fast([0, 0, 0, 1]), equals([1]));
    });

    test('i_pack write Int32', () {
      expect(i_pack(21474830), equals([1, 71, 174, 14]));
    });

    test('i_unpack read Int32', () {
      expect(i_unpack([0, 0, 0, 1]), equals([1]));
    });

    test('h_pack write Int16', () {
      expect(h_pack(32760), equals([127, 248]));
    });

    test('h_unpack read Int16', () {
      expect(h_unpack([127, 248]), equals([32760]));
    });

    test('ii_pack write 2 Int32', () {
      var res = ii_pack(21474830, 21474830);
      expect(res, equals([1, 71, 174, 14, 1, 71, 174, 14]));
    });

    test('ii_unpack read 2 Int32', () {
      expect(ii_unpack([1, 71, 174, 14, 1, 71, 174, 14]),
          equals([21474830, 21474830]));
    });

    test('ihihih_pack write Int32 Int16 | Int32 Int16 | Int32 Int16', () {
      var res = ihihih_pack(
        21474830,
        32760,
        21474830,
        32760,
        21474830,
        32760,
      );
      expect(
          res,
          equals([
            1,
            71,
            174,
            14,
            127,
            248,
            1,
            71,
            174,
            14,
            127,
            248,
            1,
            71,
            174,
            14,
            127,
            248
          ]));
    });

    test('ihihih_unpack read Int32 Int16 | Int32 Int16 | Int32 Int16', () {
      expect(
          ihihih_unpack([
            1,
            71,
            174,
            14,
            127,
            248,
            1,
            71,
            174,
            14,
            127,
            248,
            1,
            71,
            174,
            14,
            127,
            248
          ]),
          equals([21474830, 32760, 21474830, 32760, 21474830, 32760]));
    });

    test('ci_pack write one byte and Int32', () {
      expect(ci_pack(0, 21474830), equals([0, 1, 71, 174, 14]));
    });

    test('ci_unpack read one byte and Int32', () {
      expect(ci_unpack([0, 1, 71, 174, 14]), equals([0, 21474830]));
    });

    test('bh_pack write one byte and Int16', () {
      expect(bh_pack(0, 32760), equals([0, 127, 248]));
    });

    test('bh_unpack read one byte and Int16', () {
      expect(bh_unpack([0, 127, 248]), equals([0, 32760]));
    });

    test('cccc_pack write 4 byte', () {
      expect(cccc_pack(0, 0, 0, 0), equals([0, 0, 0, 0]));
    });

    test('cccc_unpack read 4 byte', () {
      expect(cccc_unpack([0, 0, 0, 0]), equals([0, 0, 0, 0]));
    });
    //unpack
    test('unpack cccc', () {
      expect(unpack('cccc', [0, 0, 0, 0]), equals([0, 0, 0, 0]));
    });

    test('unpack ii', () {
      expect(unpack('ii', [1, 71, 174, 14, 1, 71, 174, 14]),
          equals([21474830, 21474830]));
    });

    test('unpack hh', () {
      expect(unpack('hh', [127, 248, 127, 248]), equals([32760, 32760]));
    });

    test('unpack b', () {
      expect(unpack('b', [0]), equals([0]));
    });

    //unpack fast
    test('unpack2 cccc', () {
      expect(unpack2('cccc', [0, 0, 0, 0]), equals([0, 0, 0, 0]));
    });

    test('unpack2 ii', () {
      expect(unpack2('ii', [1, 71, 174, 14, 1, 71, 174, 14]),
          equals([21474830, 21474830]));
    });

    test('unpack2 hh', () {
      expect(unpack2('hh', [127, 248, 127, 248]), equals([32760, 32760]));
    });

    test('unpack2 b', () {
      expect(unpack2('b', [0]), equals([0]));
    });
  });
}
