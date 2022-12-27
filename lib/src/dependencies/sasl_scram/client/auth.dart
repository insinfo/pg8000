import 'dart:math';
import 'dart:typed_data';

import 'sasl_authenticator.dart';

abstract class Authenticator {
  static String? name;

  Authenticator();

  Uint8List? handleMessage(
      SaslMessageType msgType, Uint8List bytesReceivedFromServer);
}

class UsernamePasswordCredential {
  UsernamePasswordCredential({this.username, this.password});

  String? username;
  String? password;
}

abstract class RandomStringGenerator {
  static const String allowedCharacters = '!"#\'\$%&()*+-./0123456789:;<=>?@'
      'ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~';

  String generate(int length);
}

class CryptoStrengthStringGenerator extends RandomStringGenerator {
  @override
  String generate(int length) {
    final random = Random.secure();
    final allowedCodeUnits = RandomStringGenerator.allowedCharacters.codeUnits;

    final max = allowedCodeUnits.length;

    final randomString = <int>[];

    for (var i = 0; i < length; ++i) {
      randomString.add(allowedCodeUnits.elementAt(random.nextInt(max)));
    }

    return String.fromCharCodes(randomString);
  }
}
