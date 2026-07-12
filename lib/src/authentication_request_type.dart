import 'exceptions.dart';

/// Authentication method requested by the PostgreSQL server.
enum AuthenticationRequestType {
  ok(0),
  kerberosV4(1),
  kerberosV5(2),
  cleartextPassword(3),
  cryptPassword(4),
  md5Password(5),
  scmCredential(6),
  gss(7),
  gssContinue(8),
  sspi(9),
  sasl(10),
  saslContinue(11),
  saslFinal(12);

  final int code;
  const AuthenticationRequestType(this.code);

  static AuthenticationRequestType fromCode(int authCode) {
    return switch (authCode) {
      0 => ok,
      1 => kerberosV4,
      2 => kerberosV5,
      3 => cleartextPassword,
      4 => cryptPassword,
      5 => md5Password,
      6 => scmCredential,
      7 => gss,
      8 => gssContinue,
      9 => sspi,
      10 => sasl,
      11 => saslContinue,
      12 => saslFinal,
      _ => throw PostgresqlException(
          'Authentication method $authCode not recognized.'),
    };
  }

  String asString() => 'AuthenticationRequestType.$name';
}
