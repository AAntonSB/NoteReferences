import 'text_system_document_position.dart';

/// Half-open selection/operation range in document coordinates.
///
/// The editor should treat this as the model-layer representation of a span of
/// document content. Visual selection overlays, comments, source links,
/// citations, copy/cut/delete, and future AI actions should eventually operate
/// on this type rather than on widget-local selections.
class TextSystemDocumentRange {
  const TextSystemDocumentRange({
    required this.start,
    required this.end,
  });

  factory TextSystemDocumentRange.collapsed(TextSystemDocumentPosition position) {
    return TextSystemDocumentRange(start: position, end: position);
  }

  /// Builds a range from user-interaction anchor/focus positions. The resulting
  /// range keeps the supplied direction; call [normalized] when document-order
  /// start/end is required.
  factory TextSystemDocumentRange.fromAnchorFocus({
    required TextSystemDocumentPosition anchor,
    required TextSystemDocumentPosition focus,
  }) {
    return TextSystemDocumentRange(start: anchor, end: focus);
  }

  factory TextSystemDocumentRange.fromJson(Map<String, Object?> json) {
    return TextSystemDocumentRange(
      start: TextSystemDocumentPosition.fromJson(
        Map<String, Object?>.from(json['start'] as Map? ?? const <String, Object?>{}),
      ),
      end: TextSystemDocumentPosition.fromJson(
        Map<String, Object?>.from(json['end'] as Map? ?? const <String, Object?>{}),
      ),
    );
  }

  final TextSystemDocumentPosition start;
  final TextSystemDocumentPosition end;

  /// The original interaction anchor. This alias lets the existing start/end
  /// shape work as the first phase of a later anchor/focus selection model.
  TextSystemDocumentPosition get anchor => start;

  /// The current interaction focus. This alias lets the existing start/end
  /// shape work as the first phase of a later anchor/focus selection model.
  TextSystemDocumentPosition get focus => end;

  bool get isCollapsed => start == end;
  bool get isForward => start.compareTo(end) <= 0;
  bool get isBackward => !isForward;
  bool get spansMultipleBlocks => start.blockId != end.blockId;
  bool get touchesObjectPosition => start.isOnBlock || end.isOnBlock;
  bool get touchesInlineAtom => start.isInlineAtom || end.isInlineAtom;
  bool get touchesTableCell => start.isTableCell || end.isTableCell;

  TextSystemDocumentRange normalized() {
    return isForward ? this : TextSystemDocumentRange(start: end, end: start);
  }

  bool containsPosition(TextSystemDocumentPosition position) {
    final range = normalized();
    return range.start.compareTo(position) <= 0 && position.compareTo(range.end) <= 0;
  }

  bool containsBlockIndex(int blockIndex) {
    final range = normalized();
    return blockIndex >= range.start.blockIndex && blockIndex <= range.end.blockIndex;
  }

  TextSystemDocumentRange collapseToStart() {
    final range = normalized();
    return TextSystemDocumentRange.collapsed(range.start);
  }

  TextSystemDocumentRange collapseToEnd() {
    final range = normalized();
    return TextSystemDocumentRange.collapsed(range.end);
  }

  TextSystemDocumentRange copyWith({
    TextSystemDocumentPosition? start,
    TextSystemDocumentPosition? end,
  }) {
    return TextSystemDocumentRange(
      start: start ?? this.start,
      end: end ?? this.end,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'start': start.toJson(),
      'end': end.toJson(),
    };
  }

  String get diagnosticLabel {
    final range = normalized();
    if (range.isCollapsed) return 'collapsed:${range.start.diagnosticLabel}';
    return '${range.start.diagnosticLabel} → ${range.end.diagnosticLabel}';
  }

  @override
  String toString() => 'TextSystemDocumentRange(start: $start, end: $end)';

  @override
  bool operator ==(Object other) {
    return other is TextSystemDocumentRange && other.start == start && other.end == end;
  }

  @override
  int get hashCode => Object.hash(start, end);
}

/// Absolute half-open offset range in flattened document text.
class TextSystemDocumentOffsetRange {
  const TextSystemDocumentOffsetRange(this.start, this.end)
      : assert(start >= 0),
        assert(end >= start);

  final int start;
  final int end;

  int get length => end - start;
  bool get isCollapsed => start == end;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'start': start,
      'end': end,
    };
  }

  @override
  String toString() => 'TextSystemDocumentOffsetRange($start, $end)';
}
