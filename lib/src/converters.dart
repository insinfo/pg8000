import 'dart:convert';
import 'dart:typed_data';

import 'package:convert/convert.dart';

import 'dependencies/charcode/ascii.dart';
import 'exceptions.dart';
import 'server_info.dart';
import 'utils/utils.dart';

//enum
// class ArrayState {
//   static const InString = 1;
//   static const InEscape = 2;
//   static const InValue = 3;
//   static const Out = 4;
// }

enum ArrayState { InString, InEscape, InValue, Out }

class TypeConverter {
  static const ANY_ARRAY = 2277;
  static const BIGINT_ARRAY = 1016;
  static const BOOLEAN = 16;
  static const BOOLEAN_ARRAY = 1000;
  static const BYTES = 17;
  static const BYTES_ARRAY = 1001;
  static const CHAR = 1042;
  static const CHAR_ARRAY = 1014;
  static const CIDR = 650;
  static const CIDR_ARRAY = 651;
  static const CSTRING = 2275;
  static const CSTRING_ARRAY = 1263;
  static const DATE = 1082;
  static const DATE_ARRAY = 1182;
  static const FLOAT = 701;
// double precision
  static const FLOAT8 = 701;
  static const FLOAT_ARRAY = 1022;
  static const INET = 869;
  static const INET_ARRAY = 1041;
  static const INT2VECTOR = 22;

//Work only for smaller precision
  static const NUMERIC = 1700;

// INT2 smallint
  static const SMALLINT = 21;
// _INT4
  static const INTEGER = 23;
// _INT8
  static const BIGINT = 20;

// real
  static const FLOAT4 = 700;
  static const REAL = 700;

  static const REAL_ARRAY = 1021;
  static const INTEGER_ARRAY = 1007;
  static const INTERVAL = 1186;
  static const INTERVAL_ARRAY = 1187;
  static const OID = 26;
  static const JSON = 114;
  static const JSON_ARRAY = 199;
  static const JSONB = 3802;
  static const JSONB_ARRAY = 3807;
  static const MACADDR = 829;
  static const MONEY = 790;
  static const MONEY_ARRAY = 791;
  static const NAME = 19;
  static const NAME_ARRAY = 1003;

  static const NUMERIC_ARRAY = 1231;
  static const NULLTYPE = -1;
//const OID = 26;
  static const POINT = 600;

  static const SMALLINT_ARRAY = 1005;
  static const SMALLINT_VECTOR = 22;
//const STRING = 1043;
  static const TEXT = 25;
  static const TEXT_ARRAY = 1009;
  static const TIME = 1083;
  static const TIME_ARRAY = 1183;
  static const TIMESTAMP = 1114;
  static const TIMESTAMP_ARRAY = 1115;
  //_TIMESTAMPZ
  static const TIMESTAMPTZ = 1184;
  static const TIMESTAMPTZ_ARRAY = 1185;
  static const UNKNOWN = 705;
  static const UUID_TYPE = 2950;
  static const UUID_ARRAY = 2951;
  static const VARCHAR = 1043;
  static const VARCHAR_ARRAY = 1015;
  static const XID = 28;

// ** é o símbolo para exponenciação. em python
  static const MIN_INT2 = -32768; //-(2**15);
  static const MAX_INT2 = 32768; //2**15;
  static const MIN_INT4 = -2147483648; //-(2**31)
  static const MAX_INT4 = 2147483648; // 2**31;
  static const MIN_INT8 = -9223372036854775808; //-(2**63)
// 2**63; -1 para ser compativel com dart => pow(2, 63) - 1
  static const MAX_INT8 = 9223372036854775807;

  String connectionName;
  ServerInfo serverInfo;
  String textCharset;

  TypeConverter(this.textCharset, this.serverInfo, {this.connectionName});

  bool bool_in(data) {
    return data == "t";
  }

  /// Dart bool para postgresql
  String bool_out(data) {
    //return "true" if v else "false"
    return data != 0 && data != null && data != false && data != ''
        ? "true"
        : "false";

    // return data == 't'
    //     ? true
    //     : data == 'f'
    //         ? false
    //         : null;
  }

