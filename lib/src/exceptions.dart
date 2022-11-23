class PostgresqlException implements Exception {
  PostgresqlException(this.message, {this.serverMessage, this.exception});

  final String message;

  /// Note the connection name can be null in some cases when thrown by pool.
  //final String connectionName;

  final serverMessage;

  /// Note may be null.
  final Object exception;

  @override
  String toString() {
    if (serverMessage != null) return serverMessage.toString();

    final buf = StringBuffer(message);
    if (exception != null) buf..write(' (')..write(exception)..write(')');
    //if (connectionName != null) buf..write(' #')..write(connectionName);
    return buf.toString();
  }
}
