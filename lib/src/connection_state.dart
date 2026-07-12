/// The current state of a connection.
class ConnectionState {
  final String value;
  const ConnectionState(this.value);

  @override
  String toString() => value;

  static const ConnectionState notConnected = ConnectionState('notConnected');

  /// starting connection
  static const ConnectionState socketConnecting =
      ConnectionState('socketConnecting');

  static const ConnectionState socketConnected =
      ConnectionState('socketConnected');

  static const ConnectionState authenticating =
      ConnectionState('authenticating');
  static const ConnectionState authenticated =
      ConnectionState('authenticated');
  static const ConnectionState idle = ConnectionState('idle');
  static const ConnectionState busy = ConnectionState('busy');

  // state is called "ready" in libpq. Doesn't make sense in a non-blocking impl.
  static const ConnectionState streaming = ConnectionState('streaming');
  static const ConnectionState closed = ConnectionState('closed');
}