  /// encode bytearray Uint8List to posgresql
  dynamic bytes_out(v) {
    return "\\x" + hex.encode(v);
    // v.hex();
  }

  dynamic pg_interval_out(v) {
    return String.fromCharCodes(v);
  }

  /// Dart String para postgresql
  dynamic string_out(v) {
    return v;
  }

  dynamic null_out(v) {
    return null;
  }

  /// Dart double para postgresql
  dynamic float_out(n) {
    if (n.isNaN) return "'nan'";
    if (n == double.infinity) return "'infinity'";
    if (n == double.negativeInfinity) return "'-infinity'";
    return n.toString();
  }

  // numeric_out
  /// dart num type to postgresql numeric type
  dynamic numeric_out(n) {
    if (n.isNaN) return "'nan'";
    if (n == double.infinity) return "'infinity'";
    if (n == double.negativeInfinity) return "'-infinity'";
    return n.toString();
  }

  /// Dart int para postgresql
  dynamic int_out(n) {
    //return int.parse(v);
    if (n.isNaN) return "'nan'";
    return n.toString();
  }

  array_out(List ar) {
    var result = [];
    for (var v in ar) {
      var val;
      if (v == null) {
        val = "NULL";
      } else if (v is Map) {
        val = array_string_escape(json_out(v));
      } else if (v is Uint8List) {
        val = '"\\${bytes_out(v)}"';
      } else if (v is List) {
        val = array_out(v);
      } else if (v is String) {
        val = array_string_escape(v);
      } else {
        val = makeParam(v);
      }

      result.add(val);
    }

    return "{" + result.join(',') + "}";
  }

  dynamic array_string_escape(String inputString) {
    var v = inputString.split('');

    var cs = [];
    var val;
    for (var c in v) {
      if (c == "\\") {
        cs.add("\\");
      } else if (c == '"') {
        cs.add("\\");
      }
      cs.add(c);
    }
    val = cs.join();
    if (val.length == 0 ||
        val == "NULL" ||
        Utils.stringContainsSpace(val) ||
        Utils.stringContains(val, ["{", "}", ",", "\\"])) {
      val = '"$val"';
    }
    return val;
  }

  /// Dart date para postgresql
  String date_out(DateTime v) {
    return v.toIso8601String();
  }

  /// Dart DateTime para postgresql
  String datetime_out(DateTime v) {
    // if v.tzinfo is None:
    //     return v.isoformat()
    // else:
    //     return v.astimezone(Timezone.utc).isoformat();
    return v.toIso8601String();
  }

  /// Dart enum para postgresql
  dynamic enum_out(v) {
    return v.value;
  }

  /// Dart Map para postgresql
  String json_out(v) {
    return jsonEncode(v);
  }

