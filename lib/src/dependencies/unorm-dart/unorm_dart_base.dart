import 'composite_iterator.dart';
import 'decomposite_iterator.dart';
import 'iterator.dart';
import 'recursive_decomposite_iterator.dart';
import 'uchar.dart';
import 'uchar_iterator.dart';


enum _NormalizeMode { nfd, nfkd, nfc, nfkc }

UnormIterator _createIterator(_NormalizeMode mode, String str) {
  switch (mode) {
    case _NormalizeMode.nfd:
      return DecompositeIterator(
          RecursiveDecompositeIterator(UCharIterator(str), true));
    case _NormalizeMode.nfkd:
      return DecompositeIterator(
          RecursiveDecompositeIterator(UCharIterator(str), false));
    case _NormalizeMode.nfc:
      return CompositeIterator(DecompositeIterator(
          RecursiveDecompositeIterator(UCharIterator(str), true)));
    case _NormalizeMode.nfkc:
      return CompositeIterator(DecompositeIterator(
          RecursiveDecompositeIterator(UCharIterator(str), false)));
  }
}

String _normalize(_NormalizeMode mode, String str) {
  initUCharCache();
  UnormIterator iterator = _createIterator(mode, str);
  String ret = "";
  UChar? uchar;
  while ((uchar = iterator.next()) != null) {
    ret += uchar.toString();
  }
  return ret;
}

/// Normalizes provided [str] with Canonical Decomposition.
String nfd(String str) => _normalize(_NormalizeMode.nfd, str);

/// Normalizes provided [str] with Compatibility Decomposition.
String nfkd(String str) => _normalize(_NormalizeMode.nfkd, str);

/// Normalizes provided [str] with Canonical Decomposition, followed by Canonical Composition.
String nfc(String str) => _normalize(_NormalizeMode.nfc, str);

/// Normalizes provided [str] with Compatibility Decomposition, followed by Canonical Composition.
String nfkc(String str) => _normalize(_NormalizeMode.nfkc, str);
