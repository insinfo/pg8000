class ClientNotice {
  ClientNotice(
      {this.isError: false,
      this.severity,
      this.message,
      this.connectionName,
      this.exception,
      this.stackTrace}) {
    if (severity != 'ERROR' && severity != 'WARNING' && severity != 'DEBUG')
      throw ArgumentError.notNull('severity');
  }

  final bool isError;
  final String? severity;
  final String? message;
  final String? connectionName;
  final Object? exception;
  final StackTrace? stackTrace;

  String toString() => connectionName == null
      ? '$severity $message'
      : '$severity $message #$connectionName';
}
