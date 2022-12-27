import 'package:dargres/src/dependencies/saslprep/saslprep_export.dart';
import 'package:test/test.dart';

void main() {
  group('Saslprep', () {
    test('should work with liatin letters', () {
      var str = 'user';
      expect(Saslprep.saslprep(str), equals(str));
    });

    test('should work be case preserved', () {
      var str = 'USER';
      expect(Saslprep.saslprep(str), equals(str));
    });

    test('should work with high code points (> U+FFFF)', () {
      var str = '\uD83D\uDE00';
      expect(
          Saslprep.saslprep(str, options: SaslprepOptions(true)), equals(str));
    });

    test('should remove `mapped to nothing` characters', () {
      expect(Saslprep.saslprep('I\u00ADX'), equals('IX'));
    });

    test('should replace `Non-ASCII space characters` with space', () {
      expect(Saslprep.saslprep('a\u00A0b'), equals('a\u0020b'));
    });

    test('should normalize as NFKC', () {
      expect(Saslprep.saslprep('\u00AA'), equals('a'));
      expect(Saslprep.saslprep('\u2168'), equals('IX'));
    });

    test('should throws when prohibited characters', () {
      // C.2.1 ASCII control characters
      expect(() => Saslprep.saslprep('a\u007Fb'), throwsA(isA<Exception>()));

      // C.2.2 Non-ASCII control characters
      expect(() => Saslprep.saslprep('a\u06DDb'), throwsA(isA<Exception>()));

      // C.3 Private use
      expect(() => Saslprep.saslprep('a\uE000b'), throwsA(isA<Exception>()));

      // C.4 Non-character code points
      expect(() => Saslprep.saslprep('a${String.fromCharCode(0x1fffe)}b'),
          throwsA(isA<Exception>()));

      // C.5 Surrogate codes
      expect(() => Saslprep.saslprep('a\uD800b'), throwsA(isA<Exception>()));

      // C.6 Inappropriate for plain text
      expect(() => Saslprep.saslprep('a\uFFF9b'), throwsA(isA<Exception>()));

      // C.7 Inappropriate for canonical representation
      expect(() => Saslprep.saslprep('a\u2FF0b'), throwsA(isA<Exception>()));

      // C.8 Change display properties or are deprecated
      expect(() => Saslprep.saslprep('a\u200Eb'), throwsA(isA<Exception>()));

      // C.9 Tagging characters
      expect(() => Saslprep.saslprep('a${String.fromCharCode(0xe0001)}b'),
          throwsA(isA<Exception>()));
    });

    test('should not containt RandALCat and LCat bidi', () {
      expect(
          () => Saslprep.saslprep('a\u06DD\u00AAb'), throwsA(isA<Exception>()));
    });

    test('RandALCat should be first and last', () {
      expect(() => Saslprep.saslprep('\u0627\u0031\u0628'),
          isNot(throwsA(isA<Exception>())));
      expect(
          () => Saslprep.saslprep('\u0627\u0031'), throwsA(isA<Exception>()));
    });

    test('should handle unassigned code points', () {
      expect(() => Saslprep.saslprep('a\u0487'), throwsA(isA<Exception>()));
      expect(() => Saslprep.saslprep('a\u0487', options: SaslprepOptions(true)),
          isNot(throwsA(isA<Exception>())));
    });
  });
}