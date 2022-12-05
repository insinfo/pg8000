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
  });
}
