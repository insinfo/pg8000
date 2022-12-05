import 'package:crypto/crypto.dart';

import '../auth.dart';
import '../sasl_authenticator.dart';
import 'scram_mechanism.dart';

class ScramAuthenticator extends SaslAuthenticator {
  ScramAuthenticator(
      String hashName, Hash hash, UsernamePasswordCredential credential)
      : super(ScramMechanism(
            hashName, hash, credential, CryptoStrengthStringGenerator()));
}
