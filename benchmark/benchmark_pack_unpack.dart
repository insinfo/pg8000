import 'package:pg8000/src/pack_unpack.dart';

void main(List<String> args) {
  var stopw = Stopwatch()..start();
  var result;
  for (var i = 0; i < 100000000; i++) {
    result = i_pack_fast(21474830);
  }
  stopw.stop();
  print('result: $result');
  print('i_pack_fast time: ${stopw.elapsed}');

  var stopw2 = Stopwatch()..start();
  var result2;
  for (var i = 0; i < 100000000; i++) {
    result2 = i_pack(21474830);
  }
  stopw2.stop();
  print('result: $result2');
  print('i_pack time: ${stopw2.elapsed}');
}
