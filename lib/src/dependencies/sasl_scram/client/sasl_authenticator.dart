// ignore_for_file: constant_identifier_names, camel_case_types

import 'dart:typed_data';

import '../sasl_scram.dart';

enum SaslMessageType {
  AuthenticationSASL,
  AuthenticationSASLContinue,
  AuthenticationSASLFinal,
}

typedef passwordDigestResolver = String Function(UsernamePasswordCredential);

abstract class SaslMechanism {
  String get name;

  SaslStep initialize({bool specifyUsername = false});
}

abstract class SaslStep {
  Uint8List bytesToSendToServer;
  bool isComplete = false;

  SaslStep(this.bytesToSendToServer, {this.isComplete = false});

  /// Manages exchange messages after the first one, responds based on the
  /// bytesReceivedFromServer
  /// If required an optional function to resolve password digest can be set
  /// If no function is present, only the password is used, otherwise the
  /// function return value. (This is needed for MongoDb Scram1 resolver)
  SaslStep transition(List<int> bytesReceivedFromServer,
      {passwordDigestResolver passwordDigestResolver});
}

/// Structure for SASL Authenticator
abstract class SaslAuthenticator extends Authenticator {
  static const int DefaultNonceLength = 24;

  SaslMechanism mechanism;
  SaslStep currentStep;

  SaslAuthenticator(this.mechanism) : super();

  @override
  Uint8List handleMessage(
      SaslMessageType msgType, Uint8List bytesReceivedFromServer,
      {bool specifyUsername = false}) {
    switch (msgType) {
      case SaslMessageType.AuthenticationSASL:
        currentStep = mechanism.initialize(specifyUsername: specifyUsername);
        break;
      case SaslMessageType.AuthenticationSASLContinue:
        currentStep = currentStep.transition(bytesReceivedFromServer);
        break;
      case SaslMessageType.AuthenticationSASLFinal:
        currentStep = currentStep.transition(bytesReceivedFromServer);
        return null;
      default:
        throw SaslScramException('Unsupported authentication type $msgType.');
    }
    return currentStep.bytesToSendToServer;
  }
}
