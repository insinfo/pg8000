import 'dart:typed_data';


import 'package:dargres/src/dependencies/buffer_terrier/raw_reader.dart';

import 'package:test/test.dart';

import 'package:dargres/src/dependencies/buffer_terrier/debug_hex_codec.dart';
//import 'package:matcher/matcher.dart';

import 'package:dargres/src/dependencies/buffer_terrier/raw_data.dart';
import 'package:dargres/src/dependencies/buffer_terrier/raw_value.dart';

/// Returns a matcher that matches integers with the bytes.
/// Uses [DebugHexEncoder] for describing problems.
Matcher byteListEquals(Iterable<int> expected, {DebugHexEncoder? format}) {
  return _ByteListEquals(expected.toList(), format: format);
}

/// Returns a matcher that matches [RawEncodable] with another .
/// Uses [DebugHexEncoder] for describing problems.
Matcher selfEncoderEquals(RawEncodable expected, {DebugHexEncoder? format}) {
  return _SelfEncoderEquals(expected, format: format);
}

/// Returns a matcher that matches [RawEncodable] with the bytes.
/// Uses [DebugHexEncoder] for describing problems.
Matcher selfEncoderEqualsBytes(Iterable<int> expected,
    {DebugHexEncoder? format}) {
  return _SelfEncoderEquals(RawData(expected.toList()), format: format);
}

class _ByteListEquals extends Matcher {
  final List _expected;
  final DebugHexEncoder format;

  _ByteListEquals(this._expected, {DebugHexEncoder? format})
      : this.format = format ?? const DebugHexEncoder();

  @override
  Description describe(Description description) {
    description = description.add('equals hex:').add(format.convert(_expected));
    return description;
  }

  @override
  Description describeMismatch(
      item, Description mismatchDescription, Map matchState, bool verbose) {
    if (item is List) {
      return mismatchDescription
          .replace("Actually hex:")
          .add(format.convert(item, expected: _expected as List<int>));
    } else {
      return orderedEquals(_expected)
          .describeMismatch(item, mismatchDescription, matchState, verbose);
    }
  }

  @override
  bool matches(item, Map matchState) {
    if (item is List) {
      if (_expected.length != item.length) {
        return false;
      }
      for (var i = 0; i < item.length; i++) {
        if (_expected[i] != item[i]) {
          return false;
        }
      }
      return true;
    }
    return orderedEquals(_expected).matches(item, matchState);
  }
}

class _SelfEncoderEquals extends Matcher {
  final _ByteListEquals _equals;
  final Matcher _fallbackEquals;

  _SelfEncoderEquals(RawEncodable expected, {DebugHexEncoder? format})
      : this._equals =
            _ByteListEquals(expected.toUint8ListViewOrCopy(), format: format),
        this._fallbackEquals = equals(expected);

  @override
  Description describe(Description description) {
    return _equals.describe(description);
  }

  @override
  Description describeMismatch(
      item, Description mismatchDescription, Map matchState, bool verbose) {
    if (item is RawEncodable) {
      return _equals.describeMismatch(
        item.toUint8ListViewOrCopy(),
        mismatchDescription,
        matchState,
        verbose,
      );
    } else {
      return _fallbackEquals.describeMismatch(
        item,
        mismatchDescription,
        matchState,
        verbose,
      );
    }
  }

  @override
  bool matches(item, Map matchState) {
    if (item is RawEncodable) {
      return _equals.matches(item.toUint8ListViewOrCopy(), matchState);
    } else {
      return _fallbackEquals.matches(item, matchState);
    }
    //return _fallbackEquals.matches(item, matchState);
  }
}


