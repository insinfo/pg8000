import 'package:dargres/src/dependencies/sasl_scram/sasl_scram.dart';

import 'abstract_example.dart';

class ScramSha256Example extends ScramExample {
  static final ScramSha256Example _singleton = ScramSha256Example._internal();

  factory ScramSha256Example() {
    return _singleton;
  }

  ScramSha256Example._internal();

  @override
  String user() => 'dart';

  @override
  String password() => 'dart';

  @override
  String clientNonce() => 'JS4]nA5J?]AxA[>jjaJ+5H3g';

  @override
  String clientFirstMessageWithoutGs2Header() =>
      'n=${user()},r=${clientNonce()}';

  @override
  String clientFirstMessage() =>
      'n,,${clientFirstMessageWithoutGs2Header()}';

  @override
  String serverSalt() => 'abcdefgh';

  @override
  int serverIterations() => 1;

  @override
  String serverNonce() => '9djX!/t{sjHm)F/4B2tvu[i|';

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
      'k8RLpllFL3oHrpjMPpwUVslDK5wam7TkVbi1AmvnQS0=';

  @override
  String clientFinalMessage() =>
      '${clientFinalMessageWithoutProof()},p=${clientFinalMessageProof()}';

  @override
  String serverFinalMessageProof() =>
      '10ODfd6XRd0m4nJyYHP3u/Ib6peVFFY4piy2dbKv+bE=';

  @override
  String serverFinalMessage() => 'v=${serverFinalMessageProof()}';

  @override
  SaslAuthenticator getAuthenticator() => _ScramShaAuthenticatorTest();
}

class _StringGeneratorTest extends RandomStringGenerator {
  @override
  String generate(int length) {
    return ScramSha256Example().clientNonce();
  }
}

class _ScramShaAuthenticatorTest extends SaslAuthenticator {
  _ScramShaAuthenticatorTest()
      : super(
          ScramMechanism(
            'SCRAM-SHA-256',
            sha256,
            UsernamePasswordCredential(
                username: ScramSha256Example().user(),
                password: ScramSha256Example().password()),
            _StringGeneratorTest(),
          ),
        );
}
