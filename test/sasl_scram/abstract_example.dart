// ignore_for_file: non_constant_identifier_names



import 'package:dargres/src/dependencies/sasl_scram/sasl_scram.dart';

abstract class ScramExample {
  String USER();

  String PASSWORD();

  String CLIENT_NONCE();

  String CLIENT_FIRST_MESSAGE_WITHOUT_GS2_HEADER();

  String CLIENT_FIRST_MESSAGE();

  String SERVER_SALT();

  int SERVER_ITERATIONS();

  String SERVER_NONCE();

  String FULL_NONCE();

  String SERVER_FIRST_MESSAGE();

  String GS2_HEADER_BASE64();

  String CLIENT_FINAL_MESSAGE_WITHOUT_PROOF();

  String AUTH_MESSAGE();

  String CLIENT_FINAL_MESSAGE_PROOF();

  String CLIENT_FINAL_MESSAGE();

  String SERVER_FINAL_MESSAGE_PROOF();

  String SERVER_FINAL_MESSAGE();

  SaslAuthenticator getAuthenticator();
}