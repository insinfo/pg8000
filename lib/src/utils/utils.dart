import 'crypto.dart';

class Utils {
  ///retorna o tamanho de uma lista
  static int len(List? list) {
    if (list == null) {
      return 0;
    }
    return list.length;
  }

  ///[bytes] is ascii bytes
  /// return ascii bytes of hex of md5
  static String md5HexString(List<int> bytes) {
    return hexEncode(md5.convert(bytes));
  }

  static bool stringContainsSpace(String val) {
    return val.contains(RegExp(r'\s'));
  }

  ///any(c in val for c in ("{", "}", ",", "\\"))
  /// Utils.stringContains(val, ["{", "}", ",", "\\"])
  static bool stringContains(String str, List<String> caracts) {
    bool isContain = false;

    for (var c in caracts) {
      if (str.contains(c)) {
        isContain = true;
        return isContain;
      }
    }

    return isContain;
  }

  static String itoa(int c) {
    try {
      return String.fromCharCodes([c]);
    } catch (ex) {
      return 'Invalid';
    }
  }
}
