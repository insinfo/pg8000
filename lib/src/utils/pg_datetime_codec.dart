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
    final parts = _PgDateTimeText.parse(value);
    if (parts == null) return null;
    return timeZone.forceDecodeDateAsUTC
        ? DateTime.utc(parts.year, parts.month, parts.day)
        : DateTime(parts.year, parts.month, parts.day);
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
    // The civil components are read directly from the text. Parsing through
    // a local DateTime would move wall-clock times that fall inside a local
    // DST gap (Brazil started DST at 00:00) and would diverge from binary.
    final parts = _PgDateTimeText.parse(value);
    if (parts == null) return null;
    return timeZone.forceDecodeTimestampAsUTC
        ? DateTime.utc(parts.year, parts.month, parts.day, parts.hour,
            parts.minute, parts.second, 0, parts.microsecond)
        : DateTime(parts.year, parts.month, parts.day, parts.hour,
            parts.minute, parts.second, 0, parts.microsecond);
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
    final parts = _PgDateTimeText.parse(value);
    if (parts == null) return null;
    final civil = DateTime.utc(parts.year, parts.month, parts.day, parts.hour,
        parts.minute, parts.second, 0, parts.microsecond);
    // PostgreSQL prints the session-zone offset, including seconds for LMT
    // offsets such as `-03:06:28`.
    final instant = civil.subtract(Duration(seconds: parts.offsetSeconds));
    return _materializeTimestamptz(instant, timeZone);
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

/// Civil components of a PostgreSQL `date`, `timestamp` or `timestamptz`
/// printed with `DateStyle = ISO`:
/// `YYYY-MM-DD[ HH:MM:SS[.ffffff][±HH[:MM[:SS]]]][ BC]`.
///
/// No local [DateTime] is involved, so the result never depends on the
/// operating system time zone.
final class _PgDateTimeText {
  _PgDateTimeText(this.year, this.month, this.day, this.hour, this.minute,
      this.second, this.microsecond, this.offsetSeconds);

  /// Astronomical year: `0001 BC` is `0`, `0044 BC` is `-43`.
  final int year;
  final int month;
  final int day;
  final int hour;
  final int minute;
  final int second;
  final int microsecond;

  /// East-positive UTC offset; zero when the text has no offset.
  final int offsetSeconds;

  static _PgDateTimeText? parse(String text) {
    final s = text.trim();
    final length = s.length;
    var i = 0;

    int? digits(int count) {
      if (i + count > length) return null;
      var value = 0;
      for (var end = i + count; i < end; i++) {
        final d = s.codeUnitAt(i) - 0x30;
        if (d < 0 || d > 9) return null;
        value = value * 10 + d;
      }
      return value;
    }

    bool expect(int codeUnit) {
      if (i < length && s.codeUnitAt(i) == codeUnit) {
        i++;
        return true;
      }
      return false;
    }

    // Year: at least four digits (PostgreSQL prints five for year >= 10000).
    var year = 0;
    final yearStart = i;
    while (i < length) {
      final d = s.codeUnitAt(i) - 0x30;
      if (d < 0 || d > 9) break;
      year = year * 10 + d;
      i++;
    }
    if (i - yearStart < 4 || !expect(0x2d)) return null;
    final month = digits(2);
    if (month == null || !expect(0x2d)) return null;
    final day = digits(2);
    if (day == null) return null;

    var hour = 0, minute = 0, second = 0, microsecond = 0, offset = 0;
    if (i < length &&
        (s.codeUnitAt(i) == 0x20 || s.codeUnitAt(i) == 0x54) &&
        i + 1 < length &&
        s.codeUnitAt(i + 1) != 0x42) {
      i++; // ' ' or 'T'
      final h = digits(2);
      if (h == null || !expect(0x3a)) return null;
      final mi = digits(2);
      if (mi == null || !expect(0x3a)) return null;
      final se = digits(2);
      if (se == null) return null;
      hour = h;
      minute = mi;
      second = se;
      if (expect(0x2e)) {
        var scale = 100000;
        final fractionStart = i;
        while (i < length) {
          final d = s.codeUnitAt(i) - 0x30;
          if (d < 0 || d > 9) break;
          microsecond += d * scale;
          scale ~/= 10;
          i++;
        }
        if (i == fractionStart) return null;
      }
      if (i < length &&
          (s.codeUnitAt(i) == 0x2b || s.codeUnitAt(i) == 0x2d)) {
        final sign = s.codeUnitAt(i) == 0x2d ? -1 : 1;
        i++;
        final oh = digits(2);
        if (oh == null) return null;
        var om = 0, os = 0;
        if (expect(0x3a)) {
          final value = digits(2);
          if (value == null) return null;
          om = value;
          if (expect(0x3a)) {
            final secs = digits(2);
            if (secs == null) return null;
            os = secs;
          }
        }
        offset = sign * (oh * 3600 + om * 60 + os);
      } else if (expect(0x5a)) {
        offset = 0; // 'Z'
      }
    }

    if (i < length) {
      if (s.substring(i) != ' BC') return null;
      year = 1 - year;
      i = length;
    }
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    return _PgDateTimeText(
        year, month, day, hour, minute, second, microsecond, offset);
  }
}
