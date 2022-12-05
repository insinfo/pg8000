import 'dart:typed_data';

import 'utils/buffer.dart';

//TODO re-implement based on https://github.com/dart-protocol/raw/blob/master/lib/src/raw_value.dart
// https://github.com/dart-protocol/raw/blob/master/lib/src/raw_reader.dart
/// binary data pack and unpack
///
///
/// conversão Python to Dart
///        type Python          |  type dart
///  deque "Double-ended queue" |  Queue

/// https://docs.python.org/3/library/struct.html#format-characters
/// Format |    C Type   |   Python type     | Standard size
///   h    |    short    |    integer        |   2
///   i    |    int      |    integer        | 	4
///   c    |   char      | bytes of length 1 | 1
///   b    | signed char | integer           | 1
///   q    | long long   | integer           | 8
///   Q    | unsigned long long |  integer   |  8
///
/// pega valores não-byte (por exemplo, inteiros, strings, etc.)
/// e os converte em bytes usando o formato especificado
List<int> pack(String fmt, List<int> vals) {
  var formats = fmt.split('');

  if (vals.length != formats.length) {
    throw Exception(
        'pack expected ${formats.length} items for packing (got ${formats.length})');
  }
  var bytes = <int>[];

  for (var i = 0; i < formats.length; i++) {
    var f = formats[i];
    var val = vals[i];
    if (f == 'c' || f == 'b') {
      assert(val >= 0 && val < 256);
      bytes.add(val);
    } //Int16 short 2 bytes
    else if (f == 'h') {
      assert(val >= -32768 && val <= 32767);
      if (val < 0) val = 0x10000 + val;

      int a = (val >> 8) & 0x00FF;
      int b = val & 0x00FF;
      //checar ordem
      bytes.add(a);
      bytes.add(b);
    } //Int32 int 4 bytes
    else if (f == 'i') {
      assert(val >= -2147483648 && val <= 2147483647);

      if (val < 0) val = 0x100000000 + val;

      int a = (val >> 24) & 0x000000FF;
      int b = (val >> 16) & 0x000000FF;
      int c = (val >> 8) & 0x000000FF;
      int d = val & 0x000000FF;
      //checar ordem

      bytes.add(a);
      bytes.add(b);
      bytes.add(c);
      bytes.add(d);
    } else {
      throw Exception('format unknow');
    }
  }

  return bytes;
}

List<int> unpack(String fmt, List<int> bytes, [int offset = 0]) {
  // var sizes = [
  //   {'i': 4},
  //   {'c': 1},
  //   {'h': 2},
  //   {'b': 1},
  //   {'q': 8},
  //   {'Q': 8}
  // ];

  var decodedNum = <int>[];
  var buffer = Buffer();

  if (offset == 0) {
    buffer.append(bytes);
  } else if (offset > 0) {
    var bits = bytes.sublist(offset);
    buffer.append(bits);
  } else {
    throw Exception('offset < 0');
  }

  var formats = fmt.split('');
  for (var i = 0; i < formats.length; i++) {
    var f = formats[i];
    if (f == 'c' || f == 'b') {
      decodedNum.add(buffer.readByte());
    } else if (f == 'i') {
      decodedNum.add(buffer.readInt32());
    } else if (f == 'h') {
      decodedNum.add(buffer.readInt16());
    } else {
      throw Exception('format unknow');
    }
  }
  return decodedNum;
}

/// write char 1 byte
List<int> c_pack(int val) {
  return pack('c', [val]);
}

/// read Byte
List<int> c_unpack(List<int> bytes, [int offset = 0]) {
  return unpack('c', bytes, offset);
}

/// write Int32
/// pega valores não-byte (por exemplo, inteiros)
/// e os converte em bytes usando o formato "i" int de 4 bytes (Int32)
/// Minimum value of Int32: -2147483648
/// Maximum value of Int32: 2147483647
List<int> i_pack(int val) {
  //return pack('i', [val]);
  var bytes = <int>[];
  //assert(val >= -2147483648 && val <= 2147483647);

  if (val < 0) val = 0x100000000 + val;

  int a = (val >> 24) & 0x000000FF;
  int b = (val >> 16) & 0x000000FF;
  int c = (val >> 8) & 0x000000FF;
  int d = val & 0x000000FF;
  //checar ordem

  bytes.add(a);
  bytes.add(b);
  bytes.add(c);
  bytes.add(d);

  return bytes;
}

/// read Int32
/// Minimum value of Int32: -2147483648
/// Maximum value of Int32: 2147483647
List<int> i_unpack(List<int> bytes, [int offset = 0]) {
  return unpack('i', bytes, offset);
}

List<int> i_pack_fast(
  int val, [
  Endian endian = Endian.big,
]) {
  //return pack('i', [val]);
  ByteData data = ByteData(4);
  data.setInt32(0, val, endian);
  return data.buffer.asUint8List();
}

List<int> i_unpack_fast(List<int> bytes, [int offset = 0]) {
  //return unpack('i', bytes, offset);
  ByteData data = ByteData.view(Uint8List.fromList(bytes).buffer);
  return [data.getInt32(0)];
}

/// write Int16 short 2 bytes
/// Minimum value of Int16: -32768
/// Maximum value of Int16: 32767
List<int> h_pack(int val) {
  return pack('h', [val]);
}

/// read Int16 short 2 bytes
List<int> h_unpack(List<int> bytes, [int offset = 0]) {
  return unpack('h', bytes, offset);
}

/// write Int16 Int16 short 4 bytes
List<int> ii_pack(int val1, int val2) {
  return pack('ii', [val1, val2]);
}

/// read Int16 Int16 short 4 bytes
List<int> ii_unpack(List<int> bytes, [int offset = 0]) {
  return unpack('ii', bytes, offset);
}

List<int> ihihih_pack(int val1, int val2) {
  return pack('ihihih', [val1, val2]);
}

List<int> ihihih_unpack(List<int> bytes, [int offset = 0]) {
  return unpack('ihihih', bytes, offset);
}

List<int> ci_pack(int val1, int val2) {
  return pack('ci', [val1, val2]);
}

List<int> ci_unpack(List<int> bytes, [int offset = 0]) {
  return unpack('ci', bytes, offset);
}

List<int> bh_pack(int val1, int val2) {
  return pack('bh', [val1, val2]);
}

List<int> bh_unpack(List<int> bytes, [int offset = 0]) {
  return unpack('bh', bytes, offset);
}

List<int> cccc_pack(int val1, int val2, int val3, int val4) {
  return pack('cccc', [val1, val2, val3, val4]);
}

List<int> cccc_unpack(List<int> bytes, [int offset = 0]) {
  return unpack('cccc', bytes, offset);
}
