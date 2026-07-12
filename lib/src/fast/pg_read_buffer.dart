import 'dart:typed_data';

/// A borrowed contiguous region returned by [PgReadBuffer.readRegion].
///
/// The object itself, and possibly [bytes], are reused by the buffer. Consumers
/// must finish processing the region synchronously and must not retain it after
/// the next read.
class PgReadRegion {
  PgReadRegion._(this._bytes);

  Uint8List _bytes;
  int _offset = 0;
  int _length = 0;

  /// The storage containing this region.
  Uint8List get bytes => _bytes;

  /// The first byte of the region in [bytes].
  int get offset => _offset;

  /// The number of bytes in the region.
  int get length => _length;

}

/// A segmented PostgreSQL input buffer.
///
/// Socket chunks are retained as-is. The common case therefore reads directly
/// from the socket's [Uint8List], without first copying it into an accumulator.
/// [bytesAvailable] is maintained incrementally and is O(1).
///
/// A read spanning chunks is copied only when a contiguous region is requested;
/// that copy goes into a growable scratch buffer which is reused by subsequent
/// calls. Integer reads spanning chunks do not coalesce the input.
class PgReadBuffer {
  PgReadBuffer({int initialScratchCapacity = 0})
      : _scratch = _allocateScratch(initialScratchCapacity),
        _region = PgReadRegion._(_emptyBytes);

  static final Uint8List _emptyBytes = Uint8List(0);
  static const int _maxRetainedScratchCapacity = 1024 * 1024;

  final List<Uint8List?> _chunks = <Uint8List?>[];
  int _headIndex = 0;
  int _headOffset = 0;
  int _bytesAvailable = 0;

  Uint8List _scratch;
  final PgReadRegion _region;

  /// The unread byte count. This getter is O(1).
  int get bytesAvailable => _bytesAvailable;

  /// The socket chunk containing the next unread byte.
  ///
  /// This is the original [Uint8List] passed to [append], not a view or a copy.
  /// Throws when no bytes are available.
  Uint8List get currentChunk {
    if (_bytesAvailable == 0) {
      throw StateError('The read buffer is empty.');
    }
    return _chunks[_headIndex]!;
  }

  /// Offset of the next unread byte inside [currentChunk].
  int get currentOffset => _bytesAvailable == 0 ? 0 : _headOffset;

  /// Adds a socket chunk without copying it.
  void append(Uint8List chunk) {
    if (chunk.isEmpty) return;
    _chunks.add(chunk);
    _bytesAvailable += chunk.length;
  }

  /// Whether [length] bytes can be accessed through [currentChunk] starting at
  /// [currentOffset].
  bool hasContiguous(int length) {
    if (length < 0) {
      throw RangeError.value(length, 'length', 'Must not be negative.');
    }
    if (length == 0) return true;
    return _bytesAvailable >= length &&
        _chunks[_headIndex]!.length - _headOffset >= length;
  }

  int _readUint8() {
    _requireAvailable(1);
    final chunk = _chunks[_headIndex]!;
    final value = chunk[_headOffset];
    _consumeFromHead(1);
    return value;
  }

  int readByte() {
    _releaseOversizedScratch();
    return _readUint8();
  }

  int _readUint32() {
    _requireAvailable(4);
    int value;
    if (hasContiguous(4)) {
      final chunk = _chunks[_headIndex]!;
      final offset = _headOffset;
      value = (chunk[offset] << 24) |
          (chunk[offset + 1] << 16) |
          (chunk[offset + 2] << 8) |
          chunk[offset + 3];
      _consumeFromHead(4);
    } else {
      value = (_readUint8() << 24) |
          (_readUint8() << 16) |
          (_readUint8() << 8) |
          _readUint8();
    }
    // Dart VM bitwise operations use signed machine words, while dart2js uses
    // signed 32-bit results. Normalize both runtimes to an unsigned value.
    return value & 0xffffffff;
  }

  int readInt32() {
    _releaseOversizedScratch();
    final value = _readUint32();
    return value < 0x80000000 ? value : value - 0x100000000;
  }

