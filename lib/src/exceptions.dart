import 'server_notice.dart';

class PostgresqlException implements Exception {
  PostgresqlException(this.message,
      {this.connectionName,
      this.serverMessage,
      this.errorCode,
      this.serverErrorCode});

  final String message;

  /// Note the connection name can be null in some cases when thrown by pool.
  final String connectionName;

  final ServerNotice serverMessage;

  /// Note may be null.
  final Object errorCode;

  final dynamic serverErrorCode;

  @override
  String toString() {
    if (serverMessage != null) return serverMessage.toString();

    final buf = new StringBuffer(message);
    if (errorCode != null)
      buf
        ..write(' (')
        ..write(errorCode)
        ..write(')');
    if (connectionName != null)
      buf
        ..write(' #')
        ..write(connectionName);
    return buf.toString();
  }
}
