import 'dart:typed_data';

/// A growable, big-endian writer for PostgreSQL frontend messages.
class PgWriteBuffer {
  PgWriteBuffer({int initialCapacity = 256})
      : _buffer = _allocate(initialCapacity) {
    _data = ByteData.view(_buffer.buffer);
  }

  Uint8List _buffer;
  late ByteData _data;
  int _length = 0;
  int _messageLengthOffset = -1;

  int get length => _length;

  /// Starts a regular PostgreSQL message and reserves its four-byte length.
  ///
  /// [endMessage] patches the reserved field. PostgreSQL's length includes the
  /// length field itself, but excludes [code]. Messages may be batched one after
  /// another; nesting messages is rejected.
  void startMessage(int code) {
    if (_messageLengthOffset != -1) {
      throw StateError('A PostgreSQL message is already being written.');
    }
    writeUint8(code);
    _messageLengthOffset = _length;
    writeUint32(0);
  }

  /// Finishes the current message and returns its PostgreSQL length.
  int endMessage() {
    final offset = _messageLengthOffset;
    if (offset == -1) {
      throw StateError('No PostgreSQL message is being written.');
    }
    final messageLength = _length - offset;
    patchUint32(offset, messageLength);
    _messageLengthOffset = -1;
    return messageLength;
  }

  void writeUint8(int value) {
    _ensureCapacity(1);
    _data.setUint8(_length, value);
    _length++;
  }

  void writeUint16(int value) {
    _ensureCapacity(2);
    _data.setUint16(_length, value, Endian.big);
    _length += 2;
  }

  void writeUint32(int value) {
    _ensureCapacity(4);
    _data.setUint32(_length, value, Endian.big);
    _length += 4;
  }

  void writeInt32(int value) {
    _ensureCapacity(4);
    _data.setInt32(_length, value, Endian.big);
    _length += 4;
  }

  /// Appends [bytes] in the half-open range [start], [end].
  void writeBytes(List<int> bytes, [int start = 0, int? end]) {
    final actualEnd = end ?? bytes.length;
    RangeError.checkValidRange(start, actualEnd, bytes.length);
    final count = actualEnd - start;
    if (count == 0) return;
    _ensureCapacity(count);
    _buffer.setRange(_length, _length + count, bytes, start);
    _length += count;
  }

  /// Patches an existing unsigned 32-bit field in big-endian order.
  void patchUint32(int offset, int value) {
    RangeError.checkValidRange(offset, offset + 4, _length, 'offset');
    _data.setUint32(offset, value, Endian.big);
  }

  /// Returns the written portion of this buffer.
  ///
  /// The default copy is stable across subsequent writes and [clear] calls.
  /// With `copy: false`, the result is a transient view of the backing buffer.
  Uint8List toBytes({bool copy = true}) {
    if (copy) {
      final result = Uint8List(_length);
      result.setRange(0, _length, _buffer);
      return result;
    }
    if (_length == _buffer.length) return _buffer;
    return Uint8List.sublistView(_buffer, 0, _length);
  }

  void _ensureCapacity(int additionalBytes) {
    final required = _length + additionalBytes;
    if (required <= _buffer.length) return;

    var capacity = _buffer.isEmpty ? 1 : _buffer.length;
    while (capacity < required) {
      capacity *= 2;
    }
    final grown = Uint8List(capacity);
    grown.setRange(0, _length, _buffer);
    _buffer = grown;
    _data = ByteData.view(grown.buffer);
  }

  static Uint8List _allocate(int capacity) {
    if (capacity < 0) {
      throw RangeError.value(
        capacity,
        'initialCapacity',
        'Must not be negative.',
      );
    }
    return Uint8List(capacity);
  }
}
