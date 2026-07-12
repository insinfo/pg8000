import 'dart:typed_data';

// The 0x80..0x9f portion of the Windows-1252 code page. A negative entry is
// undefined by the code page and is rejected instead of being silently
// replaced. Bytes outside this range map directly to the same Unicode value.
const List<int> _windows1252CodePoints = <int>[
  0x20ac,
  -1,
  0x201a,
  0x0192,
  0x201e,
  0x2026,
  0x2020,
  0x2021,
  0x02c6,
  0x2030,
  0x0160,
  0x2039,
  0x0152,
  -1,
  0x017d,
  -1,
  -1,
  0x2018,
  0x2019,
  0x201c,
  0x201d,
  0x2022,
  0x2013,
  0x2014,
  0x02dc,
  0x2122,
  0x0161,
  0x203a,
  0x0153,
  -1,
  0x017e,
  0x0178,
];

/// Decodes strict Windows-1252 without allocating an intermediate buffer for
/// the common ASCII/Latin-1-only path.
String decodeWindows1252(List<int> bytes) {
  var firstMappedByte = -1;

  for (var i = 0; i < bytes.length; i++) {
    final byte = bytes[i];
    if ((byte & ~0xff) != 0) {
      throw FormatException('Invalid Windows-1252 byte $byte at offset $i.');
    }
    if (byte >= 0x80 && byte <= 0x9f) {
      firstMappedByte = i;
      break;
    }
  }

  if (firstMappedByte < 0) return String.fromCharCodes(bytes);

  final codeUnits = Uint16List(bytes.length);
  for (var i = 0; i < firstMappedByte; i++) {
    codeUnits[i] = bytes[i];
  }
  for (var i = firstMappedByte; i < bytes.length; i++) {
    final byte = bytes[i];
    if ((byte & ~0xff) != 0) {
      throw FormatException('Invalid Windows-1252 byte $byte at offset $i.');
    }
    if (byte >= 0x80 && byte <= 0x9f) {
      final codePoint = _windows1252CodePoints[byte - 0x80];
      if (codePoint < 0) {
        throw FormatException(
            'Undefined Windows-1252 byte 0x${byte.toRadixString(16)} at offset $i.');
      }
      codeUnits[i] = codePoint;
    } else {
      codeUnits[i] = byte;
    }
  }
  return String.fromCharCodes(codeUnits);
}

/// Encodes strict Windows-1252 in one pass and one fixed-size allocation.
Uint8List encodeWindows1252(String text) {
  final bytes = Uint8List(text.length);
  for (var i = 0; i < text.length; i++) {
    final codeUnit = text.codeUnitAt(i);
    if (codeUnit <= 0x7f || (codeUnit >= 0xa0 && codeUnit <= 0xff)) {
      bytes[i] = codeUnit;
      continue;
    }

    final byte = _mappedWindows1252Byte(codeUnit);
    if (byte < 0) {
      throw FormatException(
          'Character U+${codeUnit.toRadixString(16).toUpperCase().padLeft(4, '0')} cannot be encoded as Windows-1252 at offset $i.');
    }
    bytes[i] = byte;
  }
  return bytes;
}

int _mappedWindows1252Byte(int codeUnit) {
  switch (codeUnit) {
    case 0x20ac:
      return 0x80;
    case 0x201a:
      return 0x82;
    case 0x0192:
      return 0x83;
    case 0x201e:
      return 0x84;
    case 0x2026:
      return 0x85;
    case 0x2020:
      return 0x86;
    case 0x2021:
      return 0x87;
    case 0x02c6:
      return 0x88;
    case 0x2030:
      return 0x89;
    case 0x0160:
      return 0x8a;
    case 0x2039:
      return 0x8b;
    case 0x0152:
      return 0x8c;
    case 0x017d:
      return 0x8e;
    case 0x2018:
      return 0x91;
    case 0x2019:
      return 0x92;
    case 0x201c:
      return 0x93;
    case 0x201d:
      return 0x94;
    case 0x2022:
      return 0x95;
    case 0x2013:
      return 0x96;
    case 0x2014:
      return 0x97;
    case 0x02dc:
      return 0x98;
    case 0x2122:
      return 0x99;
    case 0x0161:
      return 0x9a;
    case 0x203a:
      return 0x9b;
    case 0x0153:
      return 0x9c;
    case 0x017e:
      return 0x9e;
    case 0x0178:
      return 0x9f;
    default:
      return -1;
  }
}
