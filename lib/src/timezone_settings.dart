import 'timezone_database_scope.dart';

/// Controls PostgreSQL date/time materialization.
///
/// The default is deliberately the small, exact UTC path. Named IANA lookup is
/// only performed when [useIanaTimeZoneDatabase] is explicitly enabled and
/// [forceDecodeTimestamptzAsUTC] is false.
class TimeZoneSettings {
  const TimeZoneSettings(
    this.value, {
    this.forceDecodeTimestamptzAsUTC = true,
    this.forceDecodeTimestampAsUTC = true,
    this.forceDecodeDateAsUTC = true,
    this.useIanaTimeZoneDatabase = false,
    this.ianaTimeZoneDatabaseScope = PgTimeZoneDatabaseScope.latestAll,
    this.throwOnDateTimeInfinity = false,
  });

  const TimeZoneSettings.utc()
      : value = 'UTC',
        forceDecodeTimestamptzAsUTC = true,
        forceDecodeTimestampAsUTC = true,
        forceDecodeDateAsUTC = true,
        useIanaTimeZoneDatabase = false,
        ianaTimeZoneDatabaseScope = PgTimeZoneDatabaseScope.latestAll,
        throwOnDateTimeInfinity = false;

  /// PostgreSQL/IANA location name, for example `America/Sao_Paulo`.
  final String value;

  /// Materialize `timestamptz` as UTC (the allocation-minimal default).
  final bool forceDecodeTimestamptzAsUTC;

  /// Materialize `timestamp without time zone` with UTC civil components.
  final bool forceDecodeTimestampAsUTC;

  /// Materialize `date` at UTC midnight.
  final bool forceDecodeDateAsUTC;

  /// Use the vendored IANA transition database for a named [value].
  final bool useIanaTimeZoneDatabase;

  /// Full historical or compact recent transition database.
  final PgTimeZoneDatabaseScope ianaTimeZoneDatabaseScope;

  /// Throw instead of returning null for PostgreSQL date/time infinities.
  final bool throwOnDateTimeInfinity;

  TimeZoneSettings copyWith({
    String? value,
    bool? forceDecodeTimestamptzAsUTC,
    bool? forceDecodeTimestampAsUTC,
    bool? forceDecodeDateAsUTC,
    bool? useIanaTimeZoneDatabase,
    PgTimeZoneDatabaseScope? ianaTimeZoneDatabaseScope,
    bool? throwOnDateTimeInfinity,
  }) {
    return TimeZoneSettings(
      value ?? this.value,
      forceDecodeTimestamptzAsUTC:
          forceDecodeTimestamptzAsUTC ?? this.forceDecodeTimestamptzAsUTC,
      forceDecodeTimestampAsUTC:
          forceDecodeTimestampAsUTC ?? this.forceDecodeTimestampAsUTC,
      forceDecodeDateAsUTC:
          forceDecodeDateAsUTC ?? this.forceDecodeDateAsUTC,
      useIanaTimeZoneDatabase:
          useIanaTimeZoneDatabase ?? this.useIanaTimeZoneDatabase,
      ianaTimeZoneDatabaseScope:
          ianaTimeZoneDatabaseScope ?? this.ianaTimeZoneDatabaseScope,
      throwOnDateTimeInfinity:
          throwOnDateTimeInfinity ?? this.throwOnDateTimeInfinity,
    );
  }
}
