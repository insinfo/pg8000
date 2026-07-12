class ClientNotice {
  ClientNotice(
      {this.isError = false,
      this.severity,
      this.message,
      this.connectionName,
      this.exception,
      this.stackTrace}) {
    if (severity != 'ERROR' && severity != 'WARNING' && severity != 'DEBUG') {
      throw ArgumentError.value(
          severity, 'severity', 'Expected ERROR, WARNING, or DEBUG.');
    }
  }

  final bool isError;
  final String? severity;
  final String? message;
  final String? connectionName;
  final Object? exception;
  final StackTrace? stackTrace;

  @override
  String toString() => connectionName == null
      ? '$severity $message'
      : '$severity $message #$connectionName';
}
