import 'dart:typed_data';

import '../../../sasl_scram_exception.dart';
import '../../sasl_authenticator.dart';

class ClientCompleted extends SaslStep {
  ClientCompleted() : super(Uint8List(0), isComplete: true);

  @override
  SaslStep transition(List<int> bytesReceivedFromServer,
      {passwordDigestResolver passwordDigestResolver}) {
    throw SaslScramException('Sasl conversation has completed');
  }
}
