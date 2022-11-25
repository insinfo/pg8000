//Windows OU openbsd
//https://github.com/tpn/winsdk-10/blob/master/Include/10.0.10240.0/um/WinSock2.h
import 'dart:async';
import 'dart:convert';
//import 'dart:cli';
import 'dart:io';

import 'package:convert/convert.dart';
import 'package:crypto/crypto.dart';

const WINDOWS_SO_KEEPALIVE = 0x0008; //8 keep connections alive
const WINDOWS_SOL_SOCKET = 0xffff; //65535 options for socket level

//https://chromium.googlesource.com/native_client/linux-headers-for-nacl/+/2dc04f8190a54defc0d59e693fa6cff3e8a916a9/include/asm/socket.h
//Linux #define SOL_SOCKET	1 ?
//#define SO_KEEPALIVE	9

const LINUX_SOL_SOCKET = 0x1; //1;
const LINUX_SO_KEEPALIVE = 0x0009; //9;

class Utils {
  static void enableKeepalive(Socket socket) {
    // Enable keepalive probes every 60 seconds with 3 retries each 10 seconds
    final keepaliveEnabled = true;
    final keepaliveInterval = 60;
    final keepaliveSuccessiveInterval = 10;
    final keepaliveSuccessiveCount = 3;

    if (Platform.isIOS || Platform.isMacOS) {
      final enableKeepaliveOption = RawSocketOption.fromBool(
          0xffff, // SOL_SOCKET
          0x0008, // SO_KEEPALIVE
          keepaliveEnabled);
      final keepaliveIntervalOption = RawSocketOption.fromInt(
          6, // IPPROTO_TCP
          0x10, // TCP_KEEPALIVE
          keepaliveInterval);
      final keepaliveSuccessiveIntervalOption = RawSocketOption.fromInt(
        6, // IPPROTO_TCP
        0x101, // TCP_KEEPINTVL
        keepaliveSuccessiveInterval,
      );
      final keepaliveusccessiveCountOption = RawSocketOption.fromInt(
          6, // IPPROTO_TCP
          0x102, // TCP_KEEPCNT
          keepaliveSuccessiveCount);

      socket.setRawOption(enableKeepaliveOption);
      socket.setRawOption(keepaliveIntervalOption);
      socket.setRawOption(keepaliveSuccessiveIntervalOption);
      socket.setRawOption(keepaliveusccessiveCountOption);
    } else if (Platform.isAndroid) {
      final enableKeepaliveOption = RawSocketOption.fromBool(
          0x1, // SOL_SOCKET
          0x0009, // SO_KEEPALIVE
          keepaliveEnabled);
      final keepaliveIntervalOption = RawSocketOption.fromInt(
          6, // IPPROTO_TCP
          4, // TCP_KEEPIDLE
          keepaliveInterval);
      final keepaliveSuccessiveIntervalOption = RawSocketOption.fromInt(
        6, // IPPROTO_TCP
        5, // TCP_KEEPINTVL
        keepaliveSuccessiveInterval,
      );
      final keepaliveusccessiveCountOption = RawSocketOption.fromInt(
          6, // IPPROTO_TCP
          6, // TCP_KEEPCNT
          keepaliveSuccessiveCount);

      socket.setRawOption(enableKeepaliveOption);
      socket.setRawOption(keepaliveIntervalOption);
      socket.setRawOption(keepaliveSuccessiveIntervalOption);
      socket.setRawOption(keepaliveusccessiveCountOption);
    }
  }

  ///para teste apenas
  ///https://api.dart.dev/stable/2.3.1/dart-cli/waitFor.html
  T waitFor2<T>(Future<T> future, {Duration timeout}) {
    T result;
    bool futureCompleted = false;
    Object error;
    StackTrace stacktrace;

    future.then((r) {
      futureCompleted = true;
      result = r;
    }, onError: (e, st) {
      error = e;
      stacktrace = st;
    });

    Stopwatch s;
    if (timeout != null) {
      s = new Stopwatch()..start();
    }
    Timer.run(() {}); // Enusre there is at least one message.
    while (!futureCompleted && (error == null)) {
      Duration remaining;
      if (timeout != null) {
        if (s.elapsed >= timeout) {
          throw new TimeoutException("waitFor() timed out", timeout);
        }
        remaining = timeout - s.elapsed;
      }
      //_WaitForUtils.waitForEvent(timeout: remaining);
    }
    if (timeout != null) {
      s.stop();
    }
    Timer.run(() {}); // Ensure that previous calls to waitFor are woken up.

    if (error != null) {
      throw new AsyncError(error, stacktrace);
    }

    return result;
  }

  ///retorna o tamanho de uma lista
  static int len(List list) {
    if (list == null) {
      return 0;
    }
    return list.length;
  }

  /// https://ptyagicodecamp.github.io/dart-generators.html
  /// gera uma sequencia serial sobre demanda
  static Iterable<int> sequence([int firstval = -1, step = 1]) sync* {
    var x = firstval;
    while (true) {
      yield x += step;
    }
  }

  /// [num] tem que ser maior que 0
  static Iterable<int> countDownFromSync(int num) sync* {
    while (num > 0) {
      yield num--;
    }
  }

  ///[str] is converted to ascii bytes
  /// return md5 hex String
  static String md5HexStr(String str) {
    var hexdigest = hex.encode(md5.convert(ascii.encode(str)).bytes);
    return hexdigest;
  }

  ///[bytes] is ascii bytes
  /// return ascii bytes of hex of md5
  static List<int> md5HexBytesAscii(List<int> bytes) {
    var hexdigest = hex.encode(md5.convert(bytes).bytes);
    return ascii.encode(hexdigest);
  }

  ///https://github.com/dart-lang/sdk/issues/29837
  /// split list by
  static List<List<T>> splitList<T>(List<T> list, dynamic splitBy) {
    var results = <List<T>>[];
    var result = <T>[];
    //var count = 0;
    for (var item in list) {
      if (item == splitBy) {
        results.add(result);
        result = [];
      } else {
        result.add(item);
      }
    }

    return results;
  }

  static String itoa(int c) {
    try {
      return String.fromCharCodes([c]);
    } catch (ex) {
      return 'Invalid';
    }
  }
}
