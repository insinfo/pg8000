import 'dart:convert';

import 'package:dargres/src/utils/crypto.dart';
import 'package:test/test.dart';

void main() {
  group('hex', () {
    test('encodes and decodes without package:convert', () {
      final bytes = <int>[0x00, 0x01, 0x7f, 0x80, 0xab, 0xcd, 0xef, 0xff];
      expect(hexEncode(bytes), '00017f80abcdefff');
      expect(hexDecode('00017F80aBcDeFfF'), bytes);
      expect(hexEncodeAscii(<int>[0xab, 0xcd]), <int>[97, 98, 99, 100]);
    });

    test('rejects malformed input', () {
      expect(() => hexDecode('0'), throwsFormatException);
      expect(() => hexDecode('0x'), throwsFormatException);
      expect(() => hexDecode('gg'), throwsFormatException);
    });
  });

  group('MD5 RFC 1321 vectors', () {
    const vectors = <String, String>{
      '': 'd41d8cd98f00b204e9800998ecf8427e',
      'a': '0cc175b9c0f1b6a831c399e269772661',
      'abc': '900150983cd24fb0d6963f7d28e17f72',
      'message digest': 'f96b697d7cb7938d525a2f31aaf161d0',
      'abcdefghijklmnopqrstuvwxyz': 'c3fcd3d76192e4007dfb496cca67e13b',
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789':
          'd174ab98d277d9f5a5611c2c9f419d9f',
      '12345678901234567890123456789012345678901234567890123456789012345678901234567890':
          '57edf4a22be3c955ac49da2e2107b67a',
    };

    for (final vector in vectors.entries) {
      test('message length ${vector.key.length}', () {
        expect(hexEncode(md5.convert(ascii.encode(vector.key))), vector.value);
      });
    }
  });

  group('SHA FIPS 180 vectors', () {
    test('SHA-1 empty and one/two-block messages', () {
      expect(hexEncode(sha1.convert(const <int>[])),
          'da39a3ee5e6b4b0d3255bfef95601890afd80709');
      expect(hexEncode(sha1.convert(ascii.encode('abc'))),
          'a9993e364706816aba3e25717850c26c9cd0d89d');
      expect(
          hexEncode(sha1.convert(ascii.encode(
              'abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq'))),
          '84983e441c3bd26ebaae4aa1f95129e5e54670f1');
    });

    test('SHA-256 empty and one/two-block messages', () {
      expect(hexEncode(sha256.convert(const <int>[])),
          'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855');
      expect(hexEncode(sha256.convert(ascii.encode('abc'))),
          'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
      expect(
          hexEncode(sha256.convert(ascii.encode(
              'abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq'))),
          '248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1');
    });
  });

  group('HMAC RFC 2202 and RFC 4231 vectors', () {
    test('HMAC-SHA-1', () {
      expect(
          hexEncode(hmac(
              sha1, List<int>.filled(20, 0x0b), ascii.encode('Hi There'))),
          'b617318655057264e28bc0b6fb378c8ef146be00');
    });

    test('HMAC-SHA-256', () {
      expect(
          hexEncode(hmac(
              sha256, List<int>.filled(20, 0x0b), ascii.encode('Hi There'))),
          'b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7');
    });

    test('hashes keys longer than the block size', () {
      expect(
          hexEncode(hmac(
              sha256,
              List<int>.filled(131, 0xaa),
              ascii.encode(
                  'Test Using Larger Than Block-Size Key - Hash Key First'))),
          '60e431591ee0b67f0d8a26aacbf5b77f8e0bc6213728c5140546040f0ee37f54');
    });
  });

  group('PBKDF2 RFC 6070 and SHA-256 vectors', () {
    test('PBKDF2-HMAC-SHA-1', () {
      expect(
          hexEncode(pbkdf2Hmac(
              sha1, ascii.encode('password'), ascii.encode('salt'), 1)),
          '0c60c80f961f0e71f3a9b524af6012062fe037a6');
      expect(
          hexEncode(pbkdf2Hmac(
              sha1, ascii.encode('password'), ascii.encode('salt'), 2)),
          'ea6c014dc72d6f8ccd1ed92ace1d41f0d8de8957');
      expect(
          hexEncode(pbkdf2Hmac(
              sha1, ascii.encode('password'), ascii.encode('salt'), 4096)),
          '4b007901b765489abead49d926f721d065a429c1');
    });

    test('PBKDF2-HMAC-SHA-256', () {
      expect(
          hexEncode(pbkdf2Hmac(
              sha256, ascii.encode('password'), ascii.encode('salt'), 1)),
          '120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b');
      expect(
          hexEncode(pbkdf2Hmac(
              sha256, ascii.encode('password'), ascii.encode('salt'), 2)),
          'ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43');
      expect(
          hexEncode(pbkdf2Hmac(
              sha256, ascii.encode('password'), ascii.encode('salt'), 4096)),
          'c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a');
    });

    test('supports derived keys spanning more than one digest block', () {
      expect(
          hexEncode(pbkdf2Hmac(
              sha1, ascii.encode('password'), ascii.encode('salt'), 2,
              length: 25)),
          'ea6c014dc72d6f8ccd1ed92ace1d41f0d8de8957cae9313626');
    });

    test('validates iteration count and length', () {
      expect(() => pbkdf2Hmac(sha256, <int>[], <int>[], 0),
          throwsArgumentError);
      expect(() => pbkdf2Hmac(sha256, <int>[], <int>[], 1, length: -1),
          throwsArgumentError);
    });
  });

  test('constant-time proof comparison checks content and length', () {
    expect(constantTimeBytesEqual(<int>[1, 2], <int>[1, 2]), isTrue);
    expect(constantTimeBytesEqual(<int>[1, 2], <int>[1, 3]), isFalse);
    expect(constantTimeBytesEqual(<int>[1, 2], <int>[1, 2, 0]), isFalse);
  });
}
