import 'dart:typed_data';

/// Small, allocation-conscious cryptographic primitives needed by the
/// PostgreSQL authentication protocols.
///
/// These are deliberately one-shot APIs. Hash objects are immutable and may be
/// shared between connections; each operation owns its mutable workspace.
abstract class Hash {
  const Hash();

  int get blockSize;
  int get digestSize;

  _HashWorkspace _createWorkspace();

  Uint8List convert(List<int> input) {
    final output = Uint8List(digestSize);
    _createWorkspace().convert(input, 0, input.length, output, 0);
    return output;
  }
}

const Hash md5 = _Md5();
const Hash sha1 = _Sha1();
const Hash sha256 = _Sha256();

const int _mask32 = 0xffffffff;

int _rotateLeft32(int value, int count) =>
    (((value & _mask32) << count) |
            ((value & _mask32) >> (32 - count))) &
    _mask32;

int _rotateRight32(int value, int count) =>
    (((value & _mask32) >> count) |
            ((value & _mask32) << (32 - count))) &
    _mask32;

int _readUint32Le(List<int> bytes, int offset) =>
    (bytes[offset] & 0xff) |
    ((bytes[offset + 1] & 0xff) << 8) |
    ((bytes[offset + 2] & 0xff) << 16) |
    ((bytes[offset + 3] & 0xff) << 24);

int _readUint32Be(List<int> bytes, int offset) =>
    ((bytes[offset] & 0xff) << 24) |
    ((bytes[offset + 1] & 0xff) << 16) |
    ((bytes[offset + 2] & 0xff) << 8) |
    (bytes[offset + 3] & 0xff);

void _writeUint32Le(Uint8List bytes, int offset, int value) {
  bytes[offset] = value;
  bytes[offset + 1] = value >> 8;
  bytes[offset + 2] = value >> 16;
  bytes[offset + 3] = value >> 24;
}

void _writeUint32Be(Uint8List bytes, int offset, int value) {
  bytes[offset] = value >> 24;
  bytes[offset + 1] = value >> 16;
  bytes[offset + 2] = value >> 8;
  bytes[offset + 3] = value;
}

abstract class _HashWorkspace {
  void convert(List<int> input, int start, int end, Uint8List output,
      int outputOffset);
}

class _Md5 extends Hash {
  const _Md5();

  @override
  int get blockSize => 64;

  @override
  int get digestSize => 16;

  @override
  _HashWorkspace _createWorkspace() => _Md5Workspace();
}

class _Md5Workspace extends _HashWorkspace {
  static const List<int> _shifts = <int>[
    7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22,
    5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20,
    4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23,
    6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21,
  ];

  static const List<int> _constants = <int>[
    0xd76aa478, 0xe8c7b756, 0x242070db, 0xc1bdceee,
    0xf57c0faf, 0x4787c62a, 0xa8304613, 0xfd469501,
    0x698098d8, 0x8b44f7af, 0xffff5bb1, 0x895cd7be,
    0x6b901122, 0xfd987193, 0xa679438e, 0x49b40821,
    0xf61e2562, 0xc040b340, 0x265e5a51, 0xe9b6c7aa,
    0xd62f105d, 0x02441453, 0xd8a1e681, 0xe7d3fbc8,
    0x21e1cde6, 0xc33707d6, 0xf4d50d87, 0x455a14ed,
    0xa9e3e905, 0xfcefa3f8, 0x676f02d9, 0x8d2a4c8a,
    0xfffa3942, 0x8771f681, 0x6d9d6122, 0xfde5380c,
    0xa4beea44, 0x4bdecfa9, 0xf6bb4b60, 0xbebfbc70,
    0x289b7ec6, 0xeaa127fa, 0xd4ef3085, 0x04881d05,
    0xd9d4d039, 0xe6db99e5, 0x1fa27cf8, 0xc4ac5665,
    0xf4292244, 0x432aff97, 0xab9423a7, 0xfc93a039,
    0x655b59c3, 0x8f0ccc92, 0xffeff47d, 0x85845dd1,
    0x6fa87e4f, 0xfe2ce6e0, 0xa3014314, 0x4e0811a1,
    0xf7537e82, 0xbd3af235, 0x2ad7d2bb, 0xeb86d391,
  ];

  final Uint32List _words = Uint32List(16);
  final Uint8List _tail = Uint8List(128);
  int _a = 0;
  int _b = 0;
  int _c = 0;
  int _d = 0;

