// ignore_for_file: non_constant_identifier_names

import 'package:crypto/crypto.dart';
import 'package:dargres/src/dependencies/sasl_scram/sasl_scram.dart';

import 'abstract_example.dart';

class ScramSha256Example extends ScramExample {
  static final ScramSha256Example _singleton = ScramSha256Example._internal();

  factory ScramSha256Example() {
    return _singleton;
  }

  ScramSha256Example._internal();

  @override
  String USER() => 'dart';

  @override
  String PASSWORD() => 'dart';

  @override
  String CLIENT_NONCE() => 'JS4]nA5J?]AxA[>jjaJ+5H3g';

  @override
  String CLIENT_FIRST_MESSAGE_WITHOUT_GS2_HEADER() =>
      'n=${USER()},r=${CLIENT_NONCE()}';

  @override
  String CLIENT_FIRST_MESSAGE() =>
      'n,,${CLIENT_FIRST_MESSAGE_WITHOUT_GS2_HEADER()}';

  @override
  String SERVER_SALT() => 'abcdefgh';

  @override
  int SERVER_ITERATIONS() => 1;

  @override
  String SERVER_NONCE() => '9djX!/t{sjHm)F/4B2tvu[i|';

  @override
  String FULL_NONCE() => CLIENT_NONCE() + SERVER_NONCE();

  @override
  String SERVER_FIRST_MESSAGE() =>
      'r=${FULL_NONCE()},s=${SERVER_SALT()},i=${SERVER_ITERATIONS()}';

  @override
  String GS2_HEADER_BASE64() => 'biws';

  @override
  String CLIENT_FINAL_MESSAGE_WITHOUT_PROOF() =>
      'c=${GS2_HEADER_BASE64()},r=${FULL_NONCE()}';

  @override
  String AUTH_MESSAGE() =>
      '${CLIENT_FIRST_MESSAGE_WITHOUT_GS2_HEADER()},${SERVER_FIRST_MESSAGE()},${CLIENT_FINAL_MESSAGE_WITHOUT_PROOF()}';

  @override
  String CLIENT_FINAL_MESSAGE_PROOF() =>
      'k8RLpllFL3oHrpjMPpwUVslDK5wam7TkVbi1AmvnQS0=';

  @override
  String CLIENT_FINAL_MESSAGE() =>
      '${CLIENT_FINAL_MESSAGE_WITHOUT_PROOF()},p=${CLIENT_FINAL_MESSAGE_PROOF()}';

  @override
  String SERVER_FINAL_MESSAGE_PROOF() =>
      '10ODfd6XRd0m4nJyYHP3u/Ib6peVFFY4piy2dbKv+bE=';

  @override
  String SERVER_FINAL_MESSAGE() => 'v=${SERVER_FINAL_MESSAGE_PROOF()}';

  @override
  SaslAuthenticator getAuthenticator() => _ScramShaAuthenticatorTest();
}

class _StringGeneratorTest extends RandomStringGenerator {
  @override
  String generate(int length) {
    return ScramSha256Example().CLIENT_NONCE();
  }
}

class _ScramShaAuthenticatorTest extends SaslAuthenticator {
  _ScramShaAuthenticatorTest()
      : super(
          ScramMechanism(
            'SCRAM-SHA-256',
            sha256,
            UsernamePasswordCredential(
                username: ScramSha256Example().USER(),
                password: ScramSha256Example().PASSWORD()),
            _StringGeneratorTest(),
          ),
        );
}