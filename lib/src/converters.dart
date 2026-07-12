import 'dart:convert';
import 'dart:typed_data';

import 'server_info.dart';
import 'utils/pg_datetime_codec.dart';
import 'utils/utils.dart';
import 'utils/crypto.dart';
import 'utils/windows_1252.dart';

enum ArrayState { inString, inEscape, inValue, out }

class TypeConverter {
  static const anyArray = 2277;
  static const bigintArray = 1016;
  static const boolean = 16;
  static const booleanArray = 1000;
  static const bytes = 17;
  static const bytesArray = 1001;
  static const char = 1042;
  static const charArray = 1014;
  static const cidr = 650;
  static const cidrArray = 651;
  static const cstring = 2275;
  static const cstringArray = 1263;
  static const date = 1082;
  static const dateArray = 1182;
  static const float = 701;
// double precision
  static const float8 = 701;
  static const floatArray = 1022;
  static const inet = 869;
  static const inetArray = 1041;
  static const int2vector = 22;

//Work only for smaller precision
  static const numeric = 1700;

// INT2 smallint
  static const smallint = 21;
// _INT4
  static const integer = 23;
// _INT8
  static const bigint = 20;

// real
  static const float4 = 700;
  static const real = 700;

  static const realArray = 1021;
  static const integerArray = 1007;
  static const interval = 1186;
  static const intervalArray = 1187;
  static const oid = 26;
  static const json = 114;
  static const jsonArray = 199;
  static const jsonb = 3802;
  static const jsonbArray = 3807;
  static const macaddr = 829;
  static const money = 790;
  static const moneyArray = 791;
  static const name = 19;
  static const nameArray = 1003;

  static const numericArray = 1231;
  static const nulltype = -1;
//const oid = 26;
  static const point = 600;

  static const smallintArray = 1005;
  static const smallintVector = 22;
//const STRING = 1043;
  static const text = 25;
  static const textArray = 1009;
  static const time = 1083;
  static const timeArray = 1183;
  static const timestamp = 1114;
  static const timestampArray = 1115;
  //_TIMESTAMPZ
  static const timestamptz = 1184;
  static const timestamptzArray = 1185;
  static const unknown = 705;
  static const uuidType = 2950;
  static const uuidArray = 2951;
  static const varchar = 1043;
  static const varcharArray = 1015;
  static const xid = 28;

// ** é o símbolo para exponenciação. em python
  static const minInt2 = -32768; //-(2**15);
  static const maxInt2 = 32768; //2**15;
  static const minInt4 = -2147483648; //-(2**31)
  static const maxInt4 = 2147483648; // 2**31;
  static const minInt8 = -9223372036854775808; //-(2**63)
// 2**63; -1 para ser compativel com dart => pow(2, 63) - 1
  static const maxInt8 = 9223372036854775807;

  String? connectionName;
  ServerInfo serverInfo;
  String textCharset;

  TypeConverter(this.textCharset, this.serverInfo, {this.connectionName});

  bool boolIn(data) {
    return data == "t";
  }

  /// Dart bool to postgresql
  String boolOut(data) {
    return data != 0 && data != null && data != false && data != ''
        ? "true"
        : "false";
  }

  /// encode bytearray Uint8List to posgresql
  dynamic bytesOut(v) {
    return '\\x${hexEncode(v)}';
  }

  /// Dart String to postgresql
  dynamic stringOut(v) {
    return v;
  }

  dynamic nullOut(v) {
    return null;
  }

  /// Dart double to postgresql
  dynamic floatOut(n) {
    if (n.isNaN) return "'nan'";
    if (n == double.infinity) return "'infinity'";
    if (n == double.negativeInfinity) return "'-infinity'";
    return n.toString();
  }

  // numericOut
  /// dart num type to postgresql numeric type
  dynamic numericOut(n) {
    if (n.isNaN) return "'nan'";
    if (n == double.infinity) return "'infinity'";
    if (n == double.negativeInfinity) return "'-infinity'";
    return n.toString();
  }

  /// Dart int to postgresql
  dynamic intOut(n) {
    if (n.isNaN) return "'nan'";
    return n.toString();
  }

