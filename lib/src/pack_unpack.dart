import 'dart:typed_data';

import 'dependencies/buffer_isoos/buffer.dart';
import 'dependencies/buffer_terrier/raw_reader.dart';
import 'dependencies/buffer_terrier/raw_writer.dart';
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
/// Format |    C Type   |   Python type     | Standard size | code
///   h    |    short    |    integer        |   2            104
///   i    |    int      |    integer        | 	4             105
///   c    |   char      | bytes of length 1 | 1              99
///   b    | signed char | integer           | 1              98
///   q    | long long   | integer           | 8              113
///   Q    | unsigned long long |  integer   |  8             81
///
/// pega valores não-byte (por exemplo, inteiros, strings, etc.)
/// e os converte em bytes usando o formato especificado
List<int> pack(String fmt, List<int> vals) {
  //[105, 104, 99, 98, 113, 81]
  //['i', 'h', 'c', 'b', 'q', 'Q']
  final formats = fmt.codeUnits;

  if (vals.length != formats.length) {
    throw Exception(
        'pack expected ${formats.length} items for packing (got ${formats.length})');
  }
  final bytes = <int>[];

  for (var i = 0; i < formats.length; i++) {
    var f = formats[i];
    var val = vals[i];
    // c
    if (f == 99) {
      //assert(val >= 0 && val < 256);
      bytes.add(val);
    }
    // b
    else if (f == 98) {
      //assert(val >= 0 && val < 256);
      bytes.add(val);
    }
    //Int16 short 2 bytes h
    else if (f == 104) {
      //assert(val >= -32768 && val <= 32767);
      if (val < 0) val = 0x10000 + val;

      int a = (val >> 8) & 0x00FF;
      int b = val & 0x00FF;
      //checar ordem
      bytes.add(a);
      bytes.add(b);
    } //Int32 int 4 bytes i
    else if (f == 105) {
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
    } else {
      throw Exception('format unknow');
    }
  }

  return bytes;
}

/// pega valores não-byte (por exemplo, inteiros, strings, etc.)
/// e os converte em bytes usando o formato especificado
List<int> pack2(String fmt, List<int> vals) {
  //[105, 104, 99, 98, 113, 81]
  //['i', 'h', 'c', 'b', 'q', 'Q']
  final formats = fmt.codeUnits;

  if (vals.length != formats.length) {
    throw Exception(
        'pack expected ${formats.length} items for packing (got ${formats.length})');
  }
  var buffer = ByteDataWriter();

  for (var i = 0; i < formats.length; i++) {
    var f = formats[i];
    var val = vals[i];

    // c
    if (f == 99) {
      //assert(val >= 0 && val < 256);
      buffer.writeInt8(val);
    }
    // b
    else if (f == 98) {
      //assert(val >= 0 && val < 256);
      buffer.writeInt8(val);
    }
    //Int16 short 2 bytes h
    else if (f == 104) {
      buffer.writeInt16(val);
    } //Int32 int 4 bytes i
    else if (f == 105) {
      buffer.writeInt32(val);
    } else {
      throw Exception('format unknow');
    }
  }

  return buffer.toBytes();
}

/// o mais rapido nos benchmarks usando terrier RawWriter
List<int> pack3(String fmt, List<int> vals) {
  //[105, 104, 99, 98, 113, 81]
  //['i', 'h', 'c', 'b', 'q', 'Q']
  final formats = fmt.codeUnits;

  if (vals.length != formats.length) {
    throw Exception(
        'pack expected ${formats.length} items for packing (got ${formats.length})');
  }
  var buffer = RawWriter();

  for (var i = 0; i < formats.length; i++) {
    var f = formats[i];
    var val = vals[i];
    // c
    if (f == 99) {
      //assert(val >= 0 && val < 256);
      buffer.writeInt8(val);
    }
    // b
    else if (f == 98) {
      //assert(val >= 0 && val < 256);
      buffer.writeInt8(val);
    }
    //Int16 short 2 bytes h
    else if (f == 104) {
      buffer.writeInt16(val);
    } //Int32 int 4 bytes i
    else if (f == 105) {
      buffer.writeInt32(val);
    } else {
      throw Exception('format unknow');
    }
  }

  return buffer.toUint8List();
}

/// Format     C Type            Python type        Standard size
///   h        short              integer              2
///   i        int                integer            	 4
///   c       char                bytes of length 1    1
///   b     signed char           integer              1
///   q     long long             integer              8
///   Q     unsigned long long    integer              8
List<int> unpack(String fmt, List<int> bytes, [int offset = 0]) {
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

  //[105, 104, 99, 98, 113, 81]
  //['i', 'h', 'c', 'b', 'q', 'Q']
  final formats = fmt.codeUnits;

  for (var i = 0; i < formats.length; i++) {
    var f = formats[i];
    // c
    if (f == 99) {
      decodedNum.add(buffer.readByte());
    }
    // b
    else if (f == 98) {
      decodedNum.add(buffer.readByte());
    }
    //Int16 short 2 bytes h
    else if (f == 104) {
      decodedNum.add(buffer.readInt16());
    } //Int32 int 4 bytes i
    else if (f == 105) {
      decodedNum.add(buffer.readInt32());
    } else {
      throw Exception('format unknow');
    }
  }
  return decodedNum;
}

