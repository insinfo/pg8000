import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../sasl_scram_exception.dart';
import '../../utils/typed_data.dart';
import '../../utils/sasl.dart';
import '../auth.dart';
import '../sasl_authenticator.dart';
import 'steps/client_first.dart';

class ScramMechanism extends SaslMechanism {
  final UsernamePasswordCredential credential;
  final RandomStringGenerator randomStringGenerator;
  final String _name;
  final Hash hash;

  ScramMechanism(
      this._name, this.hash, this.credential, this.randomStringGenerator);

  @override
  SaslStep initialize({bool specifyUsername = false}) {
    if (credential.username == null) {
      throw SaslScramException('Username is empty on initialization');
    }

    String username;
    if (specifyUsername) {
      username = 'n=${prepUsername(credential.username)}';
    } else {
      username = 'n=*';
    }

    final r =
        randomStringGenerator.generate(SaslAuthenticator.DefaultNonceLength);

    final nonce = 'r=$r';

    final clientFirstMessageBare = '$username,$nonce';
    final clientFirstMessage = '$gs2Header$clientFirstMessageBare';

    return ClientFirst(coerceUint8List(utf8.encode(clientFirstMessage)), hash,
        credential, clientFirstMessageBare, r);
  }

  String prepUsername(String username) =>
      username.replaceAll('=', '=3D').replaceAll(',', '=2C');

  @override
  String get name => _name;
}