  @override
  void convert(List<int> input, int start, int end, Uint8List output,
      int outputOffset) {
    RangeError.checkValidRange(start, end, input.length);
    RangeError.checkValidRange(
        outputOffset, outputOffset + 16, output.length);

    _a = 0x67452301;
    _b = 0xefcdab89;
    _c = 0x98badcfe;
    _d = 0x10325476;

    final length = end - start;
    final fullEnd = end - (length & 63);
    var offset = start;
    while (offset < fullEnd) {
      _processBlock(input, offset);
      offset += 64;
    }

    final remaining = end - offset;
    _tail.fillRange(0, _tail.length, 0);
    for (var i = 0; i < remaining; i++) {
      _tail[i] = input[offset + i];
    }
    _tail[remaining] = 0x80;
    final paddedLength = remaining < 56 ? 64 : 128;
    final bitLength = length * 8;
    _writeUint32Le(_tail, paddedLength - 8, bitLength & _mask32);
    _writeUint32Le(
        _tail, paddedLength - 4, (bitLength ~/ 0x100000000) & _mask32);
    _processBlock(_tail, 0);
    if (paddedLength == 128) _processBlock(_tail, 64);

    _writeUint32Le(output, outputOffset, _a);
    _writeUint32Le(output, outputOffset + 4, _b);
    _writeUint32Le(output, outputOffset + 8, _c);
    _writeUint32Le(output, outputOffset + 12, _d);
  }

  void _processBlock(List<int> input, int offset) {
    for (var i = 0; i < 16; i++) {
      _words[i] = _readUint32Le(input, offset + (i << 2));
    }

    var a = _a;
    var b = _b;
    var c = _c;
    var d = _d;
    for (var i = 0; i < 64; i++) {
      int f;
      int wordIndex;
      if (i < 16) {
        f = (b & c) | ((~b) & d);
        wordIndex = i;
      } else if (i < 32) {
        f = (d & b) | ((~d) & c);
        wordIndex = ((5 * i) + 1) & 15;
      } else if (i < 48) {
        f = b ^ c ^ d;
        wordIndex = ((3 * i) + 5) & 15;
      } else {
        f = c ^ (b | (~d));
        wordIndex = (7 * i) & 15;
      }

      final previousD = d;
      d = c;
      c = b;
      final sum = (a + f + _constants[i] + _words[wordIndex]) & _mask32;
      b = (b + _rotateLeft32(sum, _shifts[i])) & _mask32;
      a = previousD;
    }

    _a = (_a + a) & _mask32;
    _b = (_b + b) & _mask32;
    _c = (_c + c) & _mask32;
    _d = (_d + d) & _mask32;
  }
}

class _Sha1 extends Hash {
  const _Sha1();

  @override
  int get blockSize => 64;

  @override
  int get digestSize => 20;

  @override
  _HashWorkspace _createWorkspace() => _Sha1Workspace();
}

class _Sha1Workspace extends _HashWorkspace {
  final Uint32List _words = Uint32List(16);
  final Uint8List _tail = Uint8List(128);
  int _h0 = 0;
  int _h1 = 0;
  int _h2 = 0;
  int _h3 = 0;
  int _h4 = 0;

  @override
  void convert(List<int> input, int start, int end, Uint8List output,
      int outputOffset) {
    RangeError.checkValidRange(start, end, input.length);
    RangeError.checkValidRange(
        outputOffset, outputOffset + 20, output.length);

    _h0 = 0x67452301;
    _h1 = 0xefcdab89;
    _h2 = 0x98badcfe;
    _h3 = 0x10325476;
    _h4 = 0xc3d2e1f0;

    final length = end - start;
    final fullEnd = end - (length & 63);
    var offset = start;
    while (offset < fullEnd) {
      _processBlock(input, offset);
      offset += 64;
    }

    final remaining = end - offset;
    _tail.fillRange(0, _tail.length, 0);
    for (var i = 0; i < remaining; i++) {
      _tail[i] = input[offset + i];
    }
    _tail[remaining] = 0x80;
    final paddedLength = remaining < 56 ? 64 : 128;
    final bitLength = length * 8;
    _writeUint32Be(
        _tail, paddedLength - 8, (bitLength ~/ 0x100000000) & _mask32);
    _writeUint32Be(_tail, paddedLength - 4, bitLength & _mask32);
    _processBlock(_tail, 0);
    if (paddedLength == 128) _processBlock(_tail, 64);

    _writeUint32Be(output, outputOffset, _h0);
    _writeUint32Be(output, outputOffset + 4, _h1);
    _writeUint32Be(output, outputOffset + 8, _h2);
    _writeUint32Be(output, outputOffset + 12, _h3);
    _writeUint32Be(output, outputOffset + 16, _h4);
  }

