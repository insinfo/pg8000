//enum SslVerifyMode { CERT_NONE, CERT_REQUIRED, CERT_OPTIONAL }

import 'dart:io';

class SslContext {
  //SslVerifyMode verifyMode = SslVerifyMode.CERT_NONE;
  //bool checkHostname = false;

  SecurityContext context;
  final bool Function(X509Certificate) onBadCertificate;
  void Function(String) keyLog;
  List<String> supportedProtocols;

  SslContext(
      {this.onBadCertificate,
      this.keyLog,
      this.supportedProtocols,
      this.context});

  /// validate Bad Certificate
  factory SslContext.createDefaultContext() {
    return SslContext(onBadCertificate: (cert) => true);
  }
}