  List<T> _parse_array<T>(String data, Function adapter) {
    var state = ArrayState.Out;
    var stack = [[]];
    var val = [];
    var dataSplit = data.split('');

    for (var c in dataSplit) {
      if (state == ArrayState.InValue) {
        if (['}', ','].contains(c)) {
          var value = val.join();
          stack[stack.length - 1].add(value == "NULL" ? null : adapter(value));
          state = ArrayState.Out;
        } else {
          val.add(c);
        }
      }

      if (state == ArrayState.Out) {
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
          state = ArrayState.InString;
        } else {
          val = [c];
          state = ArrayState.InValue;
        }
      } else if (state == ArrayState.InString) {
        if (c == '"') {
          stack[stack.length - 1].add(adapter(val.join()));
          state = ArrayState.Out;
        } else if (c == "\\") {
          state = ArrayState.InEscape;
        } else {
          val.add(c);
        }
      } else if (state == ArrayState.InEscape) {
        val.add(c);
        state = ArrayState.InString;
      }
    }
    var result = stack[0][0];
    if (result is List) {
      return result.map((e) => e as T).toList();
    }
    return null;
  }

  dynamic bool_array_in(dynamic data) {
    return _parse_array<bool>(data, bool_in);
  }

  dynamic bytes_array_in(dynamic data) {
    return _parse_array<Uint8List>(data, bytes_in);
  }

  /// Returns List<int>
  dynamic int_array_in(dynamic data) {
    return _parse_array<int>(data, int_in);
  }

  dynamic vector_in(String data) {
    var vals = data.split('');
    return vals.map((v) => int.parse(v)).toList();
    //return [int(v) for v in data.split()]
  }

  /// Returns List<String>
  List<String> string_array_in(dynamic data) {
    return _parse_array<String>(data, string_in);
  }

  /// Returns List<String>
  List<String> interval_array_in(dynamic data) {
    return _parse_array<String>(data, string_in);
  }

  List<DateTime> date_array_in(dynamic data) {
    return _parse_array<DateTime>(data, date_in);
  }

  List<double> float_array_in(dynamic data) {
    return _parse_array<double>(data, float_in);
  }

  List<double> numeric_array_in(dynamic data) {
    return _parse_array<double>(data, float_in);
  }

  List<Map> json_array_in(dynamic data) {
    return _parse_array<Map>(data, json_in);
  }

  List<String> time_array_in(dynamic data) {
    return _parse_array<String>(data, string_in);
  }

  List<DateTime> timestamp_array_in(dynamic data) {
    return _parse_array<DateTime>(data, timestamp_in);
  }

  List<DateTime> timestamptz_array_in(dynamic data) {
    return _parse_array<DateTime>(data, timestamptz_in);
  }

  /// [data] String
  /// return List<int>
  dynamic bytes_in(data) {
    //if (data is String) {
    final bytesString = data.substring(2); //data.replaceFirst("\\x", '');
    return hex.decode(bytesString);
    //}
    //return data;
  }

  dynamic string_in(data) {
    return data;
  }

  dynamic int_in(data) {
    return int.parse(data);
  }

  dynamic float_in(data) {
    return double.parse(data);
  }

  dynamic numeric_in(data) {
    // return Decimal(data);
    return double.parse(data);
  }