  void _processBlock(List<int> input, int offset) {
    for (var i = 0; i < 16; i++) {
      _words[i] = _readUint32Be(input, offset + (i << 2));
    }

    var a = _h0;
    var b = _h1;
    var c = _h2;
    var d = _h3;
    var e = _h4;
    for (var i = 0; i < 80; i++) {
      int word;
      if (i < 16) {
        word = _words[i];
      } else {
        word = _rotateLeft32(
            _words[(i - 3) & 15] ^
                _words[(i - 8) & 15] ^
                _words[(i - 14) & 15] ^
                _words[i & 15],
            1);
        _words[i & 15] = word;
      }

      int f;
      int k;
      if (i < 20) {
        f = (b & c) | ((~b) & d);
        k = 0x5a827999;
      } else if (i < 40) {
        f = b ^ c ^ d;
        k = 0x6ed9eba1;
      } else if (i < 60) {
        f = (b & c) | (b & d) | (c & d);
        k = 0x8f1bbcdc;
      } else {
        f = b ^ c ^ d;
        k = 0xca62c1d6;
      }

      final temp =
          (_rotateLeft32(a, 5) + f + e + k + word) & _mask32;
      e = d;
      d = c;
      c = _rotateLeft32(b, 30);
      b = a;
      a = temp;
    }

    _h0 = (_h0 + a) & _mask32;
    _h1 = (_h1 + b) & _mask32;
    _h2 = (_h2 + c) & _mask32;
    _h3 = (_h3 + d) & _mask32;
    _h4 = (_h4 + e) & _mask32;
  }
}

class _Sha256 extends Hash {
  const _Sha256();

  @override
  int get blockSize => 64;

  @override
  int get digestSize => 32;

  @override
  _HashWorkspace _createWorkspace() => _Sha256Workspace();
}

class _Sha256Workspace extends _HashWorkspace {
  static const List<int> _constants = <int>[
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5,
    0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
    0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
    0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
    0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
    0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
    0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
    0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
    0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
  ];

  final Uint32List _words = Uint32List(16);
  final Uint8List _tail = Uint8List(128);
  int _h0 = 0;
  int _h1 = 0;
  int _h2 = 0;
  int _h3 = 0;
  int _h4 = 0;
  int _h5 = 0;
  int _h6 = 0;
  int _h7 = 0;

  @override
  void convert(List<int> input, int start, int end, Uint8List output,
      int outputOffset) {
    RangeError.checkValidRange(start, end, input.length);
    RangeError.checkValidRange(
        outputOffset, outputOffset + 32, output.length);

    _h0 = 0x6a09e667;
    _h1 = 0xbb67ae85;
    _h2 = 0x3c6ef372;
    _h3 = 0xa54ff53a;
    _h4 = 0x510e527f;
    _h5 = 0x9b05688c;
    _h6 = 0x1f83d9ab;
    _h7 = 0x5be0cd19;

    final length = end - start;
    final fullEnd = end - (length & 63);
    var offset = start;
    while (offset < fullEnd) {
      _processBlock(input, offset);
      offset += 64;
    }

    final remaining = end - offset;
    _tail.fillRange(0, _tail.length, 0);
    for (var i = 0; i < remaining; i++) {
      _tail[i] = input[offset + i];
    }
    _tail[remaining] = 0x80;
    final paddedLength = remaining < 56 ? 64 : 128;
    final bitLength = length * 8;
    _writeUint32Be(
        _tail, paddedLength - 8, (bitLength ~/ 0x100000000) & _mask32);
    _writeUint32Be(_tail, paddedLength - 4, bitLength & _mask32);
    _processBlock(_tail, 0);
    if (paddedLength == 128) _processBlock(_tail, 64);

    _writeUint32Be(output, outputOffset, _h0);
    _writeUint32Be(output, outputOffset + 4, _h1);
    _writeUint32Be(output, outputOffset + 8, _h2);
    _writeUint32Be(output, outputOffset + 12, _h3);
    _writeUint32Be(output, outputOffset + 16, _h4);
    _writeUint32Be(output, outputOffset + 20, _h5);
    _writeUint32Be(output, outputOffset + 24, _h6);
    _writeUint32Be(output, outputOffset + 28, _h7);
  }

