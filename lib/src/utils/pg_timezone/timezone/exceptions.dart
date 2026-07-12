class LocationNotFoundException implements Exception {
  final String msg;

  LocationNotFoundException(this.msg);

  @override
  String toString() => msg;
}