  arrayOut(Iterable ar) {
    var result = [];
    for (var v in ar) {
      Object? val;
      if (v == null) {
        val = "NULL";
      } else if (v is Map) {
        val = arrayStringEscape(jsonOut(v));
      } else if (v is Uint8List) {
        val = '"\\${bytesOut(v)}"';
      } else if (v is Iterable) {
        val = arrayOut(v);
      } else if (v is String) {
        val = arrayStringEscape(v);
      } else {
        val = makeParam(v);
      }

      result.add(val);
    }

    return '{${result.join(',')}}';
  }

  dynamic arrayStringEscape(String inputString) {
    var v = inputString.split('');

    var cs = [];
    String val;
    for (var c in v) {
      if (c == "\\") {
        cs.add("\\");
      } else if (c == '"') {
        cs.add("\\");
      }
      cs.add(c);
    }
    val = cs.join();
    if (val.isEmpty ||
        val == "NULL" ||
        Utils.stringContainsSpace(val) ||
        Utils.stringContains(val, ["{", "}", ",", "\\"])) {
      val = '"$val"';
    }
    return val;
  }

  /// Dart DateTime to postgresql
  String dateTimeOut(DateTime v) {
    return v.toIso8601String();
  }

  /// Dart Map to postgresql
  String jsonOut(v) {
    return jsonEncode(v);
  }

  List<T?>? _parseArray<T>(String data, Function adapter) {
    var state = ArrayState.out;
    var stack = [[]];
    var val = [];
    var dataSplit = data.split('');

    for (var c in dataSplit) {
      if (state == ArrayState.inValue) {
        if (['}', ','].contains(c)) {
          var value = val.join();
          stack[stack.length - 1].add(value == "NULL" ? null : adapter(value));
          state = ArrayState.out;
        } else {
          val.add(c);
        }
      }

      if (state == ArrayState.out) {
        if (c == '{') {
          var a = [];
          stack[stack.length - 1].add(a);
          stack.add(a);
        } else if (c == '}') {
          stack.removeLast();
        } else if (c == ',') {
          //pass;
        } else if (c == '"') {
          val = [];
          state = ArrayState.inString;
        } else {
          val = [c];
          state = ArrayState.inValue;
        }
      } else if (state == ArrayState.inString) {
        if (c == '"') {
          stack[stack.length - 1].add(adapter(val.join()));
          state = ArrayState.out;
        } else if (c == "\\") {
          state = ArrayState.inEscape;
        } else {
          val.add(c);
        }
      } else if (state == ArrayState.inEscape) {
        val.add(c);
        state = ArrayState.inString;
      }
    }
    var result = stack[0][0];
    if (result is List) {
      return result.map((e) => e as T?).toList();
    }
    return null;
  }

  dynamic boolArrayIn(dynamic data) {
    return _parseArray<bool?>(data, boolIn);
  }

  dynamic bytesArrayIn(dynamic data) {
    return _parseArray<Uint8List?>(data, bytesIn);
  }

  /// Returns `List<int>`.
  dynamic intArrayIn(dynamic data) {
    return _parseArray<int?>(data, intIn);
  }

  dynamic vectorIn(String data) {
    var vals = data.split('');
    return vals.map((v) => int.parse(v)).toList();
  }

  /// Returns `List<String>`.
  List<String?>? stringArrayIn(dynamic data) {
    return _parseArray<String?>(data, stringIn);
  }

  /// Returns `List<String>`.
  List<String?>? intervalArrayIn(dynamic data) {
    return _parseArray<String?>(data, stringIn);
  }

  List<DateTime?>? dateArrayIn(dynamic data) {
    return _parseArray<DateTime?>(data, dateIn);
  }

  List<double?>? floatArrayIn(dynamic data) {
    return _parseArray<double?>(data, floatIn);
  }

  List<double?>? numericArrayIn(dynamic data) {
    return _parseArray<double?>(data, floatIn);
  }

  List<Map?>? jsonArrayIn(dynamic data) {
    return _parseArray<Map?>(data, jsonIn);
  }

  List<String?>? timeArrayIn(dynamic data) {
    return _parseArray<String?>(data, stringIn);
  }

  List<DateTime?>? timestampArrayIn(dynamic data) {
    return _parseArray<DateTime?>(data, timestampIn);
  }

  List<DateTime?>? timestampTzArrayIn(dynamic data) {
    return _parseArray<DateTime?>(data, timestampTzIn);
  }

