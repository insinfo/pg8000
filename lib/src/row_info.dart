import 'dart:collection';

import 'column_description.dart';

/// RowDescription
/// A single row of a query result.
///
/// Column values can be accessed through the `[]` operator.
class Row extends ListBase<Object?> {
  final List<Object?> _columnValues;
  final List<ColumnDescription> _columns;
  final Map<String, int>? _nameToIndex;

  Row(this._columnValues, this._columns, [this._nameToIndex]);

  /// return List of Column Description
  List<ColumnDescription> get columnsInfo => _columns;

  @override
  String toString() => _columnValues.toString();

  /// Returns a single-level map that maps the column name (or its alias) to the
  /// value returned on that position.
  Map<String, dynamic> toColumnMap() {
    final result = <String, dynamic>{};
    final indexes = _nameToIndex;
    if (indexes != null) {
      for (final entry in indexes.entries) {
        result[entry.key] = _columnValues[entry.value];
      }
    } else {
      for (var i = 0; i < _columns.length; i++) {
        result[_columns[i].name] = _columnValues[i];
      }
    }
    return result;
  }

  @override
  List<Object?> toList({bool growable = true}) {
    return UnmodifiableListView<Object?>(_columnValues);
  }

  @override
  int get length => _columnValues.length;

  @override
  void operator []=(int index, value) {
    throw UnsupportedError('PostgreSQL rows are immutable.');
  }

  @override
  Object? operator [](int index) => _columnValues[index];

  @override
  set length(int newLength) {
    throw UnsupportedError('PostgreSQL rows are immutable.');
  }
}
