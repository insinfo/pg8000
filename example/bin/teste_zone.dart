import 'package:dargres/src/dependencies/timezone/data/latest_10y.dart' as tz;

void main(List<String> args) {
  final stopwatch = Stopwatch()..start();
  tz.initializeTimeZones();
  stopwatch.stop();
  print('Execution time: ${stopwatch.elapsed.inMilliseconds}');
}