  /// [data] String
  /// Returns `List<int>`.
  dynamic bytesIn(data) {
    final bytesString = data.substring(2); //data.replaceFirst("\\x", '');
    return hexDecode(bytesString);
  }

  dynamic stringIn(data) {
    return data;
  }

  dynamic intIn(data) {
    return int.parse(data);
  }

  dynamic floatIn(data) {
    return double.parse(data);
  }

  dynamic numericIn(data) {
    return double.parse(data);
  }

//decode _JSON and _JSONB
  dynamic jsonIn(data) {
    return jsonDecode(data);
  }

  DateTime? dateIn(String? value) => PgDateTimeCodec.decodeDateText(
        value,
        timeZone: serverInfo.timeZone,
      );

  /// convert de posgresql timestamp para dart DateTime
  DateTime? timestampIn(String? value) =>
      PgDateTimeCodec.decodeTimestampText(
        value,
        timeZone: serverInfo.timeZone,
      );

  /// Decodes PostgreSql text [value] into a [DateTime] instance.
  DateTime? timestampTzIn(String? value) =>
      PgDateTimeCodec.decodeTimestamptzText(
        value,
        timeZone: serverInfo.timeZone,
      );

  dynamic intervalIn(value) {
    return value.toString();
  }

  /// convert from dart types to posgresql types
  /// based in python pg8000
  encodeValuePg8000(dynamic value, Type type) {
    if (value is DateTime) {
      return dateTimeOut(value);
    } else if (value is bool) {
      return boolOut(value);
    } else if (value is Uint8List) {
      return bytesOut(value);
    } else if (value is Map) {
      return jsonOut(value);
    } else if (value is double) {
      return floatOut(value);
    } else if (value == null) {
      return nullOut(value);
    } else if (value is String) {
      return stringOut(value);
    } else if (value is int) {
      return intOut(value);
    } else if (value is BigInt) {
      return value.toString();
    } else if (value is num) {
      return numericOut(value);
    } else if (value is Iterable) {
      return arrayOut(value);
    } else {
      return value.toString();
    }
  }

  /// decode PostgreSQL data type to dart
  /// based on python pg8000
  /// https://github.com/dart-protocol/ip/tree/master/lib/src/ip
  decodeValuePg8000(String value, int pgType) {
    switch (pgType) {
      case bigint:
        return intIn(value); // int8
      case bigintArray:
        return intArrayIn(value); // int8[]
      case boolean:
        return boolIn(value); // bool
      case booleanArray:
        return boolArrayIn(value); // bool[]
      case bytes:
        return bytesIn(value); // bytea
      case bytesArray:
        return bytesArrayIn(value); // bytea[]
      case char:
        return stringIn(value); // char
      case charArray:
        return stringArrayIn(value); // char[]
      case cidrArray:
        return stringArrayIn(value);
      case cstring:
        return stringIn(value); // cstring
      case cstringArray:
        return stringArrayIn(value); // cstring[]
      case date:
        return dateIn(value); // date
      case dateArray:
        return dateArrayIn(value); // date[]

      case float:
        return floatIn(value); // _FLOAT8 _FLOAT4 701
      case floatArray:
        return floatArrayIn(value); // float8[]

      case inet:
        return value;
      case inetArray:
        return stringArrayIn(value);
      case integer:
        return intIn(value); //INT4 INT2 bigint
      case integerArray:
        return intArrayIn(value); // int4[]
      case json:
        return jsonIn(value); // json
      case jsonArray:
        return jsonArrayIn(value); // json[]

      case jsonb:
        return jsonIn(value); // jsonb
      case jsonbArray:
        return jsonArrayIn(value); // jsonb[]

      case macaddr:
        return stringIn(value); // macaddr type
      case money:
        return stringIn(value); // money
      case moneyArray:
        return stringArrayIn(value); // money[]
      case name:
        return stringIn(value); // name
      case nameArray:
        return stringArrayIn(value); // name[]
      case numeric:
        return numericIn(value); // numeric
      case numericArray:
        return numericArrayIn(value); // numeric[]
      case oid:
        return intIn(value); // oid
      case _oidArray:
        return intArrayIn(value); // oid[]
      case interval:
        return intervalIn(value); // interval
      case intervalArray:
        return intervalArrayIn(value); // interval[]
      case real:
        return floatIn(value); // float4
      case realArray:
        return floatArrayIn(value); // float4[]
      case smallint:
        return intIn(value); // int2
      case smallintArray:
        return intArrayIn(value); // int2[]
      case smallintVector:
        return vectorIn(value); // int2vector
      case text:
        return stringIn(value); // text
      case textArray:
        return stringArrayIn(value); // text[]
      case time:
        return stringIn(value);
      case timeArray:
        return timeArrayIn(value); // time[]
      case timestamp:
        return timestampIn(value); // timestamp
      case timestampArray:
        return timestampArrayIn(value); // timestamp
      case timestamptz:
        return timestampTzIn(value); // timestamptz
      case timestamptzArray:
        return timestampTzArrayIn(value); // timestamptz
      case unknown:
        return stringIn(value); // unknown
      case uuidArray:
        return stringArrayIn(value); // uuid[]
      case uuidType:
        return stringIn(value);
      case varchar:
        return stringIn(value); // varchar
      case varcharArray:
        return stringArrayIn(value); // varchar[]
      case xid:
        return intIn(value); // xid
      case _varbit:
        return stringIn(value); // varbit(10)
      case _varbitArray:
        return stringArrayIn(value); // varbit[]
      default:
        return value;
    }
  }

