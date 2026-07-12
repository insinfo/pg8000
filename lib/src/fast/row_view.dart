import 'dart:typed_data';

/// A lightweight, reusable view over one decoded PostgreSQL row.
///
/// Fast typed-query APIs can keep one [RowView] and one fixed-length values
/// list, overwrite that list for each DataRow, and invoke the user's mapper
/// without allocating a driver row object. Values obtained from this view must
/// be consumed during the callback; the view can point at another row later.
class RowView {
  List<Object?> _values;
  Map<String, int> _nameToIndex;

  RowView(this._values, this._nameToIndex);

  int get length => _values.length;

  Map<String, int> get nameToIndex => _nameToIndex;

  /// The reusable backing values.
  ///
  /// This list is intentionally not wrapped: doing so would allocate a wrapper
  /// on the hot path. Callers must not retain or mutate it while rows stream.
  List<Object?> get values => _values;

  /// Rebinds this object for reuse without constructing another [RowView].
  RowView reset(List<Object?> values, [Map<String, int>? nameToIndex]) {
    _values = values;
    if (nameToIndex != null) _nameToIndex = nameToIndex;
    return this;
  }

  /// Reads a value by zero-based index or column name.
  Object? operator [](Object column) => _values[_resolveIndex(column)];

  /// Reads and casts a nullable value by zero-based index or column name.
  T? get<T>(Object column) => this[column] as T?;

  /// Reads and casts a nullable value by column name.
  T? byName<T>(String name) => _values[_indexForName(name)] as T?;

  int? getInt(Object column) => this[column] as int?;

  double? getDouble(Object column) => this[column] as double?;

  num? getNum(Object column) => this[column] as num?;

  String? getString(Object column) => this[column] as String?;

  bool? getBool(Object column) => this[column] as bool?;

  DateTime? getDateTime(Object column) => this[column] as DateTime?;

  Uint8List? getBytes(Object column) => this[column] as Uint8List?;

  int? getIntByName(String name) => getInt(name);

  double? getDoubleByName(String name) => getDouble(name);

  num? getNumByName(String name) => getNum(name);

  String? getStringByName(String name) => getString(name);

  bool? getBoolByName(String name) => getBool(name);

  DateTime? getDateTimeByName(String name) => getDateTime(name);

  Uint8List? getBytesByName(String name) => getBytes(name);

  bool containsColumn(String name) => _nameToIndex.containsKey(name);

  int indexOf(String name) => _indexForName(name);

  int _resolveIndex(Object column) {
    if (column is int) return column;
    if (column is String) return _indexForName(column);
    throw ArgumentError.value(
        column, 'column', 'Expected a column index or name.');
  }

  int _indexForName(String name) {
    final index = _nameToIndex[name];
    if (index == null) {
      throw ArgumentError.value(name, 'name', 'Unknown column name.');
    }
    return index;
  }
}
