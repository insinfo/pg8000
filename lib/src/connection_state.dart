/// The current state of a connection.
class ConnectionState {
  final String value;
  const ConnectionState(this.value);

  @override
  String toString() => value;

  static const ConnectionState notConnected =
      const ConnectionState('notConnected');

  /// starting connection
  static const ConnectionState socketConnecting =
      const ConnectionState('socketConnecting');

  static const ConnectionState socketConnected =
      const ConnectionState('socketConnected');

  static const ConnectionState authenticating =
      const ConnectionState('authenticating');
  static const ConnectionState authenticated =
      const ConnectionState('authenticated');
  static const ConnectionState idle = const ConnectionState('idle');
  static const ConnectionState busy = const ConnectionState('busy');

  // state is called "ready" in libpq. Doesn't make sense in a non-blocking impl.
  static const ConnectionState streaming = const ConnectionState('streaming');
  static const ConnectionState closed = const ConnectionState('closed');
}

class PreparedStatementState {
  final String value;
  const PreparedStatementState(this.value);

  static const PreparedStatementState none =
      const PreparedStatementState('none');

  static const PreparedStatementState preparedStatement =
      const PreparedStatementState('preparedStatement');

  static const PreparedStatementState executeStatement =
      const PreparedStatementState('executeStatement');
}
