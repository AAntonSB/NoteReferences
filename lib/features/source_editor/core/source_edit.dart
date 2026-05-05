import 'source_range.dart';

/// A source mutation expressed as a range replacement.
///
/// Visual editors should not mutate rendered widgets directly. They should
/// create SourceEdit objects, apply them to the canonical source, and then let
/// the parser derive the next visual state.
class SourceEdit {
  const SourceEdit({required this.range, required this.replacement});

  factory SourceEdit.insert(int offset, String text) => SourceEdit(
        range: SourceRange(offset, offset),
        replacement: text,
      );

  factory SourceEdit.delete(SourceRange range) => SourceEdit(
        range: range,
        replacement: '',
      );

  factory SourceEdit.replace(SourceRange range, String text) => SourceEdit(
        range: range,
        replacement: text,
      );

  final SourceRange range;
  final String replacement;

  int get delta => replacement.length - range.length;

  @override
  String toString() => 'SourceEdit($range, ${replacement.length} chars)';
}

class SourceEditResult {
  const SourceEditResult({
    required this.before,
    required this.after,
    required this.edits,
  });

  final String before;
  final String after;
  final List<SourceEdit> edits;
}
