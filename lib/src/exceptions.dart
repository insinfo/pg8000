import 'server_notice.dart';

class PostgresqlException implements Exception {
  PostgresqlException(
    this.message, {
    this.connectionName,
    this.serverMessage,
    this.errorCode,
    this.serverErrorCode,
    this.sql,
  });

  final String message;

  /// Note the connection name can be null in some cases when thrown by pool.
  final String connectionName;

  final ServerNotice serverMessage;

  /// Note may be null.
  final Object errorCode;

  final dynamic serverErrorCode;

  final dynamic sql;

  @override
  String toString() {
    if (serverMessage != null) {
      var m = serverMessage.toString();
      if (sql != null) {
        m += '\r\nSQL: $sql';
      }
      return m;
    }

    final buf = StringBuffer(message);
    if (errorCode != null) {
      buf.write(' (');
      buf..write(errorCode);
      buf..write(')');
    }

    if (connectionName != null) {
      buf.write(' #');
      buf.write(connectionName);
    }

    if (sql != null) {
      buf.write(' SQL: $sql');
    }

    return buf.toString();
  }
}
