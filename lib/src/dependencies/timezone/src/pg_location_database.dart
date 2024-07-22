// ignore_for_file: always_use_package_imports

import '../timezone.dart';

import 'pg_timezone_data.dart';

/// PgLocationDatabase provides interface to find [Location]s by their name.
///
///     List<int> data = load(); // load database
///
///     PgLocationDatabase db = PgLocationDatabase.fromBytes(data);
///     Location loc = db.get('US/Eastern');
///
class PgLocationDatabase {
  /// Mapping between [Location] name and [Location].
  final locations = pgDatabaseMap; //<String, Location>{};

  /// Adds [Location] to the database.
  void add(Location location) {
    locations[location.name] = location;
  }

  /// Finds [Location] by its name.
  Location get(String name) {
    if (!isInitialized) {
      // Before you can get a location, you need to manually initialize the
      // timezone location database by calling initializeDatabase or similar.
      throw LocationNotFoundException(
          'Tried to get location before initializing timezone database');
    }

    final loc = locations[name];
    if (loc == null) {
      throw LocationNotFoundException(
          'Location with the name "$name" doesn\'t exist');
    }
    return loc;
  }

  /// Clears the database of all [Location] entries.
  void clear() => locations.clear();

  /// Returns whether the database is empty, or has [Location] entries.
  @Deprecated("Use 'isInitialized' instead")
  bool get isEmpty => isInitialized;

  /// Returns whether the database is empty, or has [Location] entries.
  bool get isInitialized => locations.isNotEmpty;
}

final _database = PgLocationDatabase();

/// Global TimeZone database
PgLocationDatabase get timeZoneDatabase => _database;

/// Find [Location] by its name.
///
/// ```dart
/// final detroit = getLocation('America/Detroit');
/// ```
Location getLocation(String pgTimeZone) {
  final tzLocations = timeZoneDatabase.locations.entries
      .where((e) {
        return e.key.toLowerCase() == pgTimeZone ||
            e.value.currentTimeZone.abbreviation.toLowerCase() == pgTimeZone;
      })
      .map((e) => e.value)
      .toList();

  if (tzLocations.isEmpty) {
    throw LocationNotFoundException(
        'Location with the name "$pgTimeZone" doesn\'t exist');
  }
  final tzLocation = tzLocations.first;
  return tzLocation;  
}