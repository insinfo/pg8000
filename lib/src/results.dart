import 'dart:async';
import 'dart:collection';

import 'row_info.dart';

class RowsAffected {
  int value = 0;
  RowsAffected();
}

class ResultStream extends StreamView<Row> {
  RowsAffected rowsAffected;
  ResultStream(super.stream, this.rowsAffected);

  /// Creates a new single-subscription stream from the future.
  ///
  /// When the future completes, the stream will fire one event, either
  /// data or error, and then close with a done-event.
  factory ResultStream.fromFuture(Future<dynamic> future) {
    // Use the controller's buffering to fill in the value even before
    // the stream has a listener. For a single value, it's not worth it
    // to wait for a listener before doing the `then` on the future.
    StreamController<dynamic> controller = StreamController<dynamic>();
    future.then((value) {
      controller.add(value);
      controller.close();
    }, onError: (error, stackTrace) {
      controller.addError(error, stackTrace);
      controller.close();
    });
    return controller.asResultStream();
  }
}

extension ResultStreamControllerExtension<T> on StreamController<T> {
  ResultStream asResultStream([RowsAffected? rowsAffected]) {
    return ResultStream(stream as Stream<Row>, rowsAffected ?? RowsAffected());
  }
}

extension StreamToResultsExtension on ResultStream {
  Future<Results> toResults() {
    var result = Results([], rowsAffected);
    var completer = Completer<Results>();
    listen(
        (data) {
          result.add(data);
        },
        onError: completer.completeError,
        onDone: () {
          completer.complete(result);
        },
        cancelOnError: true);
    return completer.future;
  }
}

/// this is Result set of Rows from database
class Results extends ListBase<Row> {
  final List<Row> rows;
  final RowsAffected rowsAffected;
  Results(this.rows, this.rowsAffected);

  @override
  int get length => rows.length;

  @override
  operator [](int index) {
    return rows[index];
  }

  @override
  void add(Row element) {
    rows.add(element);
  }

  @override
  void addAll(Iterable<Row> iterable) {
    rows.addAll(iterable);
  }

  /// return List of Row as Map
  List<Map<String, dynamic>> toMaps() {
    final maps = List<Map<String, dynamic>>.filled(
        rows.length, <String, dynamic>{},
        growable: false);
    for (var i = 0; i < rows.length; i++) {
      maps[i] = rows[i].toColumnMap();
    }
    return maps;
  }

  @override
  void operator []=(int index, value) {
    rows[index] = value;
  }

  @override
  set length(int newLength) {
    rows.length = newLength;
  }
}
