import 'dart:typed_data';

Uint8List coerceUint8List(List<int> list) =>
    list is Uint8List ? list : Uint8List.fromList(list);
