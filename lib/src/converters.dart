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
