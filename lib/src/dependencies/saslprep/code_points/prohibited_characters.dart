import 'non_ASCII_space_characters.dart';

/// 2.3.  Prohibited Output
var prohibited_characters = non_ASCII_space_characters +
    [
      // C.2.1 ASCII control characters
      // https://tools.ietf.org/html/rfc3454#appendix-C.2.1
      for (var i = 0; i <= 0x001f; i++) i /* [CONTROL CHARACTERS] */,
      0x007f /* DELETE */,

      // C.2.2 Non-ASCII control characters
      // https://tools.ietf.org/html/rfc3454#appendix-C.2.2
      for (var i = 0x0080; i <= 0x009f; i++) i /* [CONTROL CHARACTERS] */,
      0x06dd /* ARABIC END OF AYAH */,
      0x070f /* SYRIAC ABBREVIATION MARK */,
      0x180e /* MONGOLIAN VOWEL SEPARATOR */,
      0x200c /* ZERO WIDTH NON-JOINER */,
      0x200d /* ZERO WIDTH JOINER */,
      0x2028 /* LINE SEPARATOR */,
      0x2029 /* PARAGRAPH SEPARATOR */,
      0x2060 /* WORD JOINER */,
      0x2061 /* FUNCTION APPLICATION */,
      0x2062 /* INVISIBLE TIMES */,
      0x2063 /* INVISIBLE SEPARATOR */,
      for (var i = 0x206a; i <= 0x206f; i++) i /* [CONTROL CHARACTERS] */,
      0xfeff /* ZERO WIDTH NO-BREAK SPACE */,
      for (var i = 0xfff9; i <= 0xfffc; i++) i /* [CONTROL CHARACTERS] */,
      for (var i = 0x1d173; i <= 0x1d17a; i++)
        i /* [MUSICAL CONTROL CHARACTERS] */,

      // C.3 Private use
      // https://tools.ietf.org/html/rfc3454#appendix-C.3
      for (var i = 0xe000; i <= 0xf8ff; i++) i /* [PRIVATE USE, PLANE 0] */,
      for (var i = 0xf0000; i <= 0xffffd; i++) i /* [PRIVATE USE, PLANE 15] */,
      for (var i = 0x100000; i <= 0x10fffd; i++)
        i /* [PRIVATE USE, PLANE 16] */,

      // C.4 Non-character code points
      // https://tools.ietf.org/html/rfc3454#appendix-C.4
      for (var i = 0xfdd0; i <= 0xfdef; i++) i /* [NONCHARACTER CODE POINTS] */,
      for (var i = 0xfffe; i <= 0xffff; i++) i /* [NONCHARACTER CODE POINTS] */,
      for (var i = 0x1fffe; i <= 0x1ffff; i++)
        i /* [NONCHARACTER CODE POINTS] */,
      for (var i = 0x2fffe; i <= 0x2ffff; i++)
        i /* [NONCHARACTER CODE POINTS] */,
      for (var i = 0x3fffe; i <= 0x3ffff; i++)
        i /* [NONCHARACTER CODE POINTS] */,
      for (var i = 0x4fffe; i <= 0x4ffff; i++)
        i /* [NONCHARACTER CODE POINTS] */,
      for (var i = 0x5fffe; i <= 0x5ffff; i++)
        i /* [NONCHARACTER CODE POINTS] */,
      for (var i = 0x6fffe; i <= 0x6ffff; i++)
        i /* [NONCHARACTER CODE POINTS] */,
      for (var i = 0x7fffe; i <= 0x7ffff; i++)
        i /* [NONCHARACTER CODE POINTS] */,
      for (var i = 0x8fffe; i <= 0x8ffff; i++)
        i /* [NONCHARACTER CODE POINTS] */,
      for (var i = 0x9fffe; i <= 0x9ffff; i++)
        i /* [NONCHARACTER CODE POINTS] */,
      for (var i = 0xafffe; i <= 0xaffff; i++)
        i /* [NONCHARACTER CODE POINTS] */,
      for (var i = 0xbfffe; i <= 0xbffff; i++)
        i /* [NONCHARACTER CODE POINTS] */,
      for (var i = 0xcfffe; i <= 0xcffff; i++)
        i /* [NONCHARACTER CODE POINTS] */,
      for (var i = 0xdfffe; i <= 0xdffff; i++)
        i /* [NONCHARACTER CODE POINTS] */,
      for (var i = 0xefffe; i <= 0xeffff; i++)
        i /* [NONCHARACTER CODE POINTS] */,
      for (var i = 0x10fffe; i <= 0x10ffff; i++)
        i /* [NONCHARACTER CODE POINTS] */,

      // C.5 Surrogate codes
      // https://tools.ietf.org/html/rfc3454#appendix-C.5
      for (var i = 0xd800; i <= 0xdfff; i++) i,

      // C.6 Inappropriate for plain text
      // https://tools.ietf.org/html/rfc3454#appendix-C.6
      0xfff9 /* INTERLINEAR ANNOTATION ANCHOR */,
      0xfffa /* INTERLINEAR ANNOTATION SEPARATOR */,
      0xfffb /* INTERLINEAR ANNOTATION TERMINATOR */,
      0xfffc /* OBJECT REPLACEMENT CHARACTER */,
      0xfffd /* REPLACEMENT CHARACTER */,

      // C.7 Inappropriate for canonical representation
      // https://tools.ietf.org/html/rfc3454#appendix-C.7
      for (var i = 0x2ff0; i <= 0x2ffb; i++)
        i /* [IDEOGRAPHIC DESCRIPTION CHARACTERS] */,

      // C.8 Change display properties or are deprecated
      // https://tools.ietf.org/html/rfc3454#appendix-C.8
      0x0340 /* COMBINING GRAVE TONE MARK */,
      0x0341 /* COMBINING ACUTE TONE MARK */,
      0x200e /* LEFT-TO-RIGHT MARK */,
      0x200f /* RIGHT-TO-LEFT MARK */,
      0x202a /* LEFT-TO-RIGHT EMBEDDING */,
      0x202b /* RIGHT-TO-LEFT EMBEDDING */,
      0x202c /* POP DIRECTIONAL FORMATTING */,
      0x202d /* LEFT-TO-RIGHT OVERRIDE */,
      0x202e /* RIGHT-TO-LEFT OVERRIDE */,
      0x206a /* INHIBIT SYMMETRIC SWAPPING */,
      0x206b /* ACTIVATE SYMMETRIC SWAPPING */,
      0x206c /* INHIBIT ARABIC FORM SHAPING */,
      0x206d /* ACTIVATE ARABIC FORM SHAPING */,
      0x206e /* NATIONAL DIGIT SHAPES */,
      0x206f /* NOMINAL DIGIT SHAPES */,

      // C.9 Tagging characters
      // https://tools.ietf.org/html/rfc3454#appendix-C.9
      0xe0001 /* LANGUAGE TAG */,
      for (var i = 0xe0020; i <= 0xe007f; i++) i /* [TAGGING CHARACTERS] */
    ];
