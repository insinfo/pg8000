/// The current state of a connection.
class ConnectionState {
  final String _name;
  const ConnectionState(this._name);

  @override
  String toString() => _name;

  static const ConnectionState notConnected =
      const ConnectionState('notConnected');
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
