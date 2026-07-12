import 'dart:typed_data';

import 'package:dargres/src/fast/pg_read_buffer.dart';
import 'package:dargres/src/fast/pg_write_buffer.dart';
import 'package:test/test.dart';

void main() {
  group('PgReadBuffer', () {
    test('keeps socket chunks and availability without copying', () {
      final first = Uint8List.fromList(<int>[10, 11, 12]);
      final second = Uint8List.fromList(<int>[13, 14]);
      final buffer = PgReadBuffer()
        ..append(Uint8List(0))
        ..append(first)
        ..append(second);

      expect(buffer.bytesAvailable, 5);
      expect(identical(buffer.currentChunk, first), isTrue);
      expect(buffer.hasContiguous(3), isTrue);
      expect(buffer.hasContiguous(4), isFalse);
      expect(buffer.readByte(), 10);
      buffer.skip(2);
      expect(identical(buffer.currentChunk, second), isTrue);
      expect(buffer.currentOffset, 0);
    });

    test('reads signed int32 across every chunk boundary', () {
      const bytes = <int>[0xff, 0xff, 0xff, 0xfe];
      for (var split = 1; split < 4; split++) {
        final buffer = PgReadBuffer()
          ..append(Uint8List.fromList(bytes.sublist(0, split)))
          ..append(Uint8List.fromList(bytes.sublist(split)));
        expect(buffer.readInt32(), -2, reason: 'split $split');
        expect(buffer.bytesAvailable, 0);
      }
    });

    test('returns direct regions and reuses scratch for fragmented regions', () {
      final direct = Uint8List.fromList(<int>[1, 2, 3, 4]);
      final buffer = PgReadBuffer(initialScratchCapacity: 8)..append(direct);
      buffer.skip(1);
      final first = buffer.readRegion(2);
      expect(identical(first.bytes, direct), isTrue);
      expect(first.offset, 1);
      expect(first.length, 2);

      buffer.clear();
      buffer
        ..append(Uint8List.fromList(<int>[5]))
        ..append(Uint8List.fromList(<int>[6, 7]));
      final second = buffer.readRegion(3);
      final scratch = second.bytes;
      expect(scratch.sublist(0, 3), <int>[5, 6, 7]);

      buffer
        ..append(Uint8List.fromList(<int>[8]))
        ..append(Uint8List.fromList(<int>[9]));
      final third = buffer.readRegion(2);
      expect(identical(second, third), isTrue);
      expect(identical(third.bytes, scratch), isTrue);
    });

    test('compacts consumed slots and remains reusable', () {
      final buffer = PgReadBuffer();
      for (var i = 0; i < 130; i++) {
        buffer.append(Uint8List.fromList(<int>[i & 0xff]));
      }
      buffer.skip(129);
      expect(buffer.readByte(), 129);
      final next = Uint8List.fromList(<int>[7, 8]);
      buffer.append(next);
      expect(identical(buffer.currentChunk, next), isTrue);
    });

    test('does not retain an abnormally large fragmented scratch forever', () {
      final half = Uint8List(600000);
      final buffer = PgReadBuffer()
        ..append(half)
        ..append(Uint8List(600000));
      final largeScratch = buffer.readRegion(1200000).bytes;
      expect(largeScratch.length, greaterThanOrEqualTo(1200000));

      buffer
        ..append(Uint8List.fromList(<int>[1]))
        ..readRegion(1);
      buffer
        ..append(Uint8List.fromList(<int>[2]))
        ..append(Uint8List.fromList(<int>[3]));
      final smallScratch = buffer.readRegion(2).bytes;
      expect(identical(smallScratch, largeScratch), isFalse);
      expect(smallScratch.length, lessThan(largeScratch.length));
    });

    test('validates input and clear resets queued chunks', () {
      final buffer = PgReadBuffer()..append(Uint8List.fromList(<int>[1, 2, 3]));
      expect(() => buffer.readInt32(), throwsRangeError);
      expect(() => buffer.readRegion(-1), throwsRangeError);
      expect(() => buffer.skip(4), throwsRangeError);
      expect(() => buffer.hasContiguous(-1), throwsRangeError);
      expect(buffer.bytesAvailable, 3);
      buffer.clear();
      expect(buffer.bytesAvailable, 0);
      expect(() => buffer.currentChunk, throwsStateError);
      expect(() => PgReadBuffer(initialScratchCapacity: -1), throwsRangeError);
    });
  });

  group('PgWriteBuffer', () {
    test('writes active integer and byte paths in network order', () {
      final buffer = PgWriteBuffer(initialCapacity: 1)
        ..writeUint8(0xff)
        ..writeUint16(0x1234)
        ..writeUint32(0x89abcdef)
        ..writeInt32(-2)
        ..writeBytes(<int>[1, 2, 3, 4], 1, 3);
      expect(buffer.toBytes(), <int>[
        0xff, 0x12, 0x34,
        0x89, 0xab, 0xcd, 0xef,
        0xff, 0xff, 0xff, 0xfe,
        2, 3,
      ]);
    });

    test('patches and batches PostgreSQL message lengths', () {
      final buffer = PgWriteBuffer(initialCapacity: 2);
      buffer.startMessage(0x51);
      buffer.writeBytes(<int>[0x4f, 0x4b, 0]);
      expect(buffer.endMessage(), 7);
      buffer.startMessage(0x53);
      expect(buffer.endMessage(), 4);
      expect(buffer.toBytes(), <int>[
        0x51, 0, 0, 0, 7, 0x4f, 0x4b, 0,
        0x53, 0, 0, 0, 4,
      ]);
    });

    test('copy is stable and transient view aliases patched storage', () {
      final buffer = PgWriteBuffer(initialCapacity: 8)..writeUint32(0);
      final copy = buffer.toBytes();
      final view = buffer.toBytes(copy: false);
      buffer.patchUint32(0, 0x01020304);
      expect(copy, <int>[0, 0, 0, 0]);
      expect(view, <int>[1, 2, 3, 4]);
    });

    test('rejects invalid state, ranges, and capacity', () {
      final buffer = PgWriteBuffer(initialCapacity: 4);
      expect(() => buffer.endMessage(), throwsStateError);
      buffer.startMessage(1);
      expect(() => buffer.startMessage(2), throwsStateError);
      expect(() => buffer.writeBytes(<int>[1, 2], 2, 1), throwsRangeError);
      expect(() => buffer.patchUint32(100, 1), throwsRangeError);
      expect(() => PgWriteBuffer(initialCapacity: -1), throwsRangeError);
    });
  });
}
