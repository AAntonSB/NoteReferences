/// A half-open range in a source string: [start, end).
///
/// This is intentionally small and dependency-free because it is the basic
/// currency used by source-aware editors, parsers, renderers, and source edit
/// transactions.
class SourceRange {
  const SourceRange(this.start, this.end)
      : assert(start >= 0),
        assert(end >= start);

  final int start;
  final int end;

  int get length => end - start;
  bool get isCollapsed => start == end;

  bool containsOffset(int offset) => offset >= start && offset < end;

  bool containsRange(SourceRange other) =>
      other.start >= start && other.end <= end;

  SourceRange shift(int delta) => SourceRange(start + delta, end + delta);

  SourceRange clamp(int sourceLength) {
    final safeStart = start.clamp(0, sourceLength).toInt();
    final safeEnd = end.clamp(safeStart, sourceLength).toInt();
    return SourceRange(safeStart, safeEnd);
  }

  @override
  String toString() => 'SourceRange($start, $end)';

  @override
  bool operator ==(Object other) =>
      other is SourceRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);
}
