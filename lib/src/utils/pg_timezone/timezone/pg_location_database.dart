import '../../../timezone_database_scope.dart';
import 'exceptions.dart';
import 'location.dart';
import 'pg_timezone_data_10y.dart' as latest_10y;
import 'pg_timezone_data_all.dart' as latest_all;

Map<String, Location> _locations(PgTimeZoneDatabaseScope scope) {
  return switch (scope) {
    PgTimeZoneDatabaseScope.latestAll => latest_all.pgDatabaseMap,
    PgTimeZoneDatabaseScope.latest10y => latest_10y.pgDatabaseMap,
  };
}

/// Resolves a PostgreSQL/IANA timezone name in the selected vendored scope.
///
/// Canonical names use an O(1) map lookup. PostgreSQL's case-insensitive name
/// behavior is retained as a cold fallback and callers are expected to cache
/// the returned immutable [Location].
Location getLocation(
  String name, {
  PgTimeZoneDatabaseScope scope = PgTimeZoneDatabaseScope.latestAll,
}) {
  final locations = _locations(scope);
  final direct = locations[name];
  if (direct != null) return direct;

  final normalized = name.trim().toLowerCase();
  for (final entry in locations.entries) {
    if (entry.key.toLowerCase() == normalized) return entry.value;
  }
  throw LocationNotFoundException(
      'Location with the name "$name" does not exist');
}
