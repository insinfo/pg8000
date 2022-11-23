import 'dart:convert';

import 'exceptions.dart';

const ANY_ARRAY = 2277;

const BIGINT_ARRAY = 1016;
const BOOLEAN = 16;
const BOOLEAN_ARRAY = 1000;
const BYTES = 17;
const BYTES_ARRAY = 1001;
const CHAR = 1042;
const CHAR_ARRAY = 1014;
const CIDR = 650;
const CIDR_ARRAY = 651;
const CSTRING = 2275;
const CSTRING_ARRAY = 1263;
const DATE = 1082;
const DATE_ARRAY = 1182;
const FLOAT = 701;
// double precision
const FLOAT8 = 701;
const FLOAT_ARRAY = 1022;
const INET = 869;
const INET_ARRAY = 1041;
const INT2VECTOR = 22;

//Work only for smaller precision
const NUMERIC = 1700;

// INT2 smallint
const SMALLINT = 21;
// _INT4
const INTEGER = 23;
// _INT8
const BIGINT = 20;

// real
const FLOAT4 = 700;
const REAL = 700;

const REAL_ARRAY = 1021;
const INTEGER_ARRAY = 1007;
const INTERVAL = 1186;
const INTERVAL_ARRAY = 1187;
const OID = 26;
const JSON = 114;
const JSON_ARRAY = 199;
const JSONB = 3802;
const JSONB_ARRAY = 3807;
const MACADDR = 829;
const MONEY = 790;
const MONEY_ARRAY = 791;
const NAME = 19;
const NAME_ARRAY = 1003;

const NUMERIC_ARRAY = 1231;
const NULLTYPE = -1;
//const OID = 26;
const POINT = 600;

const SMALLINT_ARRAY = 1005;
const SMALLINT_VECTOR = 22;
//const STRING = 1043;
const TEXT = 25;
const TEXT_ARRAY = 1009;
const TIME = 1083;
const TIME_ARRAY = 1183;
const TIMESTAMP = 1114;
const TIMESTAMP_ARRAY = 1115;
const TIMESTAMPTZ = 1184;
const TIMESTAMPTZ_ARRAY = 1185;
const UNKNOWN = 705;
const UUID_TYPE = 2950;
const UUID_ARRAY = 2951;
const VARCHAR = 1043;
const VARCHAR_ARRAY = 1015;
const XID = 28;

//** é o símbolo para exponenciação. em python
final MIN_INT2 = -32768; //-(2**15);
final MAX_INT2 = 32768; //2**15;
final MIN_INT4 = -2147483648; //-(2**31)
final MAX_INT4 = 2147483648; // 2**31;
final MIN_INT8 = -9223372036854775808; //-(2**63)
//2**63; -1 para ser compativel com dart => pow(2, 63) - 1
final MAX_INT8 = 9223372036854775807;

bool_in(data) {
  return data == "t";
}