//decode _JSON and _JSONB
  dynamic json_in(data) {
    return jsonDecode(data);
  }

  dynamic date_in(value) {
    if (value == 'infinity' || value == '-infinity') {
      throw PostgresqlException(
        'A timestamp value "$value", cannot be represented '
        'as a Dart object.',
      );
    }

    // var formattedValue = value;
    // formattedValue = formattedValue + 'T00:00:00Z';
    return DateTime.parse(value);
  }

  /// convert de posgresql timestamp para dart DateTime
  dynamic timestamp_in(value) {
    if (value == 'infinity' || value == '-infinity') {
      throw PostgresqlException(
        'A timestamp value "$value", cannot be represented '
        'as a Dart object.',
      );
    }
    //var pattern =  value.contain('.') ? "%Y-%m-%d %H:%M:%S.%f" : "%Y-%m-%d %H:%M:%S";
    var formattedValue = value;

    return DateTime.parse(formattedValue);
  }

  /// Decodes [value] into a [DateTime] instance.
  ///
  /// Note: it will convert it to local time (via [DateTime.toLocal])
  ///
  /// TODO use https://github.com/AKushWarrior/instant/tree/master/lib/src
  DateTime timestamptz_in(value) {
    // print('timestamptz_in $value ${serverInfo.timeZone}');
// Built in Dart dates can either be local time or utc. Which means that the
    // the postgresql timezone parameter for the connection must be either set
    // to UTC, or the local time of the server on which the client is running.
    // This restriction could be relaxed by using a more advanced date library
    // capable of creating DateTimes for a non-local time zone.

    if (value == 'infinity' || value == '-infinity') {
      throw PostgresqlException(
        'A timestamp value "$value", cannot be represented '
        'as a Dart object.',
      );
    }
    //if infinity values are required, rewrite the sql query to cast
    //the value to a string, i.e. your_column::text.
    var formattedValue = value;
    //formattedValue += 'Z';
    // PG will return the timestamp in the connection's timezone. The resulting DateTime.parse will handle accordingly.

    //var pattern = value.contain('.') ? "%Y-%m-%d %H:%M:%S.%f%z" : "%Y-%m-%d %H:%M:%S%z";
    return DateTime.parse(formattedValue);
  }

  dynamic interval_in(value) {
    return value.toString();
  }

  String encodeNumber(num n) {
    if (n.isNaN) return "'nan'";
    if (n == double.infinity) return "'infinity'";
    if (n == double.negativeInfinity) return "'-infinity'";
    return n.toString();
  }

  /// Map of characters to escape.
  static const escapes = const {
    "'": r"\'",
    "\r": r"\r",
    "\n": r"\n",
    r"\": r"\\",
    "\t": r"\t",
    "\b": r"\b",
    "\f": r"\f",
    "\u0000": "",
  };

  /// Characters that will be escapes.
  static const escapePattern = r"'\r\n\\\t\b\f\u0000"; //detect unsupported null
  final _escapeRegExp = RegExp("[$escapePattern]");

  String encodeString(String s) {
    if (s == null) return ' null ';
    var escaped = s.replaceAllMapped(_escapeRegExp, _escape);
    return " E'$escaped' ";
  }

  String _escape(Match m) => escapes[m[0]];

  String encodeArray(Iterable value, {String pgType}) {
    final buf = StringBuffer('array[');
    for (final v in value) {
      if (buf.length > 6) buf.write(',');
      buf.write(encodeValueDefault(v));
    }
    buf.write(']');
    if (pgType != null) buf..write('::')..write(pgType)..write('[]');
    return buf.toString();
  }

  String encodeDateTime(DateTime datetime, {bool isDateOnly: false}) {
    if (datetime == null) return 'null';

    var string = datetime.toIso8601String();

    if (isDateOnly) {
      string = string.split("T").first;
    } else {
      // ISO8601 UTC times already carry Z, but local times carry no timezone info
      // so this code will append it.
      if (!datetime.isUtc) {
        var timezoneHourOffset = datetime.timeZoneOffset.inHours;
        var timezoneMinuteOffset = datetime.timeZoneOffset.inMinutes % 60;

        // Note that the sign is stripped via abs() and appended later.
        var hourComponent = timezoneHourOffset.abs().toString().padLeft(2, "0");
        var minuteComponent =
            timezoneMinuteOffset.abs().toString().padLeft(2, "0");

        if (timezoneHourOffset >= 0) {
          hourComponent = "+${hourComponent}";
        } else {
          hourComponent = "-${hourComponent}";
        }

        var timezoneString = [hourComponent, minuteComponent].join(":");
        string = [string, timezoneString].join("");
      }
    }

    if (string.substring(0, 1) == "-") {
      // Postgresql uses a BC suffix for dates rather than the negative prefix returned by
      // dart's ISO8601 date string.
      string = string.substring(1) + " BC";
    } else if (string.substring(0, 1) == "+") {
      // Postgresql doesn't allow leading + signs for 6 digit dates. Strip it out.
      string = string.substring(1);
    }

    return "'${string}'";
  }

  String encodeJson(value) => encodeString(jsonEncode(value));

  // Unspecified type name. Use default type mapping.
  String encodeValueDefault(value) {
    if (value == null) return 'null';
    if (value is num) return encodeNumber(value);
    if (value is String) return encodeString(value);
    if (value is DateTime) return encodeDateTime(value, isDateOnly: false);
    if (value is bool || value is BigInt) return value.toString();
    if (value is Iterable) return encodeArray(value);
    return encodeJson(value);
  }

  PostgresqlException _error(String msg) {
    return PostgresqlException(msg, connectionName: connectionName);
  }

  /// convert from dart types to posgresql types
  /// based in python pg8000
  // TODO implement ip4_address type and money 
  // https://github.com/dart-protocol/ip/tree/master/lib/src/ip
  // https://pub.dev/packages/money
  encodeValuePg8000(dynamic value, Type type) {     
    if (value is DateTime) {
      return datetime_out(value);
    } else if (value is bool) {
      return bool_out(value);
    } else if (value is Uint8List) {
      return bytes_out(value);
    } else if (value is Map) {
      return json_out(value);
    } else if (value is double) {
      return float_out(value);
    } else if (value == null) {
      return null_out(value);
    } else if (value is String) {
      return string_out(value);
    } else if (value is int) {
      return int_out(value);
    } else if (value is BigInt) {
      return value.toString();
    } else if (value is num) {
      return numeric_out(value);
    } else if (value is Iterable) {      
      return array_out(value);
    } else if (value is List<Object>) {      
      return array_out(value);
    }else{
      return value.toString();
    }
    //Iterable<int>
    //if (value is Iterable) return encodeArray(value);
  }

  /// convert from dart types to posgresql types
  /// based on tomyeh implementation  
  // based on https://github.com/tomyeh/postgresql
  encodeValueTomyeh(dynamic value, String type) {
    if (type == null) return encodeValueDefault(value);
    if (value == null) return 'null';

    switch (type) {
      case 'text':
      case 'string':
        return encodeString(value.toString());

      case 'integer':
      case 'smallint':
      case 'bigint':
      case 'serial':
      case 'bigserial':
      case 'int':
        if (value is int || value is BigInt) return encodeNumber(value);
        break;

      case 'real':
      case 'double':
      case 'num':
      case 'number':
      case 'numeric':
      case 'decimal': //Work only for smaller precision
        if (value is num || value is BigInt) return encodeNumber(value);
        break;

      case 'boolean':
      case 'bool':
        if (value is bool) return value.toString();
        break;

      case 'timestamp':
      case 'timestamptz':
      case 'datetime':
        if (value is DateTime) return encodeDateTime(value, isDateOnly: false);
        break;

      case 'date':
        if (value is DateTime) return encodeDateTime(value, isDateOnly: true);
        break;

      case 'json':
      case 'jsonb':
        return encodeJson(value);

      case 'array':
        if (value is Iterable) return encodeArray(value);
        break;

      case 'bytea':
        if (value is Iterable<int>) return encodeBytea(value);
        break;

      default:
        if (type.endsWith('_array'))
          return encodeArray(value, pgType: type.substring(0, type.length - 6));

        final t = type.toLowerCase(); //backward compatible
        if (t != type)
          return encodeValueTomyeh(
            value,
            t,
          );

        throw _error('Unknown type name: $type.');
    }

    throw _error('Invalid runtime type and type modifier: '
        '${value.runtimeType} to $type.');
  }

