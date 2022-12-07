import 'exceptions.dart';

/// enum of Authentication Type
class AuthenticationRequestType {
  final int code;
  const AuthenticationRequestType(this.code);

  /// Authentication Code 0
  static final AuthenticationRequestType Ok =
      const AuthenticationRequestType(0);

  /// Authentication Code 1
  static final AuthenticationRequestType KerberosV4 =
      const AuthenticationRequestType(1);

  /// Authentication Code 2
  static final AuthenticationRequestType KerberosV5 =
      const AuthenticationRequestType(2);

  /// Authentication Code 3
  static final AuthenticationRequestType CleartextPassword =
      const AuthenticationRequestType(3);

  /// Authentication Code 4
  static final AuthenticationRequestType CryptPassword =
      const AuthenticationRequestType(4);

  /// Authentication Code 5
  static final AuthenticationRequestType MD5Password =
      const AuthenticationRequestType(5);

  /// Authentication Code 6
  static final AuthenticationRequestType SCMCredential =
      const AuthenticationRequestType(6);

  /// Authentication Code 7
  static final AuthenticationRequestType GSS =
      const AuthenticationRequestType(7);

  /// Authentication Code 8
  static final AuthenticationRequestType GSSContinue =
      const AuthenticationRequestType(8);

  /// Authentication Code 9
  static final AuthenticationRequestType SSPI =
      const AuthenticationRequestType(9);

  /// Authentication Code 10
  static final AuthenticationRequestType SASL = AuthenticationRequestType(10);

  /// Authentication Code 11
  static final AuthenticationRequestType SASLContinue =
      const AuthenticationRequestType(11);

  /// Authentication Code 12
  static final AuthenticationRequestType SASLFinal =
      const AuthenticationRequestType(12);

  static AuthenticationRequestType fromCode(int authCode) {
    //return AuthenticationRequestType(authCode);
    switch (authCode) {
      case 0:
        return AuthenticationRequestType.Ok;
      case 1:
        return AuthenticationRequestType.KerberosV4;
      case 2:
        return AuthenticationRequestType.KerberosV5;
      case 3:
        return AuthenticationRequestType.CleartextPassword;
      case 4:
        return AuthenticationRequestType.CryptPassword;
      case 5:
        return AuthenticationRequestType.MD5Password;
      case 6:
        return AuthenticationRequestType.SCMCredential;
      case 7:
        return AuthenticationRequestType.GSS;
      case 8:
        return AuthenticationRequestType.GSSContinue;
      case 9:
        return AuthenticationRequestType.SSPI;
      case 10:
        return AuthenticationRequestType.SASL;
      case 11:
        return AuthenticationRequestType.SASLContinue;
      case 12:
        return AuthenticationRequestType.SASLFinal;
    }
    throw PostgresqlException(
        'Authentication method $authCode not recognized.');
  }

  String asString() {
    //return AuthenticationRequestType(authCode);
    switch (code) {
      case 0:
        return 'AuthenticationRequestType.Ok';
      case 1:
        return 'AuthenticationRequestType.KerberosV4';
      case 2:
        return 'AuthenticationRequestType.KerberosV5';
      case 3:
        return 'AuthenticationRequestType.CleartextPassword';
      case 4:
        return 'AuthenticationRequestType.CryptPassword';
      case 5:
        return 'AuthenticationRequestType.MD5Password';
      case 6:
        return 'AuthenticationRequestType.SCMCredential';
      case 7:
        return 'AuthenticationRequestType.GSS';
      case 8:
        return 'AuthenticationRequestType.GSSContinue';
      case 9:
        return 'AuthenticationRequestType.SSPI';
      case 10:
        return 'AuthenticationRequestType.SASL';
      case 11:
        return 'AuthenticationRequestType.SASLContinue';
      case 12:
        return 'AuthenticationRequestType.SASLFinal';
    }
    return ('Authentication method $code not recognized.');
  }
}