  void _processBlock(List<int> input, int offset) {
    for (var i = 0; i < 16; i++) {
      _words[i] = _readUint32Be(input, offset + (i << 2));
    }

    var a = _h0;
    var b = _h1;
    var c = _h2;
    var d = _h3;
    var e = _h4;
    var f = _h5;
    var g = _h6;
    var h = _h7;
    for (var i = 0; i < 64; i++) {
      int word;
      if (i < 16) {
        word = _words[i];
      } else {
        final w15 = _words[(i - 15) & 15];
        final s0 = _rotateRight32(w15, 7) ^
            _rotateRight32(w15, 18) ^
            (w15 >> 3);
        final w2 = _words[(i - 2) & 15];
        final s1 = _rotateRight32(w2, 17) ^
            _rotateRight32(w2, 19) ^
            (w2 >> 10);
        word = (s1 +
                _words[(i - 7) & 15] +
                s0 +
                _words[i & 15]) &
            _mask32;
        _words[i & 15] = word;
      }

      final sum1 = _rotateRight32(e, 6) ^
          _rotateRight32(e, 11) ^
          _rotateRight32(e, 25);
      final choose = (e & f) ^ ((~e) & g);
      final temp1 = (h + sum1 + choose + _constants[i] + word) & _mask32;
      final sum0 = _rotateRight32(a, 2) ^
          _rotateRight32(a, 13) ^
          _rotateRight32(a, 22);
      final majority = (a & b) ^ (a & c) ^ (b & c);
      final temp2 = (sum0 + majority) & _mask32;

      h = g;
      g = f;
      f = e;
      e = (d + temp1) & _mask32;
      d = c;
      c = b;
      b = a;
      a = (temp1 + temp2) & _mask32;
    }

    _h0 = (_h0 + a) & _mask32;
    _h1 = (_h1 + b) & _mask32;
    _h2 = (_h2 + c) & _mask32;
    _h3 = (_h3 + d) & _mask32;
    _h4 = (_h4 + e) & _mask32;
    _h5 = (_h5 + f) & _mask32;
    _h6 = (_h6 + g) & _mask32;
    _h7 = (_h7 + h) & _mask32;
  }
}

/// Computes HMAC without retaining mutable state between calls.
Uint8List hmac(Hash hash, List<int> key, List<int> message) {
  final output = Uint8List(hash.digestSize);
  final computer = _HmacComputer(hash, key, message.length);
  computer.convert(message, 0, message.length, output, 0);
  return output;
}

/// PBKDF2-HMAC with reusable work buffers inside the iteration loop.
///
/// The loop performs no list allocation; this matters for PostgreSQL SCRAM,
/// whose default iteration count is normally several thousand rounds.
Uint8List pbkdf2Hmac(Hash hash, List<int> password, List<int> salt,
    int iterations,
    {int? length}) {
  if (iterations <= 0) {
    throw ArgumentError.value(iterations, 'iterations', 'must be positive');
  }
  final outputLength = length ?? hash.digestSize;
  if (outputLength < 0) {
    throw ArgumentError.value(outputLength, 'length', 'must not be negative');
  }
  if (outputLength == 0) return Uint8List(0);

  final blockCount = (outputLength + hash.digestSize - 1) ~/ hash.digestSize;
  if (blockCount > _mask32) {
    throw ArgumentError.value(outputLength, 'length', 'is too large');
  }

  final saltBlock = Uint8List(salt.length + 4);
  for (var i = 0; i < salt.length; i++) {
    saltBlock[i] = salt[i];
  }
  final u = Uint8List(hash.digestSize);
  final resultBlock = Uint8List(hash.digestSize);
  final output = Uint8List(outputLength);
  final computer = _HmacComputer(
      hash, password, saltBlock.length > u.length ? saltBlock.length : u.length);

  var outputOffset = 0;
  for (var block = 1; block <= blockCount; block++) {
    final tail = salt.length;
    saltBlock[tail] = block >> 24;
    saltBlock[tail + 1] = block >> 16;
    saltBlock[tail + 2] = block >> 8;
    saltBlock[tail + 3] = block;

    computer.convert(saltBlock, 0, saltBlock.length, u, 0);
    resultBlock.setAll(0, u);
    for (var round = 1; round < iterations; round++) {
      // Safe in-place: the HMAC computer copies the message before writing u.
      computer.convert(u, 0, u.length, u, 0);
      for (var i = 0; i < resultBlock.length; i++) {
        resultBlock[i] ^= u[i];
      }
    }

    final remaining = outputLength - outputOffset;
    final take = remaining < resultBlock.length ? remaining : resultBlock.length;
    output.setRange(outputOffset, outputOffset + take, resultBlock);
    outputOffset += take;
  }
  return output;
}

