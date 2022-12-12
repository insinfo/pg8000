import 'dart:collection';

import 'column_description.dart';

/// RowDescription
/// A single row of a query result.
///
/// Column values can be accessed through the `[]` operator.
//implements List
class Row extends ListBase {
  final List<dynamic> _columnValues;
  final List<ColumnDescription> _columns;

  Row(this._columnValues, this._columns);

  /// return List of Column Description
  List<ColumnDescription> get columnsInfo => _columns;

  @override
  String toString() => _columnValues.toString();

  /// Returns a single-level map that maps the column name (or its alias) to the
  /// value returned on that position.
  Map<String, dynamic> toColumnMap() {
    return Map<String, dynamic>.fromIterables(
        _columns.map<String>((c) => c.name), _columnValues);
  }

  @override
  List toList({bool growable = true}) {
    return UnmodifiableListView(_columnValues);
  }

  @override
  int get length => _columnValues.length;

  @override
  void operator []=(int index, value) {
    //_columnValues[index] = value;
    throw UnimplementedError();
  }

  operator [](int i) => _columnValues[i];

  @override
  set length(int newLength) {
    // _columnValues.length = newLength;
    throw UnimplementedError();
  }
}


// class MyCustomList<E> extends Base with ListMixin<E> {
//   final List<E> l = [];
//   MyCustomList();

//   void set length(int newLength) { l.length = newLength; }
//   int get length => l.length;
//   E operator [](int index) => l[index];
//   void operator []=(int index, E value) { l[index] = value; }

//   // your custom methods
// }
// class FancyList<E> extends ListBase<E> {
//   List innerList = new List();

//   int get length => innerList.length;

//   void set length(int length) {
//     innerList.length = length;
//   }

//   void operator[]=(int index, E value) {
//     innerList[index] = value;
//   }

//   E operator [](int index) => innerList[index];

//   // Though not strictly necessary, for performance reasons
//   // you should implement add and addAll.

//   void add(E value) => innerList.add(value);

//   void addAll(Iterable<E> all) => innerList.addAll(all);
// }
// class ImmutableList<E> extends ListBase<E> {
//   late final List<E> innerList;

//   ImmutableList(Iterable<E> items) {
//     innerList = List<E>.unmodifiable(items);
//   }

//   @override
//   int get length => innerList.length;

//   @override
//   set length(int length) {
//     innerList.length = length;
//   }

//   @override
//   void operator []=(int index, E value) {
//     innerList[index] = value;
//   }

//   @override
//   E operator [](int index) => innerList[index];
// }