import '../auth.dart';
import '../sasl_authenticator.dart';
import '../../../../utils/crypto.dart';
import 'scram_mechanism.dart';

class ScramAuthenticator extends SaslAuthenticator {
  ScramAuthenticator(
      String hashName, Hash hash, UsernamePasswordCredential credential)
      : super(ScramMechanism(
            hashName, hash, credential, CryptoStrengthStringGenerator()));
}
