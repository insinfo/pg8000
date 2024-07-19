import 'package:dargres/src/timezone_settings.dart';

class ServerInfo {
  Map<String, dynamic> rawParams = <String, dynamic>{};

  /// SQL_ASCII | utf8
  String? clientEncoding;

  /// ISO, DMY
  String? dateStyle;

  /// on
  String? integerDatetimes;

  /// off
  String? isSuperuser;

  /// SQL_ASCII
  String? serverEncoding;

  /// example: 8.2.23
  String? serverVersion;

  /// example: username: sw.suporte
  String? sessionAuthorization;

  /// off
  String? standardConformingStrings;

  /// localtime
  TimeZoneSettings timeZone = TimeZoneSettings('UTC');

  ServerInfo({
    this.clientEncoding,
    this.dateStyle,
    this.integerDatetimes,
    this.isSuperuser,
    this.serverEncoding,
    this.serverVersion,
    this.sessionAuthorization,
    this.standardConformingStrings,
    required this.timeZone,
  });

  Map<String, dynamic> toMap() {
    return {
      'raw_params': rawParams,
      'client_encoding': clientEncoding,
      'datestyle': dateStyle,
      'integer_datetimes': integerDatetimes,
      'is_superuser': isSuperuser,
      'server_encoding': serverEncoding,
      'server_version': serverVersion,
      'session_authorization': sessionAuthorization,
      'standard_conforming_strings': standardConformingStrings,
      'timezone': timeZone,
    };
  }

  factory ServerInfo.fromMap(Map<String, dynamic> map) {
    var s = ServerInfo(
      clientEncoding: map['client_encoding'] ?? '',
      dateStyle: map['datestyle'] ?? '',
      integerDatetimes: map['integer_datetimes'] ?? '',
      isSuperuser: map['is_superuser'] ?? '',
      serverEncoding: map['server_encoding'] ?? '',
      serverVersion: map['server_version'] ?? '',
      sessionAuthorization: map['session_authorization'] ?? '',
      standardConformingStrings: map['standard_conforming_strings'] ?? '',
      timeZone: map['timezone'] ?? '',
    );
    s.rawParams = Map<String, dynamic>.from(map['params']);
    return s;
  }
}
