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
}
