

import 'package:dargres/src/dependencies/sasl_scram/sasl_scram.dart';

abstract class ScramExample {
  String user();

  String password();

  String clientNonce();

  String clientFirstMessageWithoutGs2Header();

  String clientFirstMessage();

  String serverSalt();

  int serverIterations();

  String serverNonce();

  String fullNonce();

  String serverFirstMessage();

  String gs2HeaderBase64();

  String clientFinalMessageWithoutProof();

  String authMessage();

  String clientFinalMessageProof();

  String clientFinalMessage();

  String serverFinalMessageProof();

  String serverFinalMessage();

  SaslAuthenticator getAuthenticator();
}