// See http://www.postgresql.org/docs/9.0/static/sql-syntax-lexical.html#SQL-SYNTAX-STRINGS-ESCAPE
  String encodeBytea(Iterable<int> value) {
    //var b64String = ...;
    //return " decode('$b64String', 'base64') ";

    throw _error('bytea encoding not implemented. Pull requests welcome ;)');
  }

  /// decode PostgreSQL data type to dart
  /// based on python pg8000
  /// https://github.com/dart-protocol/ip/tree/master/lib/src/ip
  decodeValuePg8000(String value, int pgType) {
    //print('decodeValuePg8000 pgType: $pgType');
    switch (pgType) {
      case BIGINT:
        return int_in(value); // int8
      case BIGINT_ARRAY:
        return int_array_in(value); // int8[]
      case BOOLEAN:
        return bool_in(value); // bool
      case BOOLEAN_ARRAY:
        return bool_array_in(value); // bool[]
      case BYTES:
        return bytes_in(value); // bytea
      case BYTES_ARRAY:
        return bytes_array_in(value); // bytea[]
      case CHAR:
        return string_in(value); // char
      case CHAR_ARRAY:
        return string_array_in(value); // char[]
      case CIDR_ARRAY:
        //return cidr_array_in(value); // cidr[]
        return string_array_in(value);
      case CSTRING:
        return string_in(value); // cstring
      case CSTRING_ARRAY:
        return string_array_in(value); // cstring[]
      case DATE:
        return date_in(value); // date
      case DATE_ARRAY:
        return date_array_in(value); // date[]
        return value;
      case FLOAT:
        return float_in(value); // _FLOAT8 _FLOAT4 701
      case FLOAT_ARRAY:
        return float_array_in(value); // float8[]
        return value;
      case INET:
        // return inet_in(value); // inet
        return value;
      case INET_ARRAY:
        //return inet_array_in(value); // inet[]
        return string_array_in(value);
      case INTEGER:
        return int_in(value); //INT4 INT2 BIGINT
      case INTEGER_ARRAY:
        return int_array_in(value); // int4[]
      case JSON:
        return json_in(value); // json
      case JSON_ARRAY:
        return json_array_in(value); // json[]
        return value;
      case JSONB:
        return json_in(value); // jsonb
      case JSONB_ARRAY:
        return json_array_in(value); // jsonb[]
        return value;
      case MACADDR:
        return string_in(value); // MACADDR type
      case MONEY:
        return string_in(value); // money
      case MONEY_ARRAY:
        return string_array_in(value); // money[]
      case NAME:
        return string_in(value); // name
      case NAME_ARRAY:
        return string_array_in(value); // name[]
      case NUMERIC:
        return numeric_in(value); // numeric
      case NUMERIC_ARRAY:
        return numeric_array_in(value); // numeric[]
      case OID:
        return int_in(value); // oid
      case _OID_ARRAY:
        return int_array_in(value); // oid[]
      case INTERVAL:
        return interval_in(value); // interval
      case INTERVAL_ARRAY:
        return interval_array_in(value); // interval[]
      case REAL:
        return float_in(value); // float4
      case REAL_ARRAY:
        return float_array_in(value); // float4[]
      case SMALLINT:
        return int_in(value); // int2
      case SMALLINT_ARRAY:
        return int_array_in(value); // int2[]
      case SMALLINT_VECTOR:
        return vector_in(value); // int2vector
      case TEXT:
        return string_in(value); // text
      case TEXT_ARRAY:
        return string_array_in(value); // text[]
      case TIME:
        //return time_in(value); // time
        return string_in(value);
      case TIME_ARRAY:
        return time_array_in(value); // time[]
      case INTERVAL:
        return interval_in(value); // interval
      case TIMESTAMP:
        return timestamp_in(value); // timestamp
      case TIMESTAMP_ARRAY:
        return timestamp_array_in(value); // timestamp
      case TIMESTAMPTZ:
        return timestamptz_in(value); // timestamptz
      case TIMESTAMPTZ_ARRAY:
        return timestamptz_array_in(value); // timestamptz
      case UNKNOWN:
        return string_in(value); // unknown
      case UUID_ARRAY:
        return string_array_in(value); // uuid[]
      case UUID_TYPE:
        //return uuid_in(value); // uuid
        return string_in(value);
      case VARCHAR:
        return string_in(value); // varchar
      case VARCHAR_ARRAY:
        return string_array_in(value); // varchar[]
      case XID:
        return int_in(value); // xid
      case _VARBIT:
        return string_in(value); // varbit(10)
      case _VARBIT_ARRAY:
        return string_array_in(value); // varbit[]
      default:
        return value;
    }
  }

  /// based on https://github.com/tomyeh/postgresql
  ///
  decodeValueTomyeh(String value, int pgType) {
    switch (pgType) {
      case BOOLEAN:
        return value == 't';

      case SMALLINT: // smallint
      case INTEGER: // integer
      case BIGINT: // bigint
        return int.parse(value);

      case _FLOAT4: // real
      case _FLOAT8: // double precision
      case _NUMERIC: //Work only for smaller precision
        return double.parse(value);

      case TIMESTAMP:
      case TIMESTAMPTZ:
      case DATE:
        return decodeDateTime(value, pgType);

      case JSON:
      case JSONB:
        return jsonDecode(value);

      //TODO binary bytea

      // Not implemented yet - return a string.
      //case _MONEY:
      //case _TIMETZ:
      //case _TIME:
      //case _INTERVAL:

      default:
        final scalarType = _arrayTypes[pgType];
        if (scalarType != null) return decodeArray(value, scalarType);

        // Return a string for unknown types. The end user can parse this.
        return value;
    }
  }

  static const _arrayTypes = {
    _BIT_ARRAY: _BIT,
    _BOOL_ARRAY: _BOOL,
    _BPCHAR_ARRAY: _BPCHAR,
    _BYTEA_ARRAY: _BYTEA,
    _CHAR_ARRAY: _CHAR,
    _DATE_ARRAY: _DATE,
    _FLOAT4_ARRAY: _FLOAT4,
    _FLOAT8_ARRAY: _FLOAT8,
    _INT2_ARRAY: _INT2,
    _INT4_ARRAY: _INT4,
    _INT8_ARRAY: _INT8,
    _INTERVAL_ARRAY: _INTERVAL,
    _JSON_ARRAY: _JSON,
    _JSONB_ARRAY: _JSONB,
    _MONEY_ARRAY: _MONEY,
    _NAME_ARRAY: _NAME,
    _NUMERIC_ARRAY: _NUMERIC,
    _OID_ARRAY: _OID,
    _TEXT_ARRAY: _TEXT,
    _TIME_ARRAY: _TIME,
    _TIMESTAMP_ARRAY: _TIMESTAMP,
    _TIMESTAMPZ_ARRAY: _TIMESTAMPZ,
    _TIMETZ_ARRAY: _TIMETZ,
    _UUID_ARRAY: _UUID,
    _VARBIT_ARRAY: _VARBIT,
    _VARCHAR_ARRAY: _VARCHAR,
    _XML_ARRAY: _XML,
  };

  /// Constants for postgresql datatypes
  /// Ref: https://jdbc.postgresql.org/development/privateapi/constant-values.html
  /// Also: select typname, typcategory, typelem, typarray from pg_type where typname LIKE '%int%'
  static const int _BIT = 1560,
      _BIT_ARRAY = 1561,
      _BOOL = 16,
      _BOOL_ARRAY = 1000,
      //  _BOX = 603,
      _BPCHAR = 1042,
      _BPCHAR_ARRAY = 1014,
      _BYTEA = 17,
      _BYTEA_ARRAY = 1001,
      _CHAR = 18,
      _CHAR_ARRAY = 1002,
      _DATE = 1082,
      _DATE_ARRAY = 1182,
      _FLOAT4 = 700,
      _FLOAT4_ARRAY = 1021,
      _FLOAT8 = 701,
      _FLOAT8_ARRAY = 1022,
      _INT2 = 21,
      _INT2_ARRAY = 1005,
      _INT4 = 23,
      _INT4_ARRAY = 1007,
      _INT8 = 20,
      _INT8_ARRAY = 1016,
      _INTERVAL = 1186,
      _INTERVAL_ARRAY = 1187,
      _JSON = 114,
      _JSON_ARRAY = 199,
      _JSONB = 3802,
      _JSONB_ARRAY = 3807,
      _MONEY = 790,
      _MONEY_ARRAY = 791,
      _NAME = 19,
      _NAME_ARRAY = 1003,
      _NUMERIC = 1700,
      _NUMERIC_ARRAY = 1231,
      _OID = 26,
      _OID_ARRAY = 1028,
      //_POINT = 600,
      _TEXT = 25,
      _TEXT_ARRAY = 1009,
      _TIME = 1083,
      _TIME_ARRAY = 1183,
      _TIMESTAMP = 1114,
      _TIMESTAMP_ARRAY = 1115,
      _TIMESTAMPZ = 1184,
      _TIMESTAMPZ_ARRAY = 1185,
      _TIMETZ = 1266,
      _TIMETZ_ARRAY = 1270,
      //_UNSPECIFIED = 0,
      _UUID = 2950,
      _UUID_ARRAY = 2951,
      _VARBIT = 1562,
      _VARBIT_ARRAY = 1563,
      _VARCHAR = 1043,
      _VARCHAR_ARRAY = 1015,
      //_VOID = 2278,
      _XML = 142,
      _XML_ARRAY = 143;

  /// Decodes [value] into a [DateTime] instance.
  ///
  /// Note: it will convert it to local time (via [DateTime.toLocal])
  DateTime decodeDateTime(String value, int pgType) {
    // Built in Dart dates can either be local time or utc. Which means that the
    // the postgresql timezone parameter for the connection must be either set
    // to UTC, or the local time of the server on which the client is running.
    // This restriction could be relaxed by using a more advanced date library
    // capable of creating DateTimes for a non-local time zone.

    if (value == 'infinity' || value == '-infinity')
      throw _error('A timestamp value "$value", cannot be represented '
          'as a Dart object.');
    //if infinity values are required, rewrite the sql query to cast
    //the value to a string, i.e. your_column::text.

    var formattedValue = value;

    // Postgresql uses a BC suffix rather than a negative prefix as in ISO8601.
    if (value.endsWith(' BC'))
      formattedValue = '-' + value.substring(0, value.length - 3);

    if (pgType == TIMESTAMP) {
      formattedValue += 'Z';
    } else if (pgType == TIMESTAMPTZ) {
      // PG will return the timestamp in the connection's timezone. The resulting DateTime.parse will handle accordingly.
    } else if (pgType == DATE) {
      formattedValue = formattedValue + 'T00:00:00Z';
    }

    return DateTime.parse(formattedValue).toLocal();
  }

  /// Decodes an array value, [value]. Each item of it is [pgType].
  decodeArray(String value, int pgType) {
    final len = value.length - 2;
    assert(
        value.codeUnitAt(0) == $lbrace && value.codeUnitAt(len + 1) == $rbrace);
    if (len <= 0) return [];
    value = value.substring(1, len + 1);

    if (const {TEXT, CHAR, VARCHAR, NAME}.contains(pgType)) {
      final result = [];
      for (int i = 0; i < len; ++i) {
        if (value.codeUnitAt(i) == $quot) {
          final buf = <int>[];
          for (;;) {
            final cc = value.codeUnitAt(++i);
            if (cc == $quot) {
              result.add(new String.fromCharCodes(buf));
              ++i;
              assert(i >= len || value.codeUnitAt(i) == $comma);
              break;
            }
            if (cc == $backslash)
              buf.add(value.codeUnitAt(++i));
            else
              buf.add(cc);
          }
        } else {
          //not quoted
          for (int j = i;; ++j) {
            if (j >= len || value.codeUnitAt(j) == $comma) {
              final v = value.substring(i, j);
              result.add(v == 'NULL' ? null : v);
              i = j;
              break;
            }
          }
        }
      }
      return result;
    }

    if (const {JSON, JSONB}.contains(pgType)) return jsonDecode('[$value]');

    final result = [];
    for (final v in value.split(','))
      result.add(v == 'NULL' ? null : decodeValueTomyeh(v, pgType));
    return result;
  }

  dynamic makeParam(dynamic value) {
    try {
      //func = PY_TYPES[value.runtimeType];
      //return encodeValue(value, null);
      return encodeValuePg8000(value, value.runtimeType);
    } catch (e) {
      print('make_param error $e');
    }

    return string_out(value);
  }

  /// convert prepared params from dart types to posgresql types
  List makeParams(List values) {
    var results = [];
    for (var v in values) {      
      results.add(makeParam(v));
    }
    return results;
  }

  /// PostgreSQL encodings:
  /// https://www.postgresql.org/docs/current/multibyte.html
  ///
  /// Python encodings:
  /// https://docs.python.org/3/library/codecs.html
  ///
  /// Commented out encodings don't require a name change between PostgreSQL and
  /// Python.  If the py side is None, then the encoding isn't supported.
  final PG_PY_ENCODINGS = <String, dynamic>{
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
      case 'iso-8859–1':
        return latin1.decode(codeUnits);
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
      case 'iso-8859–1':
        return latin1.encode(codeUnits);
      default:
        return utf8.encode(codeUnits);
    }
  }
}
