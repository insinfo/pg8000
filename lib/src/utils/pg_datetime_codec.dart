import '../timezone_settings.dart';
import 'pg_timezone/pg_timezone.dart' as tz;

/// Allocation-conscious PostgreSQL date/time decoder shared by text and
/// binary result paths.
abstract final class PgDateTimeCodec {
  static const int postgresUnixEpochMicroseconds = 946684800000000;
  static const int microsecondsPerDay = 86400000000;
  static const int dateInfinity = 2147483647;
  static const int dateNegativeInfinity = -2147483648;
  static const int timestampInfinity = 9223372036854775807;
  static const int timestampNegativeInfinity = -9223372036854775808;

  static Map<String, tz.Location>? _locationCache;

  static DateTime? decodeDate(
    int days, {
    TimeZoneSettings timeZone = const TimeZoneSettings.utc(),
  }) {
    if (days == dateInfinity || days == dateNegativeInfinity) {
      return handleInfinity('date', timeZone);
    }
    final utc = DateTime.fromMicrosecondsSinceEpoch(
      postgresUnixEpochMicroseconds + days * microsecondsPerDay,
      isUtc: true,
    );
    return timeZone.forceDecodeDateAsUTC
        ? utc
        : DateTime(utc.year, utc.month, utc.day);
  }

  static DateTime? decodeDateText(
    String? value, {
    TimeZoneSettings timeZone = const TimeZoneSettings.utc(),
  }) {
    if (value == null) return null;
    if (_isInfinity(value)) return handleInfinity('date', timeZone);
    final parsed = DateTime.tryParse(value);
    if (parsed == null) return null;
    return timeZone.forceDecodeDateAsUTC
        ? DateTime.utc(parsed.year, parsed.month, parsed.day)
        : DateTime(parsed.year, parsed.month, parsed.day);
  }

  static DateTime? decodeTimestamp(
    int microseconds, {
    TimeZoneSettings timeZone = const TimeZoneSettings.utc(),
  }) {
    if (microseconds == timestampInfinity ||
        microseconds == timestampNegativeInfinity) {
      return handleInfinity('timestamp', timeZone);
    }
    final components = DateTime.fromMicrosecondsSinceEpoch(
      postgresUnixEpochMicroseconds + microseconds,
      isUtc: true,
    );
    if (timeZone.forceDecodeTimestampAsUTC) return components;
    return DateTime(
      components.year,
      components.month,
      components.day,
      components.hour,
      components.minute,
      components.second,
      components.millisecond,
      components.microsecond,
    );
  }

  static DateTime? decodeTimestampText(
    String? value, {
    TimeZoneSettings timeZone = const TimeZoneSettings.utc(),
  }) {
    if (value == null) return null;
    if (_isInfinity(value)) return handleInfinity('timestamp', timeZone);
    final parsed = DateTime.tryParse(value.replaceFirst(' ', 'T'));
    if (parsed == null) return null;
    return timeZone.forceDecodeTimestampAsUTC
        ? DateTime.utc(
            parsed.year,
            parsed.month,
            parsed.day,
            parsed.hour,
            parsed.minute,
            parsed.second,
            parsed.millisecond,
            parsed.microsecond,
          )
        : DateTime(
            parsed.year,
            parsed.month,
            parsed.day,
            parsed.hour,
            parsed.minute,
            parsed.second,
            parsed.millisecond,
            parsed.microsecond,
          );
  }

  static DateTime? decodeTimestamptz(
    int microseconds, {
    TimeZoneSettings timeZone = const TimeZoneSettings.utc(),
  }) {
    if (microseconds == timestampInfinity ||
        microseconds == timestampNegativeInfinity) {
      return handleInfinity('timestamptz', timeZone);
    }
    final instant = DateTime.fromMicrosecondsSinceEpoch(
      postgresUnixEpochMicroseconds + microseconds,
      isUtc: true,
    );
    return _materializeTimestamptz(instant, timeZone);
  }

  static DateTime? decodeTimestamptzText(
    String? value, {
    TimeZoneSettings timeZone = const TimeZoneSettings.utc(),
  }) {
    if (value == null) return null;
    if (_isInfinity(value)) return handleInfinity('timestamptz', timeZone);
    final parsed = DateTime.tryParse(value.replaceFirst(' ', 'T'));
    if (parsed == null) return null;
    return _materializeTimestamptz(parsed.toUtc(), timeZone);
  }

  static DateTime _materializeTimestamptz(
      DateTime instant, TimeZoneSettings timeZone) {
    if (timeZone.forceDecodeTimestamptzAsUTC) return instant;

    final name = timeZone.value.trim();
    if (name.isEmpty || name.toLowerCase() == 'utc') return instant;
    if (!timeZone.useIanaTimeZoneDatabase) return instant.toLocal();

    // The transition is selected for this exact instant. Never substitute the
    // location's current offset: historical DST and rule changes must survive.
    return tz.TZDateTime.from(instant, _resolveLocation(name, timeZone));
  }

  static tz.Location _resolveLocation(
      String name, TimeZoneSettings timeZone) {
    final normalized = name.toLowerCase();
    final key = '${timeZone.ianaTimeZoneDatabaseScope.name}:$normalized';
    final cache = _locationCache ??= <String, tz.Location>{};
    final cached = cache[key];
    if (cached != null) return cached;
    final location = tz.getLocation(
      name,
      scope: timeZone.ianaTimeZoneDatabaseScope,
    );
    cache[key] = location;
    return location;
  }

  static DateTime? handleInfinity(
      String typeName, TimeZoneSettings timeZone) {
    if (timeZone.throwOnDateTimeInfinity) {
      throw FormatException('PostgreSQL $typeName value is infinity.');
    }
    return null;
  }

  static bool _isInfinity(String value) {
    final normalized = value.trim().toLowerCase();
    return normalized == 'infinity' || normalized == '-infinity';
  }
}
