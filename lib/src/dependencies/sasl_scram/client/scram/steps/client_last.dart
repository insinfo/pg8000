import 'dart:convert';
import 'dart:typed_data';

import 'package:collection/collection.dart';

import '../../../sasl_scram_exception.dart';
import '../../../utils/parsing.dart';
import '../../sasl_authenticator.dart';
import 'client_completed.dart';

class ClientLast extends SaslStep {
  Uint8List serverSignature64;

  ClientLast(Uint8List bytesToSendToServer, this.serverSignature64)
      : super(bytesToSendToServer);

  @override
  SaslStep transition(List<int> bytesReceivedFromServer,
      {passwordDigestResolver passwordDigestResolver}) {
    final Map<String, dynamic> decodedMessage =
        parsePayload(utf8.decode(bytesReceivedFromServer));
    final serverSignature = base64.decode(decodedMessage['v'].toString());

    if (!const IterableEquality().equals(serverSignature64, serverSignature)) {
      throw SaslScramException('Server signature was invalid.');
    }

    return ClientCompleted();
  }
}
