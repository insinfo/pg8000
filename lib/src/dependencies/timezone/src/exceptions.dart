
class TimeZoneInitException implements Exception {
  final String msg;

  TimeZoneInitException(this.msg);

  @override
  String toString() => msg;
}

class LocationNotFoundException implements Exception {
  final String msg;

  LocationNotFoundException(this.msg);

  @override
  String toString() => msg;
}
