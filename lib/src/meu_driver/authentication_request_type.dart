/// enum of Authentication Type
class AuthenticationRequestType {
  final int code;
  AuthenticationRequestType(this.code);

  static final AuthenticationRequestType AuthenticationOk =
      AuthenticationRequestType(0);
  static final AuthenticationRequestType AuthenticationKerberosV4 =
      AuthenticationRequestType(1);
  static final AuthenticationRequestType AuthenticationKerberosV5 =
      AuthenticationRequestType(2);
  static final AuthenticationRequestType AuthenticationCleartextPassword =
      AuthenticationRequestType(3);
  static final AuthenticationRequestType AuthenticationCryptPassword =
      AuthenticationRequestType(4);
  static final AuthenticationRequestType AuthenticationMD5Password =
      AuthenticationRequestType(5);
  static final AuthenticationRequestType AuthenticationSCMCredential =
      AuthenticationRequestType(6);
  static final AuthenticationRequestType AuthenticationGSS =
      AuthenticationRequestType(7);
  static final AuthenticationRequestType AuthenticationGSSContinue =
      AuthenticationRequestType(8);
  static final AuthenticationRequestType AuthenticationSSPI =
      AuthenticationRequestType(9);
  static final AuthenticationRequestType AuthenticationSASL =
      AuthenticationRequestType(10);
  static final AuthenticationRequestType AuthenticationSASLContinue =
      AuthenticationRequestType(11);
  static final AuthenticationRequestType AuthenticationSASLFinal =
      AuthenticationRequestType(12);
}
