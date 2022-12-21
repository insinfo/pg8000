/// PostgreTypes enum
class PostgreTypes {
  final int value;

  const PostgreTypes(this.value);

  /// bit_type  bit(1)
  static const PostgreTypes bit = const PostgreTypes(1560);
  static const PostgreTypes bool = const PostgreTypes(16);
  static const PostgreTypes box = const PostgreTypes(603);
  static const PostgreTypes bytea = const PostgreTypes(17);
  static const PostgreTypes char = const PostgreTypes(1042);
  static const PostgreTypes cidr = const PostgreTypes(650);
  static const PostgreTypes circle = const PostgreTypes(718);
  static const PostgreTypes date = const PostgreTypes(1082);
  static const PostgreTypes decimal = const PostgreTypes(1700);
  static const PostgreTypes float4 = const PostgreTypes(700);
  static const PostgreTypes float8 = const PostgreTypes(701);
  static const PostgreTypes inet = const PostgreTypes(869);

  /// SMALLINT 21
  static const PostgreTypes int2 = const PostgreTypes(21);

  /// INTEGER 23
  static const PostgreTypes int4 = const PostgreTypes(23);

  /// BIGINT 20
  static const PostgreTypes int8 = const PostgreTypes(20);
  static const PostgreTypes interval = const PostgreTypes(1186);
  static const PostgreTypes json = const PostgreTypes(114);
  static const PostgreTypes jsonb = const PostgreTypes(3802);
  static const PostgreTypes line = const PostgreTypes(628);
  static const PostgreTypes lseg = const PostgreTypes(601);
  static const PostgreTypes macaddr = const PostgreTypes(829);
  static const PostgreTypes money = const PostgreTypes(790);
  static const PostgreTypes path = const PostgreTypes(602);
  static const PostgreTypes polygon = const PostgreTypes(604);
  static const PostgreTypes point = const PostgreTypes(600);
  static const PostgreTypes text = const PostgreTypes(25);
  static const PostgreTypes time = const PostgreTypes(1083);
  static const PostgreTypes timestamp = const PostgreTypes(1114);
  static const PostgreTypes timestamptz = const PostgreTypes(1184);
  static const PostgreTypes timetz = const PostgreTypes(1266);

  /// Text Search Types
  /// https://www.postgresql.org/docs/current/datatype-textsearch.html
  static const PostgreTypes tsquery = const PostgreTypes(3615);
  static const PostgreTypes tsvector = const PostgreTypes(3614);

  /// UUID Type
  /// https://www.postgresql.org/docs/current/datatype-uuid.html
  static const PostgreTypes uuid = const PostgreTypes(2950);

  ///  Bit String Types
  /// https://www.postgresql.org/docs/current/datatype-bit.html#:~:text=bit%20varying%20data%20is%20of,length%20specification%20means%20unlimited%20length.
  static const PostgreTypes varbit = const PostgreTypes(1562);

  static const PostgreTypes varchar = const PostgreTypes(1043);
  static const PostgreTypes xml = const PostgreTypes(142);
  // extras
  /// XID Data Types
  static const PostgreTypes xid = const PostgreTypes(28);

  /// UNKNOWN = 705
  /// Identifies a not-yet-resolved type, e.g., of an undecorated string literal.
  /// Pseudo-Types https://www.postgresql.org/docs/current/datatype-pseudo.html
  static const PostgreTypes unknown = const PostgreTypes(705);

  /// SMALLINT_VECTOR 22
  static const PostgreTypes int2vector = const PostgreTypes(22);

  /// VARCHAR_ARRAY
  static const PostgreTypes varcharArray = const PostgreTypes(1015);

  /// SMALLINT_ARRAY | INT2_ARRAY 1005
  static const PostgreTypes int2Array = const PostgreTypes(1005);

  /// INTEGER_ARRAY | INT4_ARRAY 1007
  static const PostgreTypes int4Array = const PostgreTypes(1007);

  /// BIGINT_ARRAY | INT8_ARRAY 1016 int8[]
  static const PostgreTypes int8Array = const PostgreTypes(1016);

  /// BOOLEAN_ARRAY 1000 bool[]
  static const PostgreTypes booleanArray = const PostgreTypes(1000);

  /// BYTES_ARRAY | BYTEA_ARRAY 1001 bytea[]
  static const PostgreTypes byteaArray = const PostgreTypes(1001);

  /// _BPCHAR_ARRAY | CHAR_ARRAY 1014
  static const PostgreTypes charArray = const PostgreTypes(1014);

  /// DATE_ARRAY 1182
  static const PostgreTypes dateArray = const PostgreTypes(1182);

  /// FLOAT_ARRAY 1022
  static const PostgreTypes floatArray = const PostgreTypes(1022);