class _HmacComputer {
  final Hash _hash;
  final _HashWorkspace _innerWorkspace;
  final _HashWorkspace _outerWorkspace;
  late final Uint8List _inner;
  late final Uint8List _outer;

  _HmacComputer(this._hash, List<int> key, int maximumMessageLength)
      : _innerWorkspace = _hash._createWorkspace(),
        _outerWorkspace = _hash._createWorkspace() {
    if (maximumMessageLength < 0) {
      throw ArgumentError.value(maximumMessageLength, 'maximumMessageLength');
    }
    _inner = Uint8List(_hash.blockSize + maximumMessageLength);
    _outer = Uint8List(_hash.blockSize + _hash.digestSize);

    final normalizedKey =
        key.length > _hash.blockSize ? _hash.convert(key) : key;
    _inner.fillRange(0, _hash.blockSize, 0x36);
    _outer.fillRange(0, _hash.blockSize, 0x5c);
    for (var i = 0; i < normalizedKey.length; i++) {
      _inner[i] ^= normalizedKey[i];
      _outer[i] ^= normalizedKey[i];
    }
  }

  void convert(List<int> message, int start, int end, Uint8List output,
      int outputOffset) {
    RangeError.checkValidRange(start, end, message.length);
    final length = end - start;
    if (length > _inner.length - _hash.blockSize) {
      throw RangeError.range(length, 0, _inner.length - _hash.blockSize);
    }
    for (var i = 0; i < length; i++) {
      _inner[_hash.blockSize + i] = message[start + i];
    }
    _innerWorkspace.convert(_inner, 0, _hash.blockSize + length, _outer,
        _hash.blockSize);
    _outerWorkspace.convert(
        _outer, 0, _outer.length, output, outputOffset);
  }
}

const String _hexAlphabet = '0123456789abcdef';

String hexEncode(List<int> bytes) =>
    String.fromCharCodes(hexEncodeAscii(bytes));

Uint8List hexEncodeAscii(List<int> bytes) {
  final output = Uint8List(bytes.length * 2);
  var target = 0;
  for (var i = 0; i < bytes.length; i++) {
    final byte = bytes[i] & 0xff;
    output[target++] = _hexAlphabet.codeUnitAt(byte >> 4);
    output[target++] = _hexAlphabet.codeUnitAt(byte & 0x0f);
  }
  return output;
}

Uint8List hexDecode(String input) {
  if (input.length.isOdd) {
    throw const FormatException('Hex input must contain an even number of digits.');
  }
  final output = Uint8List(input.length ~/ 2);
  var source = 0;
  for (var target = 0; target < output.length; target++) {
    final high = _hexNibble(input.codeUnitAt(source++));
    final low = _hexNibble(input.codeUnitAt(source++));
    if ((high | low) < 0) {
      throw FormatException('Invalid hexadecimal digit at offset ${source - 2}.');
    }
    output[target] = (high << 4) | low;
  }
  return output;
}

int _hexNibble(int codeUnit) {
  final decimal = codeUnit - 0x30;
  if (decimal >= 0 && decimal <= 9) return decimal;
  final lower = codeUnit | 0x20;
  final alpha = lower - 0x61;
  return alpha >= 0 && alpha <= 5 ? alpha + 10 : -1;
}

/// Length-independent comparison for authentication proofs.
bool constantTimeBytesEqual(List<int> left, List<int> right) {
  var difference = left.length ^ right.length;
  final length = left.length < right.length ? left.length : right.length;
  for (var i = 0; i < length; i++) {
    difference |= left[i] ^ right[i];
  }
  return difference == 0;
}
