import 'dart:async';
import 'dart:collection';

class RowsAffected {
  int value = 0;
  RowsAffected();
}

class ResultStream<T> extends StreamView<T> {
  RowsAffected rowsAffected;
  ResultStream(Stream<T> stream, this.rowsAffected) : super(stream);

  /// Creates a new single-subscription stream from the future.
  ///
  /// When the future completes, the stream will fire one event, either
  /// data or error, and then close with a done-event.
  factory ResultStream.fromFuture(Future<T> future) {
    //return ResultStream<T>(Stream.fromFuture(future));

    // Use the controller's buffering to fill in the value even before
    // the stream has a listener. For a single value, it's not worth it
    // to wait for a listener before doing the `then` on the future.
    StreamController<T> controller = new StreamController<T>();
    future.then((value) {
      controller.add(value);
      controller.close();
    }, onError: (error, stackTrace) {
      controller.addError(error, stackTrace);
      controller.close();
    });
    //print('ResultStream@fromFuture');
    return controller.asResultStream();
  }
}

extension ResultStreamControllerExtension<T> on StreamController<T> {
  ResultStream<T> asResultStream([RowsAffected? rowsAffected]) {
    //print('ResultStreamController@asResultStream ${rowsAffected?.value}');
    return ResultStream<T>(
        this.stream, rowsAffected == null ? RowsAffected() : rowsAffected);
  }
}

extension StreamToResultsExtension<T> on ResultStream<T> {
  Future<Results<T>> toResults() {
    //print('StreamToResults@toResults ${rowsAffected.value}');
    var result = Results<T>([], this.rowsAffected);
    var completer = new Completer<Results<T>>();
    this.listen(
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

class Results<T> extends ListBase<T> {
  final List<T> rows;
  final RowsAffected rowsAffected;
  Results(this.rows, this.rowsAffected);

  int get length => rows.length;

  @override
  operator [](int index) {
    return rows[index];
  }

  @override
  void add(T element) {
    rows.add(element);
  }

  @override
  void addAll(Iterable<T> iterable) {
    rows.addAll(iterable);
  }

  @override
  void operator []=(int index, value) {
    print('operator [] $index');
    //rows[index] = value;
    //this[this.length++] = element;
    rows[index] = value;
  }

  @override
  set length(int newLength) {
    UnimplementedError();
  }
}
