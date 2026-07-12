import 'package:dargres/src/dependencies/sasl_scram/sasl_scram.dart';


import 'abstract_example.dart';

class ScramSha1Example extends ScramExample {
  static final ScramSha1Example _singleton = ScramSha1Example._internal();

  factory ScramSha1Example() {
    return _singleton;
  }

  ScramSha1Example._internal();

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
  int serverIterations() => 4096;

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
  String clientFinalMessageProof() => 'hOvx2G8wsqweEG2TXg2iDtvgDLE=';

  @override
  String clientFinalMessage() =>
      '${clientFinalMessageWithoutProof()},p=${clientFinalMessageProof()}';

  @override
  String serverFinalMessageProof() => 'IBr5o3kXU6mavsYjaCTcqfoYvYU=';

  @override
  String serverFinalMessage() => 'v=${serverFinalMessageProof()}';

  @override
  SaslAuthenticator getAuthenticator() => _ScramShaAuthenticatorTest();
}

class _StringGeneratorTest extends RandomStringGenerator {
  @override
  String generate(int length) {
    return ScramSha1Example().clientNonce();
  }
}

class _ScramShaAuthenticatorTest extends SaslAuthenticator {
  _ScramShaAuthenticatorTest()
      : super(
          ScramMechanism(
            'SCRAM-SHA-1',
            sha1,
            UsernamePasswordCredential(
                username: ScramSha1Example().user(),
                password: ScramSha1Example().password()),
            _StringGeneratorTest(),
          ),
        );
}
