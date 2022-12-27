import 'dart:collection';

class ServerNotice {
  ServerNotice(this.isError, Map<String, String> fields, [this.connectionName])
      : fields = UnmodifiableMapView<String, String>(fields),
        severity = fields['S'],
        code = fields['C'],
        message = fields['M'] ?? '?';

  final bool isError;

  final String? connectionName;

  final Map<String, String> fields;

  final String? severity;

  final String? code;

  final String? message;

  String? get detail => fields['D'];

  String? get hint => fields['H'];

  String? get position => fields['P'];

  String? get internalPosition => fields['p'];

  String? get internalQuery => fields['q'];

  String? get where => fields['W'];

  String? get schema => fields['s'];

  String? get table => fields['t'];

  String? get column => fields['c'];

  String? get dataType => fields['d'];

  String? get constraint => fields['n'];

  String? get file => fields['F'];

  String? get line => fields['L'];

  String? get routine => fields['R'];

  String toString() => connectionName == null
      ? '$severity $code $message'
      : '$severity $code $message #$connectionName';
}
