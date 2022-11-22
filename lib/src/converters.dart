const ANY_ARRAY = 2277;
const BIGINT = 20;
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
const FLOAT_ARRAY = 1022;
const INET = 869;
const INET_ARRAY = 1041;
const INT2VECTOR = 22;
const INTEGER = 23;
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
const NUMERIC = 1700;
const NUMERIC_ARRAY = 1231;
const NULLTYPE = -1;
//const OID = 26;
const POINT = 600;
const REAL = 700;
const REAL_ARRAY = 1021;
const SMALLINT = 21;
const SMALLINT_ARRAY = 1005;
const SMALLINT_VECTOR = 22;
const STRING = 1043;
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

bool_out(data) {
  //return "true" if v else "false"
  return data != 0 && data != null && data != false && data != ''
      ? "true"
      : "false";
}

//enum
class ArrayState {
  static const InString = 1;
  static const InEscape = 2;
  static const InValue = 3;
  static const Out = 4;
}

parse_array(data, adapter) {
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

final PY_PG = {
  DateTime: DATE,
  num: NUMERIC,
  // IPv4Address: INET,
  // IPv6Address: INET,
  // IPv4Network: INET,
  // IPv6Network: INET,
  // PGInterval: INTERVAL,
  DateTime: TIME,
  Duration: INTERVAL,
  String: UUID_TYPE,
  bool: BOOLEAN,
  List: BYTES,
  Map: JSONB,
  double: FLOAT,
  null: NULLTYPE,
  List: BYTES,
  String: TEXT,
};

final PY_TYPES = {
  // DateTime: date_out,  // date
  // DateTime: datetime_out,
  // Decimal: numeric_out,  // numeric
  // enum: enum_out,  // enum
  // IPv4Address: inet_out,  // inet
  // IPv6Address: inet_out,  // inet
  // IPv4Network: inet_out,  // inet
  // IPv6Network: inet_out,  // inet
  // PGInterval: interval_out,  // interval
  // Time: time_out,  // time
  // Timedelta: interval_out,  // interval
  // UUID: uuid_out,  // uuid
  // bool: bool_out,  // bool
  // bytearray: bytes_out,  // bytea
  // dict: json_out,  // jsonb
  // float: float_out,  // float8
  // type(None): null_out,  // null
  // bytes: bytes_out,  // bytea
  // str: string_out,  // unknown
  // int: int_out,
  // list: array_out,
  // tuple: array_out,
};
