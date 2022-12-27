import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dargres/src/dependencies/sasl_scram/client/scram/steps/client_first.dart';
import 'package:dargres/src/dependencies/sasl_scram/client/scram/steps/client_last.dart';
import 'package:dargres/src/dependencies/sasl_scram/sasl_scram.dart';
import 'package:dargres/src/dependencies/sasl_scram/utils/parsing.dart';
import 'package:dargres/src/dependencies/sasl_scram/utils/sasl.dart';
import 'package:dargres/src/dependencies/sasl_scram/utils/typed_data.dart';
import 'package:test/test.dart';

import 'example_scram_sha1.dart';
import 'example_scram_sha256.dart';
import 'example_scram_sha256_simple.dart';

void main() async {
  group('Scram Authentication', () {
    final scramExamples = [
      ScramSha1Example(),
      ScramSha256Example(),
      SimpleScramSha256Example()
    ];
    for (final scramExample in scramExamples) {
      final authenticator = scramExample.getAuthenticator();

      test('Should be able to return the client first message for the server',
          () {
        final bytesReceivedFromServer = Uint8List(0);

        final bytesToSentToServer = authenticator.handleMessage(
          SaslMessageType.AuthenticationSASL,
          bytesReceivedFromServer,
        );

        final decode = utf8.decode(bytesToSentToServer!);
        final payload = decode.replaceFirst(gs2Header, '');
        expect(decode.length, payload.length + 3);
        final parsed = parsePayload(payload);
        expect(parsed['n'], '*');
        expect(parsed['r'], scramExample.CLIENT_NONCE());

        return parsed['r']!;
      });

      test(
          'Should be able to interpret the first server response and return the client final message with proof for the server',
          () {
        final bytesReceivedFromServer =
            coerceUint8List(utf8.encode(scramExample.SERVER_FIRST_MESSAGE()));

        final bytesToSentToServer = authenticator.handleMessage(
          SaslMessageType.AuthenticationSASLContinue,
          bytesReceivedFromServer,
        );

        final decode = utf8.decode(bytesToSentToServer!);
        final parsed = parsePayload(decode);
        expect(parsed['c'], scramExample.GS2_HEADER_BASE64());
        expect(parsed['r'], scramExample.FULL_NONCE());
        expect(parsed['p'], scramExample.CLIENT_FINAL_MESSAGE_PROOF());
      });

      test(
          'Should be able to interpret the final server response and check the server proof',
          () {
        final bytesReceivedFromServer =
            coerceUint8List(utf8.encode(scramExample.SERVER_FINAL_MESSAGE()));

        expect(authenticator.currentStep is ClientLast, true);
        final clientLastStep = authenticator.currentStep as ClientLast;
        final serverSignature = base64.encode(clientLastStep.serverSignature64);
        expect(serverSignature, scramExample.SERVER_FINAL_MESSAGE_PROOF());

        // Throws if proof is not correct
        final bytesToSentToServer = authenticator.handleMessage(
          SaslMessageType.AuthenticationSASLFinal,
          bytesReceivedFromServer,
        );

        expect(bytesToSentToServer, null); // No client response needed
      });
    }
  });

  group('RandomStringGenerator', () {
    test("Shouldn't produce twice the same string", () {
      var generator = CryptoStrengthStringGenerator();

      var results = {};

      for (var i = 0; i < 100000; ++i) {
        var generatedString =
            generator.generate(SaslAuthenticator.DefaultNonceLength);
        if (results.containsKey(generatedString)) {
          fail("Shouldn't have generated 2 identical strings");
        } else {
          results[generatedString] = 1;
        }
      }
    });
  });
  group('Static Methods', () {
    test('hi', () {
      var salt = [
        99,
        152,
        63,
        114,
        74,
        185,
        151,
        114,
        213,
        141,
        130,
        192,
        111,
        106,
        92,
        21,
        188,
        147,
        158,
        198,
        94,
        89,
        75,
        136,
        105,
        183,
        207,
        24
      ];
      var password = 'übelkübel';
      var iterations = 15000;

      var result = [
        229,
        212,
        50,
        8,
        194,
        32,
        193,
        73,
        95,
        176,
        199,
        198,
        15,
        144,
        48,
        86,
        6,
        240,
        51,
        35,
        45,
        158,
        174,
        188,
        64,
        181,
        6,
        165,
        174,
        112,
        102,
        90
      ];

      var ret = ClientFirst.hi(
          password, Uint8List.fromList(salt), iterations, sha256);
      expect(ret, result);
    });
  });
}