/// Format |    C Type   |   Python type     | Standard size
///   h    |    short    |    integer        |   2
///   i    |    int      |    integer        | 	4
///   c    |   char      | bytes of length 1 | 1
///   b    | signed char | integer           | 1
///   q    | long long   | integer           | 8
///   Q    | unsigned long long |  integer   |  8
List<int> unpack2(String fmt, List<int> bytes, [int offset = 0]) {
  var decodedNum = <int>[];
  var buffer = ByteDataReader();

  if (offset == 0) {
    buffer.add(bytes);
  } else if (offset > 0) {
    var bits = bytes.sublist(offset);
    buffer.add(bits);
  } else {
    throw Exception('offset < 0');
  }

  //[105, 104, 99, 98, 113, 81]
  //['i', 'h', 'c', 'b', 'q', 'Q']
  final formats = fmt.codeUnits;

  for (var i = 0; i < formats.length; i++) {
    var f = formats[i];
    // c
    if (f == 99) {
      decodedNum.add(buffer.readByte());
    }
    // b
    else if (f == 98) {
      decodedNum.add(buffer.readByte());
    }
    //Int16 short 2 bytes h
    else if (f == 104) {
      decodedNum.add(buffer.readInt16());
    } //Int32 int 4 bytes i
    else if (f == 105) {
      decodedNum.add(buffer.readInt32());
    } else {
      throw Exception('format unknow');
    }
  }
  return decodedNum;
}

/// o mais rapido nos benchmarks usando terrier RawReader
List<int> unpack3(String fmt, List<int> bytes, [int offset = 0]) {
  var decodedNum = <int>[];
  RawReader buffer;

  if (offset == 0) {
    buffer = RawReader.withBytes(bytes);
  } else if (offset > 0) {
    var bits = bytes.sublist(offset);
    buffer = RawReader.withBytes(bits);
  } else {
    throw Exception('offset < 0');
  }

  //[105, 104, 99, 98, 113, 81]
  //['i', 'h', 'c', 'b', 'q', 'Q']
  final formats = fmt.codeUnits;

  for (var i = 0; i < formats.length; i++) {
    var f = formats[i];
    // c
    if (f == 99) {
      decodedNum.add(buffer.readByte());
    }
    // b
    else if (f == 98) {
      decodedNum.add(buffer.readByte());
    }
    //Int16 short 2 bytes h
    else if (f == 104) {
      decodedNum.add(buffer.readInt16());
    } //Int32 int 4 bytes i
    else if (f == 105) {
      decodedNum.add(buffer.readInt32());
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
  //return unpack('i', bytes, offset);
  var buffer = Buffer();
  if (offset == 0) {
    buffer.append(bytes);
  } else if (offset > 0) {
    var bits = bytes.sublist(offset);
    buffer.append(bits);
  } else {
    throw Exception('offset < 0');
  }

  return [buffer.readInt32()];
}

List<int> i_pack_fast(
  int val, [
  Endian endian = Endian.big,
]) {
  ByteData data = ByteData(4);
  data.setInt32(0, val, endian);
  return data.buffer.asUint8List();

//   Uint8List int32bytes(int value) =>
//     Uint8List(4)..buffer.asInt32List()[0] = value;

// Uint8List int32BigEndianBytes(int value) =>
//     Uint8List(4)..buffer.asByteData().setInt32(0, value, Endian.big);
}

List<int> i_unpack_fast(List<int> bytes, [int offset = 0]) {
  //return unpack('i', bytes, offset);
  ByteData data = ByteData.view(Uint8List.fromList(bytes).buffer);
  return [data.getInt32(0)];
}

/// write Int16 short 2 bytes
/// Minimum value of Int16: -32768
/// Maximum value of Int16: 32767
List<int> h_pack(
  int val, [
  Endian endian = Endian.big,
]) {
  //return pack('h', [val]);
  ByteData data = ByteData(2);
  data.setInt16(0, val, endian);
  return data.buffer.asUint8List();
}

/// read Int16 short 2 bytes
List<int> h_unpack(List<int> bytes, [int offset = 0]) {
  return unpack('h', bytes, offset);
}

/// write 2 Int32
List<int> ii_pack(int val1, int val2) {
  return pack('ii', [val1, val2]);
}

/// read 2 Int32
List<int> ii_unpack(List<int> bytes, [int offset = 0]) {
  return unpack('ii', bytes, offset);
}

/// write Int32 Int16 | Int32 Int16 | Int32 Int16
List<int> ihihih_pack(
    int val1, int val2, int val3, int val4, int val5, int val6) {
  return pack('ihihih', [val1, val2, val3, val4, val5, val6]);
}

/// read Int32 Int16 | Int32 Int16 | Int32 Int16
List<int> ihihih_unpack(List<int> bytes, [int offset = 0]) {
  return unpack('ihihih', bytes, offset);
}

/// write one byte and Int32
List<int> ci_pack(int val1, int val2) {
  return pack('ci', [val1, val2]);
}

/// read one byte and Int32
List<int> ci_unpack(List<int> bytes, [int offset = 0]) {
  return unpack('ci', bytes, offset);
}

/// write one byte and Int16
List<int> bh_pack(int val1, int val2) {
  return pack('bh', [val1, val2]);
}

/// read  one byte and Int16
List<int> bh_unpack(List<int> bytes, [int offset = 0]) {
  return unpack('bh', bytes, offset);
}

/// write 4 byte
List<int> cccc_pack(int val1, int val2, int val3, int val4) {
  return pack('cccc', [val1, val2, val3, val4]);
}

/// read 4 byte
List<int> cccc_unpack(List<int> bytes, [int offset = 0]) {
  return unpack('cccc', bytes, offset);
}