  /// Returns and consumes a borrowed contiguous region of [length] bytes.
  ///
  /// If the bytes are already in one socket chunk, [PgReadRegion.bytes] is that
  /// exact chunk. Otherwise the bytes are coalesced into reusable scratch
  /// storage. No [Uint8List] view is created in either case.
  PgReadRegion readRegion(int length) {
    _releaseOversizedScratch();
    _requireAvailable(length);

    if (length == 0) {
      _setRegion(_emptyBytes, 0, 0);
      return _region;
    }

    if (hasContiguous(length)) {
      final chunk = _chunks[_headIndex]!;
      final offset = _headOffset;
      _consumeFromHead(length);
      _setRegion(chunk, offset, length);
      return _region;
    }

    _ensureScratchCapacity(length);
    var destinationOffset = 0;
    var remaining = length;
    while (remaining != 0) {
      final chunk = _chunks[_headIndex]!;
      final count = _min(remaining, chunk.length - _headOffset);
      _scratch.setRange(
        destinationOffset,
        destinationOffset + count,
        chunk,
        _headOffset,
      );
      destinationOffset += count;
      remaining -= count;
      _consumeFromHead(count);
    }
    _setRegion(_scratch, 0, length);
    return _region;
  }

  /// Consumes [length] bytes without materializing them.
  void skip(int length) {
    _releaseOversizedScratch();
    _requireAvailable(length);
    var remaining = length;
    while (remaining != 0) {
      final chunk = _chunks[_headIndex]!;
      final count = _min(remaining, chunk.length - _headOffset);
      remaining -= count;
      _consumeFromHead(count);
    }
  }

  /// Discards all queued chunks while retaining scratch storage for reuse.
  void clear() {
    _chunks.clear();
    _headIndex = 0;
    _headOffset = 0;
    _bytesAvailable = 0;
    _setRegion(_emptyBytes, 0, 0);
    if (_scratch.length > _maxRetainedScratchCapacity) {
      _scratch = Uint8List(0);
    }
  }

  void _releaseOversizedScratch() {
    if (_scratch.length <= _maxRetainedScratchCapacity ||
        !identical(_region._bytes, _scratch)) {
      return;
    }
    _scratch = Uint8List(0);
    _setRegion(_emptyBytes, 0, 0);
  }

  void _setRegion(Uint8List bytes, int offset, int length) {
    _region._bytes = bytes;
    _region._offset = offset;
    _region._length = length;
  }

  void _requireAvailable(int length) {
    if (length < 0) {
      throw RangeError.value(length, 'length', 'Must not be negative.');
    }
    if (length > _bytesAvailable) {
      throw RangeError.range(
        length,
        0,
        _bytesAvailable,
        'length',
        'Only $_bytesAvailable bytes are available.',
      );
    }
  }

  void _consumeFromHead(int count) {
    _headOffset += count;
    _bytesAvailable -= count;

    final chunk = _chunks[_headIndex]!;
    if (_headOffset != chunk.length) return;

    _chunks[_headIndex] = null;
    _headIndex++;
    _headOffset = 0;

    if (_bytesAvailable == 0) {
      _chunks.clear();
      _headIndex = 0;
      return;
    }

    // Release consumed slots occasionally. This never copies socket bytes and
    // keeps queue operations amortized O(1).
    if (_headIndex >= 64 && _headIndex * 2 >= _chunks.length) {
      _chunks.removeRange(0, _headIndex);
      _headIndex = 0;
    }
  }

  void _ensureScratchCapacity(int required) {
    if (_scratch.length >= required) return;
    var capacity = _scratch.isEmpty ? 64 : _scratch.length;
    while (capacity < required) {
      capacity *= 2;
    }
    _scratch = Uint8List(capacity);
  }

  static Uint8List _allocateScratch(int capacity) {
    if (capacity < 0) {
      throw RangeError.value(
        capacity,
        'initialScratchCapacity',
        'Must not be negative.',
      );
    }
    return Uint8List(capacity);
  }

  static int _min(int a, int b) => a < b ? a : b;
}
