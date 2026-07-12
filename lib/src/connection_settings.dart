import 'package:dargres/src/timezone_settings.dart';

import 'exceptions.dart';
import 'ssl_context.dart';

/// Bounded exponential backoff used when a disconnected connection is asked
/// to reconnect.
///
/// [maxAttempts] counts actual connection attempts. The first attempt waits
/// [initialDelay], subsequent attempts double that delay up to [maxDelay].
/// [jitterFactor] spreads reconnects from multiple clients over the interval
/// `delay * (1 - jitterFactor)` to `delay * (1 + jitterFactor)`.
class ReconnectPolicy {
  final int maxAttempts;
  final Duration initialDelay;
  final Duration maxDelay;
  final double jitterFactor;

  const ReconnectPolicy({
    this.maxAttempts = 5,
    this.initialDelay = const Duration(milliseconds: 100),
    this.maxDelay = const Duration(seconds: 5),
    this.jitterFactor = 0.2,
  })  : assert(maxAttempts >= 0),
        assert(jitterFactor >= 0 && jitterFactor <= 1);

  void validate() {
    if (maxAttempts < 0) {
      throw RangeError.value(maxAttempts, 'maxAttempts', 'must be >= 0');
    }
    if (initialDelay.isNegative || maxDelay.isNegative) {
      throw RangeError('Reconnect delays must not be negative.');
    }
    if (initialDelay > maxDelay) {
      throw RangeError('initialDelay must not exceed maxDelay.');
    }
    if (jitterFactor < 0 || jitterFactor > 1) {
      throw RangeError.range(jitterFactor, 0, 1, 'jitterFactor');
    }
  }

  /// Computes the delay for a one-based [attempt]. [jitterUnit] makes the
  /// calculation deterministic in tests; production callers pass a random
  /// value in the inclusive range 0..1.
  Duration delayForAttempt(int attempt, {double jitterUnit = 0.5}) {
    if (attempt < 1) {
      throw RangeError.value(attempt, 'attempt', 'must be >= 1');
    }
    validate();
    if (jitterUnit < 0 || jitterUnit > 1) {
      throw RangeError.range(jitterUnit, 0, 1, 'jitterUnit');
    }

    final maximum = maxDelay.inMicroseconds;
    var delay = initialDelay.inMicroseconds;
    for (var current = 1; current < attempt && delay < maximum; current++) {
      delay = delay > maximum ~/ 2 ? maximum : delay * 2;
    }
    if (delay > maximum) delay = maximum;
    if (delay == 0 || jitterFactor == 0) {
      return Duration(microseconds: delay);
    }

    final multiplier =
        1 - jitterFactor + (2 * jitterFactor * jitterUnit);
    final jittered = (delay * multiplier).round().clamp(0, maximum);
    return Duration(microseconds: jittered);
  }
}

class ConnectionSettings {
  /// The default port used by a PostgreSQL server.
  static const int defaultPort = 5432;
  static const String defaultHost = 'localhost';

  static PostgresqlException _error(String message) =>
      PostgresqlException('Settings: $message');

  String host;
  int port;
  String user;
  String? password;
  String? database;
  String textCharset;

  bool isUnixSocket = false;
  SslContext? sslContext;

  Duration connectionTimeout = const Duration(seconds: 180);

  /// Maximum time a command may remain active on the server. When it expires,
  /// dargres sends a PostgreSQL CancelRequest over a separate socket. Defaults
  /// to `null` to keep the normal hot path timer-free.
  Duration? commandTimeout;

  /// Time allowed for the original connection to reach ReadyForQuery after a
  /// CancelRequest. The socket is destroyed when this grace period expires.
  Duration cancelGracePeriod;

  TimeZoneSettings? timeZone;

  String sourceAddress = '';

  bool tcpKeepalive = false;

  String? applicationName;
  dynamic replication;
  String? connectionName;

  /// Allow reconnection attempt if PostgreSQL was restarted
  bool allowAttemptToReconnect = false;
  final ReconnectPolicy reconnectPolicy;
  final int statementCacheCapacity;

