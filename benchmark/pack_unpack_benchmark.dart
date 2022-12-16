import 'dart:convert';

import 'package:dargres/src/pack_unpack.dart';

void main(List<String> args) {
  // var stopw = Stopwatch()..start();
  // var result;
  // for (var i = 0; i < 100000000; i++) {
  //   result = i_pack_fast(21474830);
  // }
  // stopw.stop();
  // print('result: $result');
  // print('i_pack_fast time: ${stopw.elapsed}');

  // var stopw2 = Stopwatch()..start();
  // var result2;
  // for (var i = 0; i < 100000000; i++) {
  //   result2 = i_pack(21474830);
  // }
  // stopw2.stop();
  // print('result: $result2');
  // print('i_pack time: ${stopw2.elapsed}');

  // implementation from @lrhn https://github.com/dart-lang/sdk/issues/50708
  runBenchmark(() {
    return packlrhn('iiii', [64, 65, 66, 67]);
  }, 'pack from lrhn', 2);

  // my pure dart implementation
  runBenchmark(() {
    return pack('iiii', [64, 65, 66, 67]);
  }, 'my pure dart pack', 2);

  // using isoos ByteDataWriter
  runBenchmark(() {
    return pack2('iiii', [64, 65, 66, 67]);
  }, 'using isoos ByteDataWriter pack', 2);

  // using terrier RawWriter
  runBenchmark(() {
    return pack3('iiii', [64, 65, 66, 67]);
  }, 'using terrier RawWriter pack', 2);
}

void runBenchmark(Function closure, String title, [int runCount = 1]) {
  for (var rc = 0; rc < runCount; rc++) {
    var stopw3 = Stopwatch()..start();
    var result3;
    for (var i = 0; i < 100000000; i++) {
      result3 = closure();
    }
    stopw3.stop();
    print('$title result: ${utf8.decode(result3)}');
    print('$title time: ${stopw3.elapsed}');
  }
}
