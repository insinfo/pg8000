/// Selects the vendored PostgreSQL/IANA timezone database used by opt-in
/// named-timezone decoding.
enum PgTimeZoneDatabaseScope {
  /// Full historical transition data. This is the correctness-first default.
  latestAll,

  /// Compact transition data for recent/current dates.
  latest10y,
}

PgTimeZoneDatabaseScope parsePgTimeZoneDatabaseScope(String value) {
  switch (value.trim().toLowerCase().replaceAll('-', '_')) {
    case 'latest_all':
    case 'all':
    case 'full':
      return PgTimeZoneDatabaseScope.latestAll;
    case 'latest_10y':
    case '10y':
    case 'compact':
      return PgTimeZoneDatabaseScope.latest10y;
    default:
      throw ArgumentError.value(
          value, 'value', 'Use latest_all or latest_10y.');
  }
}

String pgTimeZoneDatabaseScopeName(PgTimeZoneDatabaseScope scope) {
  return switch (scope) {
    PgTimeZoneDatabaseScope.latestAll => 'latest_all',
    PgTimeZoneDatabaseScope.latest10y => 'latest_10y',
  };
}