  ConnectionSettings({
    required this.user,
    this.host = defaultHost,
    this.database,
    this.port = defaultPort,
    this.password,
    this.sourceAddress = '',
    this.isUnixSocket = false,
    this.sslContext,
    this.connectionTimeout = const Duration(seconds: 180),
    this.commandTimeout,
    this.cancelGracePeriod = const Duration(seconds: 5),
    this.tcpKeepalive = false,
    this.applicationName,
    this.replication,
    this.connectionName,
    this.textCharset = 'utf8',
    this.allowAttemptToReconnect = false,
    this.reconnectPolicy = const ReconnectPolicy(),
    this.statementCacheCapacity = 64,
    this.timeZone,
  }) {
    reconnectPolicy.validate();
    if (commandTimeout != null && commandTimeout! <= Duration.zero) {
      throw ArgumentError.value(
          commandTimeout, 'commandTimeout', 'must be greater than zero');
    }
    if (cancelGracePeriod <= Duration.zero) {
      throw ArgumentError.value(cancelGracePeriod, 'cancelGracePeriod',
          'must be greater than zero');
    }
    if (statementCacheCapacity < 0) {
      throw RangeError.value(
          statementCacheCapacity, 'statementCacheCapacity', 'must be >= 0');
    }
  }

  ConnectionSettings clone() {
    return ConnectionSettings(
      user: user,
      host: host,
      database: database,
      port: port,
      password: password,
      sourceAddress: sourceAddress,
      isUnixSocket: isUnixSocket,
      sslContext: sslContext,
      connectionTimeout: connectionTimeout,
      commandTimeout: commandTimeout,
      cancelGracePeriod: cancelGracePeriod,
      tcpKeepalive: tcpKeepalive,
      applicationName: applicationName,
      replication: replication,
      connectionName: connectionName,
      textCharset: textCharset,
      allowAttemptToReconnect: allowAttemptToReconnect,
      reconnectPolicy: reconnectPolicy,
      statementCacheCapacity: statementCacheCapacity,
      timeZone: timeZone,
    );
  }

  /// create Connection Settings from URI String
  /// Example:  var uri = 'postgres://postgres:dart@localhost:5432/sistemas';
  factory ConnectionSettings.fromUri(String uriString) {
    final uri = Uri.parse(uriString);
    if (uri.scheme != 'postgres' && uri.scheme != 'postgresql') {
      throw _error('Invalid uri: scheme must be `postgres` or `postgresql`.');
    }

    if (uri.userInfo.isEmpty) {
      throw _error('Invalid uri: username must be specified.');
    }

    final separator = uri.userInfo.indexOf(':');
    final encodedUser = separator < 0
        ? uri.userInfo
        : uri.userInfo.substring(0, separator);
    final encodedPassword =
        separator < 0 ? '' : uri.userInfo.substring(separator + 1);

    if (!uri.path.startsWith('/') || uri.path.length <= 1) {
      throw _error('Invalid uri: `database name must be specified`.');
    }
    if (uri.host.isEmpty) {
      throw _error('Invalid uri: host must be specified.');
    }

    final requireSsl = uri.queryParameters['sslmode'] == 'require';

    final uriHost = Uri.decodeComponent(uri.host);
    final uriPort = uri.port == 0 ? defaultPort : uri.port;
    final uriUserName = Uri.decodeComponent(encodedUser);
    final uriPassword = Uri.decodeComponent(encodedPassword);
    final uriDatabase = Uri.decodeComponent(uri.path.substring(1));

    return ConnectionSettings(
      user: uriUserName,
      host: uriHost,
      port: uriPort,
      password: uriPassword,
      database: uriDatabase,
      sslContext: requireSsl ? SslContext.createDefaultContext() : null,
    );
  }

  String toUri() {
    final currentPassword = password;
    final currentDatabase = database;
    return Uri(
      scheme: 'postgres',
      userInfo: currentPassword == null || currentPassword.isEmpty
          ? user
          : '$user:$currentPassword',
      host: host,
      port: port,
      path: currentDatabase == null || currentDatabase.isEmpty
          ? null
          : '/$currentDatabase',
      queryParameters:
          sslContext == null ? null : const <String, String>{'sslmode': 'require'},
    ).toString();
  }

  @override
  String toString() =>
      "Settings {host: $host, port: $port, user: $user, database: $database}";
}
