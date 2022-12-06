import 'package:pg8000/src/pack_unpack.dart';

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

  var stopw3 = Stopwatch()..start();
  var result3;
  for (var i = 0; i < 100000000; i++) {
    // result3 = pack2('ihihih', [
    //   21474830,
    //   32760,
    //   21474830,
    //   32760,
    //   21474830,
    //   32760,
    // ]);

    // result3 = unpack3('ihihih', [
    //   1,
    //   71,
    //   174,
    //   14,
    //   127,
    //   248,
    //   1,
    //   71,
    //   174,
    //   14,
    //   127,
    //   248,
    //   1,
    //   71,
    //   174,
    //   14,
    //   127,
    //   248
    // ]);

    //result3 = ihihih_pack(20, 20, 20, 20, 20, 20);
    result3 = ihihih_unpack(
        [0, 0, 0, 20, 0, 20, 0, 0, 0, 20, 0, 20, 0, 0, 0, 20, 0, 20]);
  }

  stopw3.stop();

  print('result: $result3');
  //result: [1, 71, 174, 14, 127, 248, 1, 71, 174, 14, 127, 248, 1, 71, 174, 14, 127, 248]
  print('pack time: ${stopw3.elapsed}');
}