/// Dart bool para postgresql
dynamic bool_out(data) {
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

dynamic pg_interval_out(v) {
  return String.fromCharCodes(v);
}

/// Dart String para postgresql
dynamic string_out(v) {
  return v;
}

/// Dart double para postgresql
dynamic float_out(v) {
  return v.toString();
}

/// Dart int para postgresql
dynamic int_out(v) {
  //return int.parse(v);
  return v.toString();
}

/// Dart date para postgresql
dynamic date_out(DateTime v) {
  return v.toIso8601String();
}

/// Dart DateTime para postgresql
dynamic datetime_out(DateTime v) {
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
dynamic json_out(v) {
  return jsonEncode(v);
}

//enum
class ArrayState {
  static const InString = 1;
  static const InEscape = 2;
  static const InValue = 3;
  static const Out = 4;
}

_parse_array(data, adapter) {
  var state = ArrayState.Out;
  var stack = [[]];
  var val = [];

  for (var c in data) {
    if (state == ArrayState.InValue) {
      if (["}", ","].contains(c)) {
        var value = val.join();
        stack[0].add(value == "NULL" ? null : adapter(value));
        state = ArrayState.Out;
      } else {
        val.add(c);
      }
    }
    if (state == ArrayState.Out) {
      if (c == "{") {
        var a = [];
        stack[0].add(a);
        stack.add(a);
      } else if (c == "}") {
        stack.removeLast();
      } else if (c == ",") {
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
        stack[0].add(adapter(val.join()));
        state = ArrayState.Out;
      } else if (c == "\\")
        state = ArrayState.InEscape;
      else {
        val.add(c);
      }
    } else if (state == ArrayState.InEscape) {
      val.add(c);
      state = ArrayState.InString;
    }
  }
  return stack[0][0];
}

dynamic _array_in(dynamic adapter) {
  var f = (data) => _parse_array(data, adapter);
  return f;
}

dynamic int_array_in() => _array_in(int);

dynamic string_in(data) {
  return data;
}

dynamic int_in(data) {
  return int.parse(data);
}

dynamic double_in(data) {
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

  var formattedValue = value;
  formattedValue = formattedValue + 'T00:00:00Z';
  return DateTime.parse(formattedValue);
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
  formattedValue += 'Z';
  return DateTime.parse(formattedValue);
}

/// Decodes [value] into a [DateTime] instance.
///
/// Note: it will convert it to local time (via [DateTime.toLocal])
dynamic timestamptz_in(value) {
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
  // PG will return the timestamp in the connection's timezone. The resulting DateTime.parse will handle accordingly.

  var pattern =
      value.contain('.') ? "%Y-%m-%d %H:%M:%S.%f%z" : "%Y-%m-%d %H:%M:%S%z";
  return DateTime.parse(formattedValue);
}

dynamic interval_in(value) {
  return value.toString();
}

final PY_PG = {
  DateTime: DATE,
  num: NUMERIC,
  // IPv4Address: INET,
  // IPv6Address: INET,
  // IPv4Network: INET,
  // IPv6Network: INET,
  // PGInterval: INTERVAL,
  // DateTime: TIME,
  Duration: INTERVAL,
  // String: UUID_TYPE,
  bool: BOOLEAN,
  // List: BYTES,
  Map: JSONB,
  double: FLOAT,
  null: NULLTYPE,
  // List: BYTES,
  String: TEXT,
};

/// mapeia tipos de dados Dart para funcões que convertem
/// este tipo para o tipo Postgresql adequado
final PY_TYPES = {
  //Date: date_out, // date
  DateTime: datetime_out,
  // Decimal: numeric_out,  // numeric
  //enum: enum_out,  // enum
  // IPv4Address: inet_out,  // inet
  // IPv6Address: inet_out,  // inet
  // IPv4Network: inet_out,  // inet
  // IPv6Network: inet_out,  // inet
  // PGInterval: interval_out,  // interval
  // Time: time_out,  // time
  // Timedelta: interval_out,  // interval
  // UUID: uuid_out,  // uuid
  bool: bool_out, // bool
  // bytearray: bytes_out,  // bytea
  Map: json_out, // jsonb
  double: float_out, // float8
  // type(None): null_out,  // null
  // bytes: bytes_out,  // bytea
  String: string_out, // unknown
  int: int_out,
  // list: array_out,
  // tuple: array_out,
};

/// mapeia tipos de dados PostgreSQL para funcões que convertem
/// este tipo para o dart tipo adequado
final PG_TYPES = <int, Function>{
  BIGINT: int_in, // int8
  BIGINT_ARRAY: int_array_in, // int8[]
  BOOLEAN: bool_in, // bool
  // BOOLEAN_ARRAY: bool_array_in, // bool[]
//  BYTES: bytes_in, // bytea
  // BYTES_ARRAY: bytes_array_in, // bytea[]
  CHAR: string_in, // char
  // CHAR_ARRAY: string_array_in, // char[]
  // CIDR_ARRAY: cidr_array_in, // cidr[]
  CSTRING: string_in, // cstring
//  CSTRING_ARRAY: string_array_in, // cstring[]
  DATE: date_in, // date
  // DATE_ARRAY: date_array_in, // date[]
  FLOAT: double_in, // _FLOAT8 _FLOAT4 701
  // FLOAT_ARRAY: float_array_in, // float8[]
  //INET: inet_in, // inet
  // INET_ARRAY: inet_array_in, // inet[]
  INTEGER: int_in, //INT4 INT2 BIGINT
  INTEGER_ARRAY: int_array_in, // int4[]
  JSON: json_in, // json
//  JSON_ARRAY: json_array_in, // json[]
  JSONB: json_in, // jsonb
//  JSONB_ARRAY: json_array_in, // jsonb[]
  MACADDR: string_in, // MACADDR type
  MONEY: string_in, // money
  // MONEY_ARRAY: string_array_in, // money[]
  NAME: string_in, // name
  // NAME_ARRAY: string_array_in, // name[]
  NUMERIC: numeric_in, // numeric
  // NUMERIC_ARRAY: numeric_array_in, // numeric[]
  OID: int_in, // oid
  // INTERVAL: interval_in, // interval
//  INTERVAL_ARRAY: interval_array_in, // interval[]
  REAL: double_in, // float4
  // REAL_ARRAY: float_array_in, // float4[]
  SMALLINT: int_in, // int2
  SMALLINT_ARRAY: int_array_in, // int2[]
  // SMALLINT_VECTOR: vector_in, // int2vector
  TEXT: string_in, // text
  // TEXT_ARRAY: string_array_in, // text[]
  // TIME: time_in, // time
  // TIME_ARRAY: time_array_in, // time[]
  INTERVAL: interval_in, // interval
  TIMESTAMP: timestamp_in, // timestamp
  //TIMESTAMP_ARRAY: timestamp_array_in, // timestamp
  TIMESTAMPTZ: timestamptz_in, // timestamptz
  // TIMESTAMPTZ_ARRAY: timestamptz_array_in, // timestamptz
  UNKNOWN: string_in, // unknown
//  UUID_ARRAY: uuid_array_in, // uuid[]
  // UUID_TYPE: uuid_in, // uuid
  VARCHAR: string_in, // varchar
//  VARCHAR_ARRAY: string_array_in, // varchar[]
  XID: int_in, // xid
};
