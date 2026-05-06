import 'text_system_document_position.dart';

/// Half-open selection range in document coordinates.
///
/// The user experience remains fluent text. This range exists so the engine can
/// map a future cross-paragraph selection back onto structured internal text
/// units without exposing those units as the editing model.
class TextSystemDocumentRange {
  const TextSystemDocumentRange({
    required this.start,
    required this.end,
  });

  factory TextSystemDocumentRange.collapsed(TextSystemDocumentPosition position) {
    return TextSystemDocumentRange(start: position, end: position);
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

  bool get isCollapsed => start == end;

  TextSystemDocumentRange normalized() {
    return start.compareTo(end) <= 0 ? this : TextSystemDocumentRange(start: end, end: start);
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'start': start.toJson(),
      'end': end.toJson(),
    };
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