  /// JSON_ARRAY
  static const PostgreTypes jsonArray = const PostgreTypes(199);

  // JSONB_ARRAY
  static const PostgreTypes jsonbArray = const PostgreTypes(3807);

  /// MONEY_ARRAY
  static const PostgreTypes moneyArray = const PostgreTypes(791);

  /// NUMERIC_ARRAY 1231
  static const PostgreTypes numericArray = const PostgreTypes(1231);

  /// INTERVAL_ARRAY  1187
  static const PostgreTypes intervalArray = const PostgreTypes(1187);

  /// TEXT_ARRAY 1009
  static const PostgreTypes textArray = const PostgreTypes(1009);

  /// TIME_ARRAY 1183
  static const PostgreTypes timeArray = const PostgreTypes(1183);

  /// TIMESTAMP_ARRAY 1115
  static const PostgreTypes timestampArray = const PostgreTypes(1115);

  /// TIMESTAMPTZ_ARRAY 1185
  static const PostgreTypes timestamptzArray = const PostgreTypes(1185);

  /// UUID_ARRAY 2951 uuid[]
  static const PostgreTypes uuidArray = const PostgreTypes(2951);

  static const PostgreTypes int2vectorArray = const PostgreTypes(1006);

  static const PostgreTypes cidrArray = const PostgreTypes(651);

  /// INET_ARRAY  1041
  static const PostgreTypes inetArray = const PostgreTypes(1041);

  /// XML_ARRAY
  static const PostgreTypes xmlArray = const PostgreTypes(143);

  /// VARBIT_ARRAY  1563
  static const PostgreTypes varbitArray = const PostgreTypes(1563);

  /// OID Object Identifier Types - PostgreSQL
  /// Name	References	Description	Value Example
  /// oid	any	numeric object identifier	564182
  static const PostgreTypes oid = const PostgreTypes(26);
  static const PostgreTypes oidArray = const PostgreTypes(1028);
  //  _BIT_ARRAY = 1561,  ,_NAME_ARRAY = 1003,

  static String asString(PostgreTypes tp) {
    switch (tp.value) {
      case 1560:
        return 'bit';
      case 16:
        return 'bool';
      case 603:
        return 'box';
      case 17:
        return 'bytea';
      case 1042:
        return 'char';
      case 650:
        return 'cidr';
      case 718:
        return 'circle';
      case 1082:
        return 'date';
      case 1700:
        return 'decimal';
      case 700:
        return 'float4';
      case 701:
        return 'float8';
      case 869:
        return 'inet';
      case 21:
        return 'int2';
      case 23:
        return 'int4';
      case 20:
        return 'int8';
      case 1186:
        return 'interval';
      case 114:
        return 'json';
      case 3802:
        return 'jsonb';
      case 628:
        return 'line';
      case 601:
        return 'lseg';
      case 829:
        return 'macaddr';
      case 790:
        return 'money';
      case 602:
        return 'path';
      case 604:
        return 'polygon';
      case 600:
        return 'point';
      case 25:
        return 'text';
      case 1083:
        return 'time';
      case 1114:
        return 'timestamp';
      case 1184:
        return 'timestamptz';
      case 1266:
        return 'timetz';
      case 3615:
        return 'tsquery';
      case 3614:
        return 'tsvector';
      case 2950:
        return 'uuid';
      case 1562:
        return 'varbit';
      case 1043:
        return 'varchar';
      case 142:
        return 'xml';
      case 28:
        return 'xid';
      case 1015:
        return 'varcharArray';
      case 1007:
        return 'int4Array';
      case 1000:
        return 'booleanArray';
      case 1001:
        return 'byteaArray';
      case 1014:
        return 'charArray';
      case 1182:
        return 'dateArray';
      case 1022:
        return 'floatArray';
      case 199:
        return 'jsonArray';
      case 3807:
        return 'jsonbArray';
      case 791:
        return 'moneyArray';
      case 1231:
        return 'numericArray';
      case 1187:
        return 'intervalArray';
      case 1009:
        return 'textArray';
      case 1183:
        return 'timeArray';
      case 1115:
        return 'timestampArray';
      case 1185:
        return 'timestamptzArray';
      case 2951:
        return 'uuidArray';
      case 22:
        return 'int2vector';
      case 1006:
        return 'int2vectorArray';
      case 705:
        return 'unknown';
      case 1016:
        return 'int8Array';
      case 651:
        return 'cidrArray';
      case 1041:
        return 'inetArray';
      case 143:
        return 'xmlArray';
      case 1563:
        return 'varbitArray';
      case 1028:
        return 'oidArray';
      case 26:
        return 'oid';

      default:
        return 'unknow';
    }
  }

  @override
  String toString() {
    return 'PostgreTypes.${asString(this)}.$value';
  }
}
