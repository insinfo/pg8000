import 'package:dargres/src/timezone_settings.dart';

import 'exceptions.dart';
import 'ssl_context.dart';

class ConnectionSettings {
  /// The default port used by a PostgreSQL server.
  static const int defaultPort = 5432;
  static const String DEFAULT_HOST = 'localhost';
  static _error(msg) => PostgresqlException('Settings: $msg');

  String host;
  int port;
  String user;
  String? password;
  String? database;
  String textCharset;

  bool isUnixSocket = false;
  //SSLv3/TLS TLSv1.3
  SslContext? sslContext;

  Duration connectionTimeout = Duration(seconds: 180);

  TimeZoneSettings? timeZone;

  String sourceAddress = '';

  bool tcpKeepalive = false;

  String? applicationName;
  dynamic replication;
  String? connectionName;

  /// Allow reconnection attempt if PostgreSQL was restarted
  bool allowAttemptToReconnect = false;
  ConnectionSettings({
    required this.user,
    this.host = 'localhost',
    this.database,
    this.port = 5432,
    this.password,
    this.sourceAddress = '',
    this.isUnixSocket = false,
    this.sslContext,
    this.connectionTimeout = const Duration(seconds: 180),
    this.tcpKeepalive = false,
    this.applicationName,
    this.replication = null,
    this.connectionName = null,
    this.textCharset = 'utf8',
    this.allowAttemptToReconnect = false,
    this.timeZone,
  });

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
      tcpKeepalive: tcpKeepalive,
      applicationName: applicationName,
      replication: replication,
      connectionName: connectionName,
      textCharset: textCharset,
      allowAttemptToReconnect: allowAttemptToReconnect,
      timeZone: timeZone,
    );
  }

  /// create Connection Settings from URI String
  /// Example:  var uri = 'postgres://postgres:s1sadm1n@localhost:5432/sistemas';
  factory ConnectionSettings.fromUri(String uriString) {
    var uri = Uri.parse(uriString);
    if (uri.scheme != 'postgres' && uri.scheme != 'postgresql')
      throw _error('Invalid uri: scheme must be `postgres` or `postgresql`.');

    if (uri.userInfo == '')
      throw _error('Invalid uri: username must be specified.');

    var userInfo;
    if (uri.userInfo.contains(':'))
      userInfo = uri.userInfo.split(':');
    else
      userInfo = [uri.userInfo, ''];

    if (!uri.path.startsWith('/') || !(uri.path.length > 1))
      throw _error('Invalid uri: `database name must be specified`.');

    final requireSsl = uri.query.contains('sslmode=require');

    var uriHost = Uri.decodeComponent(uri.host);
    var uriPort = uri.port == 0 ? ConnectionSettings.defaultPort : uri.port;
    var uriUserName = Uri.decodeComponent(userInfo[0]);
    var uriPassword = Uri.decodeComponent(userInfo[1]);
    var uriDatabase = Uri.decodeComponent(uri.path.substring(1));

    return ConnectionSettings(
      user: uriUserName,
      host: uriHost,
      port: uriPort,
      password: uriPassword,
      database: uriDatabase,
      sslContext: requireSsl ? SslContext.createDefaultContext() : null,
    );
  }

  String toUri() => new Uri(
          scheme: 'postgres',
          userInfo: password == '' ? '$user' : '$user:$password',
          host: host,
          port: port,
          path: database,
          query: sslContext != null ? '?sslmode=require' : null)
      .toString();

  @override
  String toString() =>
      "Settings {host: $host, port: $port, user: $user, database: $database}";
}
