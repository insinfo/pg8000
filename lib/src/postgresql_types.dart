/// PostgreTypes enum
class PostgreTypes {
  final int value;

  const PostgreTypes(this.value);

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
  static const PostgreTypes int2 = const PostgreTypes(21);
  static const PostgreTypes int4 = const PostgreTypes(23);
  static const PostgreTypes int8 = const PostgreTypes(20);
  static const PostgreTypes interval = const PostgreTypes(1186);
  static const PostgreTypes json = const PostgreTypes(114);
  static const PostgreTypes jsonb = const PostgreTypes(3802);
  static const PostgreTypes line = const PostgreTypes(628);
  static const PostgreTypes lseg = const PostgreTypes(601);
  static const PostgreTypes macaddr = const PostgreTypes(829);
  static const PostgreTypes money = const PostgreTypes(790);

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
      default:
        return 'unknow';
    }
  }

  @override
  String toString() {
    return 'PostgreTypes.${asString(this)}.$value';
  }
}
