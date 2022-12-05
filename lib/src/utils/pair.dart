/// Represents a pair of objects.
/// It is useful for implementing a function returning a pair of objects.
class Pair<F, S> {
  final F first;
  final S second;

  const Pair(this.first, this.second);
  Pair.fromJson(List json) : this(json[0] as F, json[1] as S);

  S get last => second;

  List toJson() => [first, second];

  @override
  int get hashCode => Object.hash(first, second);
  @override
  bool operator ==(Object o) =>
      o is Pair && first == o.first && second == o.second;
  @override
  String toString() => toJson().toString();
}
