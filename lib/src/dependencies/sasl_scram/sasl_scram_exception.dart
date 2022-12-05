class SaslScramException implements Exception {
  final String message;

  SaslScramException(this.message);

  @override
  String toString() => 'SaslScramDart Exception: $message';
}