  static const int _oidArray = 1028, _varbit = 1562, _varbitArray = 1563;

  dynamic makeParam(dynamic value) {
    return encodeValuePg8000(value, value.runtimeType);
  }

  /// PostgreSQL encodings:
  /// https://www.postgresql.org/docs/current/multibyte.html
  ///
  /// Python encodings:
  /// https://docs.python.org/3/library/codecs.html
  ///
  /// Commented out encodings don't require a name change between PostgreSQL and
  /// Python.  If the py side is None, then the encoding isn't supported.
  final pgPyEncodings = <String, dynamic>{
    // Not supported:
    "mule_internal": null,
    "euc_tw": null,
    // Name fine as-is:
    // "euc_jp",
    // "euc_jis_2004",
    // "euc_kr",
    // "gb18030",
    // "gbk",
    // "johab",
    // "sjis",
    // "shift_jis_2004",
    // "uhc",
    // "utf8",
    // Different name:
    "euc_cn": "gb2312",
    "iso_8859_5": "is8859_5",
    "iso_8859_6": "is8859_6",
    "iso_8859_7": "is8859_7",
    "iso_8859_8": "is8859_8",
    "koi8": "koi8_r",
    "latin1": "latin1", //iso8859-1
    "latin2": "iso8859_2",
    "latin3": "iso8859_3",
    "latin4": "iso8859_4",
    "latin5": "iso8859_9",
    "latin6": "iso8859_10",
    "latin7": "iso8859_13",
    "latin8": "iso8859_14",
    "latin9": "iso8859_15",
    'sql_ascii': "ascii",
    "win866": "cp886",
    "win874": "cp874",
    "win1250": "cp1250",
    "win1251": "cp1251",
    "win1252": "cp1252",
    "win1253": "cp1253",
    "win1254": "cp1254",
    "win1255": "cp1255",
    "win1256": "cp1256",
    "win1257": "cp1257",
    "win1258": "cp1258",
    "unicode": "utf8", // Needed for Amazon Redshift
    "utf8": "utf8"
  };

  String charsetDecode(List<int> codeUnits, String encoding) {
    switch (encoding.toLowerCase()) {
      case 'utf8':
        return utf8.decode(codeUnits);
      case 'ascii':
        return ascii.decode(codeUnits);
      case 'latin1':
        return latin1.decode(codeUnits);
      case 'iso-8859-1':
        return latin1.decode(codeUnits);
      case 'win1252':
        return decodeWindows1252(codeUnits);
      default:
        return utf8.decode(codeUnits, allowMalformed: true);
    }
  }

  List<int> charsetEncode(String codeUnits, String encoding) {
    switch (encoding.toLowerCase()) {
      case 'utf8':
        return utf8.encode(codeUnits);
      case 'ascii':
        return ascii.encode(codeUnits);
      case 'latin1':
        return latin1.encode(codeUnits);
      case 'iso-8859-1':
        return latin1.encode(codeUnits);
      case 'win1252':
        return encodeWindows1252(codeUnits);
      default:
        return utf8.encode(codeUnits);
    }
  }
}
