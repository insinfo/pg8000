import 'location.dart';

final Location _utc =
    Location('UTC', const <int>[minTime], const <int>[0], const <TimeZone>[
  TimeZone.UTC,
]);

Location _local = _utc;

/// UTC timezone location.
// ignore: non_constant_identifier_names
Location get UTC => _utc;

/// Process-local timezone used by [TZDateTime.toLocal]. Defaults to UTC.
Location get local => _local;

/// Sets the location used by [TZDateTime.toLocal].
void setLocalLocation(Location location) => _local = location;
