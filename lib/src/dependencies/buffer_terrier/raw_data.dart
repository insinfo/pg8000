import 'raw_reader.dart';
import 'raw_writer.dart';
import 'raw_value.dart';

/// A simple [RawEncodable] that holds bytes.
class RawData extends RawEncodable {
  static final RawData empty = RawData(const []);

  final List<int> bytes;

  const RawData(this.bytes);

  factory RawData.decode(RawReader reader, int length) {
    if (length == 0) {
      return empty;
    }
    return RawData(reader.readUint8ListViewOrCopy(length));
  }

  @override
  int encodeRawCapacity() => bytes.length;

  @override
  void encodeRaw(RawWriter writer) {
    writer.writeBytes(bytes);
  }

  String toString() => "[Raw data with length ${bytes.length}]";
}
