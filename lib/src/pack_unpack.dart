import 'dart:typed_data';

import 'dependencies/buffer_isoos/buffer.dart';
import 'dependencies/buffer_terrier/raw_reader.dart';
import 'dependencies/buffer_terrier/raw_writer.dart';
import 'utils/buffer.dart';

// C# example https://stackoverflow.com/questions/28225303/equivalent-in-c-sharp-of-pythons-struct-pack-unpack/28418846#28418846
// java example https://stackoverflow.com/questions/29879009/how-to-convert-python-struct-unpack-to-java
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

/// using isoos ByteDataWriter
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

/// using terrier RawWriter
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

// Character code constants.
const int _b = 0x62, _c = 0x63, _h = 0x68, _i = 0x69, _q = 0x71;
const _formatSize = {
  _h: 2,
  _i: 4,
  _c: 1,
  _b: 1,
  _q: 8,
};

/// Format     C Type            Python type        Standard size
///   h        short              integer              2
///   i        int                integer              4
///   c        char               bytes of length 1    1
///   b        signed char        integer              1
///   q        long long          integer              8
/// from lrhn https://github.com/dart-lang/sdk/issues/50708
Uint8List packlrhn(String format, List<int> values) {
  if (format.length != values.length) {
    throw ArgumentError.value(values, "values",
        "Expected ${format.length} values for format: $format");
  }
  var bufferSize = 0;

  for (var i = 0; i < format.length; i++) {
    bufferSize += _formatSize[format.codeUnitAt(i)] ??
        (throw FormatException("Unknown format", format, i));
  }
  var buffer = ByteData(bufferSize);
  var cursor = 0;
  for (var i = 0; i < format.length; i++) {
    var f = format.codeUnitAt(i);
    var value = values[i];
    switch (f) {
      case _c:
        buffer.setUint8(cursor++, value);
        break;
      case _b:
        buffer.setInt8(cursor++, value);
        break;
      case _i:
        buffer.setInt32(cursor, value);
        cursor += 4;
        break;
      case _h:
        buffer.setInt16(cursor, value);
        cursor += 2;
        break;
      case _q: //writeInt64
        buffer.setInt64(cursor, value);
        cursor += 8;
        break;
      default:
        assert(false, "unreachable");
    }
  }
  assert(cursor == buffer.lengthInBytes); //length
  return Uint8List.sublistView(buffer);
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
/// esta é a versão mais lenta
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
  // return pack('c', [val]);
  return [val];
}

/// read Byte
List<int> c_unpack(List<int> bytes, [int offset = 0]) {
  //return unpack('c', bytes, offset);
  if (offset != 0) {
    return [bytes.first];
  }
  return [bytes.sublist(offset).first];
}

/// write Int32
/// pega valores não-byte (por exemplo, inteiros)
/// e os converte em bytes usando o formato "i" int de 4 bytes (Int32)
/// Minimum value of Int32: -2147483648
/// Maximum value of Int32: 2147483647
// List<int> i_pack(int val) {
//   //return pack('i', [val]);
//   var bytes = <int>[];
//   //assert(val >= -2147483648 && val <= 2147483647);
//   if (val < 0) val = 0x100000000 + val;
//   int a = (val >> 24) & 0x000000FF;
//   int b = (val >> 16) & 0x000000FF;
//   int c = (val >> 8) & 0x000000FF;
//   int d = val & 0x000000FF;
//   //checar ordem
//   bytes.add(a);
//   bytes.add(b);
//   bytes.add(c);
//   bytes.add(d);
//   return bytes;
// }

// /// read Int32
// /// Minimum value of Int32: -2147483648
// /// Maximum value of Int32: 2147483647
// List<int> i_unpack(List<int> bytes, [int offset = 0]) {
//   //return unpack('i', bytes, offset);
//   var buffer = Buffer();
//   if (offset == 0) {
//     buffer.append(bytes);
//   } else if (offset > 0) {
//     var bits = bytes.sublist(offset);
//     buffer.append(bits);
//   } else {
//     throw Exception('offset < 0');
//   }

//   return [buffer.readInt32()];
// }

List<int> i_pack(
  int val, [
  Endian endian = Endian.big,
]) {
  //return pack('i', [val]);
  // ByteData data = ByteData(4);
  // data.setInt32(0, val, endian);
  // return data.buffer.asUint8List();
  final result = Uint8List(4)..buffer.asByteData().setInt32(0, val, endian);
  return [...result]; //<int>[]..addAll(result);
}

List<int> i_unpack(List<int> bytes, [int offset = 0]) {
  //return unpack2('i', bytes, offset);
  // final data = ByteData.view(Uint8List.fromList(bytes).buffer);
  // return [data.getInt32(offset)];
  final result = Uint8List.fromList(bytes).buffer.asByteData().getInt32(offset);
  return [result];
}

/// write Int16 short 2 bytes
/// Minimum value of Int16: -32768
/// Maximum value of Int16: 32767
List<int> h_pack(
  int val, [
  Endian endian = Endian.big,
]) {
  //return pack('h', [val]);
  // ByteData data = ByteData(2);
  // data.setInt16(0, val, endian);
  // return data.buffer.asUint8List();
  final result = Uint8List(2)..buffer.asByteData().setInt16(0, val, endian);
  return [...result]; //<int>[]..addAll(result);
}

/// read Int16 short 2 bytes
List<int> h_unpack(List<int> bytes, [int offset = 0]) {
  //return unpack('h', bytes, offset);
  final result = Uint8List.fromList(bytes).buffer.asByteData().getInt16(offset);
  return [result];
}

/// write 2 Int32
List<int> ii_pack(
  int val1,
  int val2, [
  Endian endian = Endian.big,
]) {
  //return pack('ii', [val1, val2]);
  final list = Uint8List(8);
  final byteData = list.buffer.asByteData();
  byteData.setInt32(0, val1, endian);
  byteData.setInt32(4, val2, endian);
  return [...list]; //<int>[]..addAll(result);
}

/// read 2 Int32
List<int> ii_unpack(List<int> bytes, [int offset = 0]) {
  //return unpack3('ii', bytes, offset);
  final list = Uint8List.fromList(bytes);
  final byteData = list.buffer.asByteData();
  return [byteData.getInt32(offset), byteData.getInt32(offset + 4)];
}

/// write Int32 Int16 | Int32 Int16 | Int32 Int16
List<int> ihihih_pack(
    int val1, int val2, int val3, int val4, int val5, int val6,
    [Endian endian = Endian.big]) {
  //return pack('ihihih', [val1, val2, val3, val4, val5, val6]);

  final list = Uint8List(18);
  final byteData = list.buffer.asByteData();
  byteData.setInt32(0, val1, endian);
  byteData.setInt16(4, val2, endian);
  byteData.setInt32(6, val3, endian);
  byteData.setInt16(10, val4, endian);
  byteData.setInt32(12, val5, endian);
  byteData.setInt16(16, val6, endian);

  return [...list]; //<int>[]..addAll(result);
}

/// read Int32 Int16 | Int32 Int16 | Int32 Int16
List<int> ihihih_unpack(List<int> bytes, [int offset = 0]) {
  //return unpack('ihihih', bytes, offset);

  final list = Uint8List.fromList(bytes);
  final byteData = list.buffer.asByteData();
  return [
    byteData.getInt32(offset),
    byteData.getInt16(offset + 4),
    byteData.getInt32(offset + 6),
    byteData.getInt16(offset + 10),
    byteData.getInt32(offset + 12),
    byteData.getInt16(offset + 16),
  ];
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
