Map<String, String> parsePayload(String payload) {
  final dict = <String, String>{};
  final parts = payload.split(',');

  for (var i = 0; i < parts.length; i++) {
    final key = parts[i][0];
    final value = parts[i].substring(2);
    dict[key] = value;
  }

  return dict;
}
