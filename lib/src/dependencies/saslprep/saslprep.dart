import 'dart:typed_data';

import '../unorm-dart/unorm_dart_export.dart' as unorm;

import 'code_points/bidirectional_l.dart';
import 'code_points/bidirectional_r_al.dart';
import 'code_points/commonly_mapped_to_nothing.dart';
import 'code_points/non_ASCII_space_characters.dart';
import 'code_points/prohibited_characters.dart';
import 'code_points/unassigned.dart';
import 'saslprep_options.dart';

class Saslprep {
  /// Convert provided string into an array of Unicode Code Points.
  /// Based on https://stackoverflow.com/a/21409165/1556249
  /// and https://www.npmjs.com/package/code-point-at.
  static Uint32List toCodePoints(String input) {
    var codePoints = Uint32List(input.length);
    var sizeOffset = 0;
    var codePointIndex = 0;
    for (var i = 0; i < input.length; i++) {
      var before = input.codeUnitAt(i);

      if (before >= 0xd800 && before <= 0xdbff && input.length > i + 1) {
        var next = input.codeUnitAt(i + 1);

        if (next >= 0xdc00 && next <= 0xdfff) {
          codePoints[codePointIndex++] =
              ((before - 0xd800) * 0x400 + next - 0xdc00 + 0x10000);
          i++;
          sizeOffset++;
          continue;
        }
      }
      codePoints[codePointIndex++] = (before);
    }
    codePoints = codePoints.sublist(0, codePoints.length - sizeOffset);
    return codePoints;
  }

  /// This computes the saslprep algorithm. to allow allow unassigned use the
  /// [options] and set [options.allowUnassigned] to true
  static String saslprep(String input, {SaslprepOptions? options}) {
    if (input.isEmpty) {
      return '';
    }

    // 1. Map
    var mapped_input = toCodePoints(input)
        // 1.1 mapping to space
        .map((character) =>
            (non_ASCII_space_characters.contains(character) ? 0x20 : character))
        // 1.2 mapping to nothing
        .where((character) => !commonly_mapped_to_nothing.contains(character));

    // 2. Normalize
    var normalized_input = unorm.nfkc(String.fromCharCodes(mapped_input));

    var normalized_map = toCodePoints(normalized_input);

    // 3. Prohibit
    var hasProhibited = normalized_map
        .any((character) => prohibited_characters.contains(character));

    if (hasProhibited) {
      throw Exception(
          'Prohibited character, see https://tools.ietf.org/html/rfc4013#section-2.3');
    }

    // Unassigned Code Points
    if (options == null || options.allowUnassigned != true) {
      var hasUnassigned = normalized_map
          .any((character) => unassigned_code_points.contains(character));
      if (hasUnassigned) {
        throw Exception(
            'Unassigned code point, see https://tools.ietf.org/html/rfc4013#section-2.5');
      }
    }

    // 4. check bidi
    var hasBidiRAL = normalized_map
        .any((character) => bidirectional_r_al.contains(character));
    var hasBidiL =
        normalized_map.any((character) => bidirectional_l.contains(character));

    // 4.1 If a string contains any RandALCat character, the string MUST NOT
    // contain any LCat character.
    if (hasBidiRAL && hasBidiL) {
      throw Exception(
          'String must not contain RandALCat and LCat at the same time, see https://tools.ietf.org/html/rfc3454#section-6');
    }

    //4.2 If a string contains any RandALCat character, a RandALCat
    //character MUST be the first character of the string, and a
    //RandALCat character MUST be the last character of the string.
    var isFirstBidiRAL =
        bidirectional_r_al.contains(normalized_input.codeUnitAt(0));
    var isLastBidiRAL = bidirectional_r_al
        .contains(normalized_input.codeUnitAt(normalized_input.length - 1));

    if (hasBidiRAL && !(isFirstBidiRAL && isLastBidiRAL)) {
      throw Exception(
          'Bidirectional RandALCat character must be the first and the last character of the string, see https://tools.ietf.org/html/rfc3454#section-6');
    }

    return normalized_input;
  }
}
