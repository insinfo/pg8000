import 'package:dargres/src/dependencies/sasl_scram/sasl_scram.dart';

import 'abstract_example.dart';

/// For test data, see: https://github.com/brianc/node-postgres/blob/9d2c977ce9b13f8f3b024759b1deaec165564a6a/packages/pg/test/unit/client/sasl-scram-tests.js#L118
class SimpleScramSha256Example extends ScramExample {
  static final SimpleScramSha256Example _singleton =
      SimpleScramSha256Example._internal();

  factory SimpleScramSha256Example() {
    return _singleton;
  }

  SimpleScramSha256Example._internal();

  @override
  String user() => 'user';

  @override
  String password() => 'password';

  @override
  String clientNonce() => 'a';

  @override
  String clientFirstMessageWithoutGs2Header() =>
      'n=${user()},r=${clientNonce()}';

  @override
  String clientFirstMessage() =>
      'n,,${clientFirstMessageWithoutGs2Header()}';

  @override
  String serverSalt() => 'abcd';

  @override
  int serverIterations() => 1;

  @override
  String serverNonce() => 'b';

  @override
  String fullNonce() => clientNonce() + serverNonce();

  @override
  String serverFirstMessage() =>
      'r=${fullNonce()},s=${serverSalt()},i=${serverIterations()}';

  @override
  String gs2HeaderBase64() => 'biws';

  @override
  String clientFinalMessageWithoutProof() =>
      'c=${gs2HeaderBase64()},r=${fullNonce()}';

  @override
  String authMessage() =>
      '${clientFirstMessageWithoutGs2Header()},${serverFirstMessage()},${clientFinalMessageWithoutProof()}';

  @override
  String clientFinalMessageProof() =>
      'mU8grLfTjDrJer9ITsdHk0igMRDejG10EJPFbIBL3D0=';

  @override
  String clientFinalMessage() =>
      '${clientFinalMessageWithoutProof()},p=${clientFinalMessageProof()}';

  @override
  String serverFinalMessageProof() =>
      'jwt97IHWFn7FEqHykPTxsoQrKGOMXJl/PJyJ1JXTBKc=';

  @override
  String serverFinalMessage() => 'v=${serverFinalMessageProof()}';

  @override
  SaslAuthenticator getAuthenticator() => _ScramShaAuthenticatorTest();
}

class _StringGeneratorTest extends RandomStringGenerator {
  @override
  String generate(int length) {
    return SimpleScramSha256Example().clientNonce();
  }
}

class _ScramShaAuthenticatorTest extends SaslAuthenticator {
  _ScramShaAuthenticatorTest()
      : super(
          ScramMechanism(
            'SCRAM-SHA-256',
            sha256,
            UsernamePasswordCredential(
                username: SimpleScramSha256Example().user(),
                password: SimpleScramSha256Example().password()),
            _StringGeneratorTest(),
          ),
        );
}
