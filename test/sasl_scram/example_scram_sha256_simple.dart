// ignore_for_file: non_constant_identifier_names

import 'package:crypto/crypto.dart';
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
  String USER() => 'user';

  @override
  String PASSWORD() => 'password';

  @override
  String CLIENT_NONCE() => 'a';

  @override
  String CLIENT_FIRST_MESSAGE_WITHOUT_GS2_HEADER() =>
      'n=${USER()},r=${CLIENT_NONCE()}';

  @override
  String CLIENT_FIRST_MESSAGE() =>
      'n,,${CLIENT_FIRST_MESSAGE_WITHOUT_GS2_HEADER()}';

  @override
  String SERVER_SALT() => 'abcd';

  @override
  int SERVER_ITERATIONS() => 1;

  @override
  String SERVER_NONCE() => 'b';

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
      'mU8grLfTjDrJer9ITsdHk0igMRDejG10EJPFbIBL3D0=';

  @override
  String CLIENT_FINAL_MESSAGE() =>
      '${CLIENT_FINAL_MESSAGE_WITHOUT_PROOF()},p=${CLIENT_FINAL_MESSAGE_PROOF()}';

  @override
  String SERVER_FINAL_MESSAGE_PROOF() =>
      'jwt97IHWFn7FEqHykPTxsoQrKGOMXJl/PJyJ1JXTBKc=';

  @override
  String SERVER_FINAL_MESSAGE() => 'v=${SERVER_FINAL_MESSAGE_PROOF()}';

  @override
  SaslAuthenticator getAuthenticator() => _ScramShaAuthenticatorTest();
}

class _StringGeneratorTest extends RandomStringGenerator {
  @override
  String generate(int length) {
    return SimpleScramSha256Example().CLIENT_NONCE();
  }
}

class _ScramShaAuthenticatorTest extends SaslAuthenticator {
  _ScramShaAuthenticatorTest()
      : super(
          ScramMechanism(
            'SCRAM-SHA-256',
            sha256,
            UsernamePasswordCredential(
                username: SimpleScramSha256Example().USER(),
                password: SimpleScramSha256Example().PASSWORD()),
            _StringGeneratorTest(),
          ),
        );
}