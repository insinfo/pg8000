import 'dart:convert';
import 'dart:typed_data';

import '../../../sasl_scram_exception.dart';
import '../../../utils/parsing.dart';
import '../../sasl_authenticator.dart';
import 'client_completed.dart';

class ClientLast extends SaslStep {
  Uint8List serverSignature64;

  ClientLast(super.bytesToSendToServer, this.serverSignature64);

  @override
  SaslStep transition(List<int> bytesReceivedFromServer,
      {PasswordDigestResolver? passwordDigestResolver}) {
    final Map<String, dynamic> decodedMessage =
        parsePayload(utf8.decode(bytesReceivedFromServer));
    final serverSignature = base64.decode(decodedMessage['v'].toString());

    if (!_constantTimeBytesEqual(serverSignature64, serverSignature)) {
      throw SaslScramException('Server signature was invalid.');
    }

    return ClientCompleted();
  }
}

// Authentication material must not use List equality (identity) and should not
// reveal the first differing byte through an early return.
bool _constantTimeBytesEqual(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  var difference = 0;
  for (var i = 0; i < left.length; i++) {
    difference |= left[i] ^ right[i];
  }
  return difference == 0;
}
