import 'unormdata.dart';
import 'utils.dart';

final _defaultFeature = <Object?>[null, 0, <int, Object>{}];
const _cacheThreshold = 10;
const _sBase = 0xAC00;
const _lBase = 0x1100;
const _vBase = 0x1161;
const _tBase = 0x11A7;
const _lCount = 19;
const _vCount = 21;
const _tCount = 28;
const _nCount = _vCount * _tCount;
const _sCount = _lCount * _nCount;

bool _initialized = false;
final Map<int, UChar> _cache = <int, UChar>{};
final List<int> _cacheCounter = <int>[];

void initUCharCache() {
  if (_initialized) {
    return;
  }
  for (int i = 0; i <= 0xFF; i++) {
    _cacheCounter.add(0);
  }
  _initialized = true;
}

typedef NextFunc = UChar Function(int, bool);

UChar _fromCache(NextFunc? next, int cp, bool needFeature) {
  UChar? ret = _cache[cp];
  if (ret == null) {
    ret = next!(cp, needFeature);
    if (ret.feature != null &&
        ++_cacheCounter[(cp >> 8) & 0xFF] > _cacheThreshold) {
      _cache[cp] = ret;
    }
  }
  return ret;
}

UChar _fromData(NextFunc? next, int cp, bool needFeature) {
  final hash = cp & 0xFF00;
  final dunit = unormdata[hash] ?? {};
  final f = dunit[cp];
  return f != null ? UChar(cp, f) : UChar(cp, _defaultFeature);
}

UChar _fromCpOnly(NextFunc? next, int cp, bool needFeature) {
  return needFeature ? next!(cp, needFeature) : UChar(cp, null);
}

UChar _fromRuleBasedJamo(NextFunc? next, int cp, bool needFeature) {
  if (cp < _lBase ||
      (_lBase + _lCount <= cp && cp < _sBase) ||
      (_sBase + _sCount < cp)) {
    return next!(cp, needFeature);
  }
  if (_lBase <= cp && cp < _lBase + _lCount) {
    final c = <int, Object>{};
    final base = (cp - _lBase) * _vCount;
    for (int i = 0; i < _vCount; ++i) {
      c[_vBase + i] = _sBase + _tCount * (i + base);
    }
    return UChar(cp, [null, null, c]);
  }

  final sIndex = cp - _sBase;
  final tIndex = sIndex % _tCount;
  final feature = List<dynamic>.filled(3, null, growable: false);
  if (tIndex != 0) {
    feature[0] = [_sBase + sIndex - tIndex, _tBase + tIndex];
    feature[1] = null;
    feature[2] = null;
  } else {
    feature[0] = [
      _lBase + (sIndex / _nCount).floor(),
      _vBase + ((sIndex % _nCount) / _tCount).floor()
    ];
    feature[1] = null;
    feature[2] = <int, int>{};
    for (int j = 1; j < _tCount; ++j) {
      feature[2][_tBase + j] = cp + j;
    }
  }
  return UChar(cp, feature);
}

UChar _fromCpFilter(NextFunc? next, int cp, bool needFeature) {
  return cp < 60 || 13311 < cp && cp < 42607
      ? UChar(cp, _defaultFeature)
      : next!(cp, needFeature);
}

final Function _fromCharCode = reduceRight(
    [_fromCpFilter, _fromCache, _fromCpOnly, _fromRuleBasedJamo, _fromData],
    (next, strategy, int index, List list) {
  return (int cp, bool needFeature) {
    return strategy(next, cp, needFeature);
  };
}, null);

class UChar {
  final int codepoint;
  List<Object?>? _feature;

  List<Object?>? get feature => _feature;

  UChar(this.codepoint, this._feature);

  void prepareFeature() {
    if (feature == null) {
      _feature = UChar.fromCharCode(codepoint, true)!.feature;
    }
  }

  @override
  String toString() {
    if (codepoint < 0x10000) {
      return String.fromCharCode(codepoint);
    } else {
      final x = codepoint - 0x10000;
      return String.fromCharCodes(
          [(x / 0x400).floor() + 0xD800, x % 0x400 + 0xDC00]);
    }
  }

  List<int>? getDecomp() {
    prepareFeature();
    return _feature![0] as List<int>?;
  }

  bool isCompatibility() {
    prepareFeature();
    final int? feature1 = _feature![1] as int?;
    return feature1 != null && feature1 > 0 && (feature1 & (1 << 8)) > 0;
  }

  bool isExclude() {
    prepareFeature();
    final int? feature1 = _feature![1] as int?;
    return feature1 != null && feature1 > 0 && (feature1 & (1 << 9)) > 0;
  }

  int getCanonicalClass() {
    prepareFeature();
    final int? feature1 = _feature![1] as int?;
    return feature1 != null && feature1 > 0 ? feature1 & 0xFF : 0;
  }

  UChar? getComposite(UChar following) {
    prepareFeature();
    final Map<dynamic, dynamic>? feature2 = _feature![2] as Map<dynamic, dynamic>?;
    if (feature2 == null) {
      return null;
    }
    final int? cp = feature2[following.codepoint];
    return cp != null && cp > 0 ? UChar.fromCharCode(cp, false) : null;
  }

  static UChar? fromCharCode(int cp, bool needFeature) =>
      _fromCharCode(cp, needFeature);

  static bool isHighSurrogate(int cp) {
    return cp >= 0xD800 && cp <= 0xDBFF;
  }

  static bool isLowSurrogate(int cp) {
    return cp >= 0xDC00 && cp <= 0xDFFF;
  }
}
