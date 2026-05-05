/// Half-open text range used by the project-wide text system: [start, end).
class TextSystemRange {
  const TextSystemRange(this.start, this.end)
      : assert(start >= 0),
        assert(end >= start);

  factory TextSystemRange.collapsed(int offset) => TextSystemRange(offset, offset);

  factory TextSystemRange.fromJson(Map<String, Object?> json) {
    final start = ((json['start'] as num?)?.toInt() ?? 0).clamp(0, 1 << 31).toInt();
    final rawEnd = ((json['end'] as num?)?.toInt() ?? start).clamp(0, 1 << 31).toInt();
    final end = rawEnd < start ? start : rawEnd;
    return TextSystemRange(start, end);
  }

  final int start;
  final int end;

  int get length => end - start;
  bool get isCollapsed => start == end;

  bool containsOffset(int offset) => offset >= start && offset < end;

  bool containsRange(TextSystemRange other) =>
      other.start >= start && other.end <= end;

  bool overlaps(TextSystemRange other) => start < other.end && other.start < end;

  TextSystemRange? intersection(TextSystemRange other) {
    final nextStart = start > other.start ? start : other.start;
    final nextEnd = end < other.end ? end : other.end;
    if (nextStart >= nextEnd) return null;
    return TextSystemRange(nextStart, nextEnd);
  }

  TextSystemRange shift(int delta) => TextSystemRange(start + delta, end + delta);

  TextSystemRange clamp(int textLength) {
    final safeStart = start.clamp(0, textLength).toInt();
    final safeEnd = end.clamp(safeStart, textLength).toInt();
    return TextSystemRange(safeStart, safeEnd);
  }

  TextSystemRange relativeTo(int offset) => TextSystemRange(start - offset, end - offset);

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'start': start,
      'end': end,
    };
  }

  @override
  String toString() => 'TextSystemRange($start, $end)';

  @override
  bool operator ==(Object other) =>
      other is TextSystemRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);
}