void main() {
  group("RawReader:", () {
    group("numbers:", () {
     late int expected;
     late int length;
     late RawReader reader;

      // tearDown(() {
      //   expected = null;
      //   length = null;
      //   reader = null;
      // });

      /// Converts reader to little-endian.
      void littleEndian(int length) {
        final input = reader.bufferAsUint8List;
        final inputCopy = List<int>.from(input);
        final firstIndex = reader.index;
        final lastIndex = reader.index + length - 1;
        for (var i = 0; i < length; i++) {
          input[firstIndex + i] = inputCopy[lastIndex - i];
        }
      }

      test("little-endian conversion works", () {
        reader = RawReader.withBytes([0, 1, 2, 3, 4]);
        reader.index = 1;
        littleEndian(3);
        expect(reader.bufferAsUint8List, byteListEquals([0, 3, 2, 1, 4]));
      });

      group("readUint8:", () {
        setUp(() {
          reader = RawReader.withBytes(const <int>[0, 0, 0xF2]);
          reader.index = 2;
          expected = 0xF2;
          length = 1;
        });

        test("simple call", () {
          expect(reader.availableLength, length);
          expect(reader.readUint8(), expected);
          expect(reader.availableLength, 0);
        });

        test("throws RawReaderException when EOF is encountered", () {
          reader.index += reader.availableLength;
          expect(reader.availableLength, 0);
          expect(
            () => reader.readUint8(),
            throwsA(const TypeMatcher<RawReaderException>()),
          );
        });
      });

      group("readUint16:", () {
        setUp(() {
          reader = RawReader.withBytes(const <int>[0, 0, 1, 2]);
          reader.index = 2;
          expected = 0x0102;
          length = 2;
        });

        test("simple call", () {
          expect(reader.availableLength, length);
          expect(reader.readUint16(), expected);
          expect(reader.availableLength, 0);
        });

        test("big-endian", () {
          expect(reader.availableLength, length);
          expect(reader.readUint16(Endian.big), expected);
          expect(reader.availableLength, 0);
        });

        test("little-endian", () {
          littleEndian(2);
          expect(reader.availableLength, length);
          expect(reader.readUint16(Endian.little), expected);
          expect(reader.availableLength, 0);
        });
        test("throws RawReaderException when EOF is encountered", () {
          reader.index += reader.availableLength - (length - 1);
          expect(reader.availableLength, (length - 1));
          expect(
            () => reader.readUint16(),
            throwsA(const TypeMatcher<RawReaderException>()),
          );
        });
      });

      group("readUint32:", () {
        setUp(() {
          reader = RawReader.withBytes(const <int>[0, 0, 1, 2, 3, 4]);
          reader.index = 2;
          expected = 0x01020304;
          length = 4;
        });
        test("simple call", () {
          expect(reader.availableLength, length);
          expect(reader.readUint32(), expected);
          expect(reader.availableLength, 0);
        });
        test("big-endian", () {
          expect(reader.availableLength, length);
          expect(reader.readUint32(Endian.big), expected);
          expect(reader.availableLength, 0);
        });
        test("little-endian", () {
          littleEndian(4);
          expect(reader.availableLength, length);
          expect(reader.readUint32(Endian.little), expected);
          expect(reader.availableLength, 0);
        });
        test("throws RawReaderException when EOF is encountered", () {
          reader.index += reader.availableLength - (length - 1);
          expect(reader.availableLength, (length - 1));
          expect(
            () => reader.readUint32(),
            throwsA(const TypeMatcher<RawReaderException>()),
          );
        });
      });

      group("readInt8:", () {
        setUp(() {
          reader = RawReader.withBytes(const <int>[0, 0, 0xFE]);
          reader.index = 2;
          expected = -2;
          length = 1;
        });
        test("simple call", () {
          expect(reader.availableLength, 1);
          expect(reader.readInt8(), expected);
          expect(reader.availableLength, 0);
        });
        test("throws RawReaderException when EOF is encountered", () {
          reader.index += reader.availableLength;
          expect(reader.availableLength, 0);
          expect(
            () => reader.readInt8(),
            throwsA(const TypeMatcher<RawReaderException>()),
          );
        });
      });

      group("readInt16:", () {
        setUp(() {
          reader = RawReader.withBytes(const <int>[0, 0, 0xFF, 0xFE]);
          reader.index = 2;
          expected = -2;
          length = 2;
        });

        test("simple call", () {
          expect(reader.availableLength, length);
          expect(reader.readInt16(), expected);
          expect(reader.availableLength, 0);
        });

        test("big-endian", () {
          expect(reader.availableLength, length);
          expect(reader.readInt16(Endian.big), expected);
          expect(reader.availableLength, 0);
        });

        test("little-endian", () {
          littleEndian(2);
          expect(reader.availableLength, length);
          expect(reader.readInt16(Endian.little), expected);
          expect(reader.availableLength, 0);
        });

        test("throws RawReaderException when EOF is encountered", () {
          reader.index += reader.availableLength - (length - 1);
          expect(reader.availableLength, (length - 1));
          expect(
            () => reader.readInt16(),
            throwsA(const TypeMatcher<RawReaderException>()),
          );
        });
      });

      group("readInt32:", () {
        setUp(() {
          reader = RawReader.withBytes(
            const <int>[0, 0, 0xFF, 0xFF, 0xFF, 0xFE],
          );
          reader.index = 2;
          expected = -2;
          length = 4;
        });

        test("simple call", () {
          expect(reader.availableLength, length);
          expect(reader.readInt32(), expected);
          expect(reader.availableLength, 0);
        });

        test("big-endian", () {
          expect(reader.availableLength, length);
          expect(reader.readInt32(Endian.big), expected);
          expect(reader.availableLength, 0);
        });

        test("little-endian", () {
          littleEndian(4);
          expect(reader.availableLength, length);
          expect(reader.readInt32(Endian.little), expected);
          expect(reader.availableLength, 0);
        });

        test("throws RawReaderException when EOF is encountered", () {
          reader.index += reader.availableLength - (length - 1);
          expect(reader.availableLength, (length - 1));
          expect(
            () => reader.readInt32(),
            throwsA(const TypeMatcher<RawReaderException>()),
          );
        });
      });
    });
  });

  // group("readFixInt64:", () {
  //   test("simple call", () {
  //     final input = const <int>[0, 1, 2, 3, 4, 5, 6, 7, 8];
  //     final expected =
  //         Int64.fromBytesBigEndian(const <int>[1, 2, 3, 4, 5, 6, 7, 8]);

  //     final reader = Rawreader!.withBytes(input);
  //     reader!.index = 1;
  //     expect(reader!.readFixInt64(), expected);
  //     expect(reader!.availableLength, 0);
  //   });

  //   test("big-endian", () {
  //     final input = const <int>[0, 1, 2, 3, 4, 5, 6, 7, 8];
  //     final expected =
  //         Int64.fromBytesBigEndian(const <int>[1, 2, 3, 4, 5, 6, 7, 8]);

  //     final reader = Rawreader!.withBytes(input);
  //     reader!.index = 1;
  //     expect(reader!.readFixInt64(Endian.big), expected);
  //     expect(reader!.availableLength, 0);
  //   });

  //   test("little-endian", () {
  //     final input = const <int>[0, 8, 7, 6, 5, 4, 3, 2, 1];
  //     final expected =
  //         Int64.fromBytesBigEndian(const <int>[1, 2, 3, 4, 5, 6, 7, 8]);

  //     final reader = Rawreader!.withBytes(input);
  //     reader!.index = 1;
  //     expect(reader!.readFixInt64(Endian.little), expected);
  //     expect(reader!.availableLength, 0);
  //   });
  // });

  test("readVarUint", () {
    final input = [0, 1, 2, 0x81, 0x01, 0x80, 0x80, 0x01];
    final reader = RawReader.withBytes(input);
    expect(reader.readVarUint(), 0);
    expect(reader.readVarUint(), 1);
    expect(reader.readVarUint(), 2);
    expect(reader.readVarUint(), 129);
    expect(reader.readVarUint(), 1 << 14);
  });

  test("readVarInt", () {
    final input = [0, 1, 2, 3, 4, 0x80, 0x01, 0x81, 0x01];
    final reader = RawReader.withBytes(input);
    expect(reader.readVarInt(), 0);
    expect(reader.readVarInt(), -1);
    expect(reader.readVarInt(), 1);
    expect(reader.readVarInt(), -2);
    expect(reader.readVarInt(), 2);
    expect(reader.readVarInt(), 64);
    expect(reader.readVarInt(), -65);
  });

  group("readUint8ListViewOrCopy", () {
    test("When isViewAllowed == true, returns a view", () {
      final original = Uint8List(3);
      const initialIndex = 1;
      const readLength = 2;

      // New reader
      final reader = RawReader.withBytes(original, isViewAllowed: true);
      reader.index = initialIndex;

      // Mutate original
      original[initialIndex] = 1;

      // Read
      final result = reader.readUint8ListViewOrCopy(readLength);
      expect(result[0], 1);
      expect(reader.index, initialIndex + readLength);

      // Mutate original
      original[initialIndex] = 2;
      expect(result[0], 2);
    });

    test("Normally returns a copy", () {
      final original = Uint8List(3);
      const initialIndex = 1;
      const readLength = 2;

      // New reader
      final reader = RawReader.withBytes(original);
      reader.index = initialIndex;

      // Mutate original
      original[initialIndex] = 1;

      // Read
      final result = reader.readUint8ListViewOrCopy(readLength);
      expect(result[0], 1);
      expect(reader.index, initialIndex + readLength);

      // Mutate original
      original[initialIndex] = 2;
      expect(result[0], 1);
    });
  });

  group("readUint8ListCopy", () {
    test("Always returns a copy", () {
      final original = Uint8List(3);
      const initialIndex = 1;
      const readLength = 2;

      // New reader
      final reader = RawReader.withBytes(original, isViewAllowed: true);
      reader.index = initialIndex;

      // Mutate original
      original[initialIndex] = 1;

      // Read
      final result = reader.readUint8List(readLength);
      expect(result[0], 1);
      expect(reader.index, initialIndex + readLength);

      // Mutate original
      original[initialIndex] = 2;
      expect(result[0], 1);
    });
  });

  group("readByteDataViewOrCopy", () {
    test("When isViewAllowed == true, returns a view", () {
      final original = Uint8List(3);
      const initialIndex = 1;
      const readLength = 2;

      // New reader
      final reader = RawReader.withBytes(original, isViewAllowed: true);
      reader.index = initialIndex;

      // Mutate original
      original[initialIndex] = 1;

      // Read
      final result = reader.readByteDataViewOrCopy(readLength);
      expect(result.getUint8(0), 1);
      expect(reader.index, initialIndex + readLength);

      // Mutate original
      original[initialIndex] = 2;
      expect(result.getUint8(0), 2);
    });

    test("Normally returns a copy", () {
      final original = Uint8List(3);
      const initialIndex = 1;
      const readLength = 2;

      // New reader
      final reader = RawReader.withBytes(original);
      reader.index = initialIndex;

      // Mutate original
      original[initialIndex] = 1;

      // Read
      final result = reader.readByteDataViewOrCopy(readLength);
      expect(result.getUint8(0), 1);
      expect(reader.index, initialIndex + readLength);

      // Mutate original
      original[initialIndex] = 2;
      expect(result.getUint8(0), 1);
    });
  });

  group("readByteDataCopy", () {
    test("Always returns a copy", () {
      final original = Uint8List(3);
      const initialIndex = 1;
      const readLength = 2;

      // New reader
      final reader = RawReader.withBytes(original, isViewAllowed: true);
      reader.index = initialIndex;

      // Mutate original
      original[initialIndex] = 1;

      // Read
      final result = reader.readByteData(readLength);
      expect(result.getUint8(0), 1);
      expect(reader.index, initialIndex + readLength);

      // Mutate original
      original[initialIndex] = 2;
      expect(result.getUint8(0), 1);
    });
  });

  test("readUtf8", () {
    final input = [0x61, 0x62, 0x63, 0xf0, 0x9f, 0x99, 0x8f];
    final reader = RawReader.withBytes(input);
    expect(reader.readUtf8(3), "abc");
    expect(reader.index, 3);
    expect(reader.readUtf8(4), "🙏");
    expect(reader.index, 7);
  });

  test("readUtf8NullEnding", () {
    final input = [0x61, 0x62, 0x63, 0, 0xf0, 0x9f, 0x99, 0x8f, 0];
    final reader = RawReader.withBytes(input);
    expect(reader.readUtf8NullEnding(), "abc");
    expect(reader.index, 4);
    expect(reader.readUtf8NullEnding(), "🙏");
    expect(reader.index, 9);
  });

  test("readUtf8NullEnding (missing zero)", () {
    final input = [0x61, 0x62, 0x63];
    final reader = RawReader.withBytes(input);
    expect(() => reader.readUtf8NullEnding(),
        throwsA(TypeMatcher<RawReaderException>()));
  });

  test("readZeroes()", () {
    final reader = RawReader.withBytes([0, 0, 0]);
    reader.index = 1;
    reader.readZeroes(2);
    expect(reader.availableLength, 0);
  });

  test("readZeroes() throws RawReaderException if it encounters non-zero value",
      () {
    final reader = RawReader.withBytes([0, 0, 1, 0]);
    reader.index = 1;
    expect(
      () => reader.readZeroes(3),
      throwsA(const TypeMatcher<RawReaderException>()),
    );
  });
}
