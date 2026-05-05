import 'source_range.dart';

/// Behavior-level block types. These are intentionally general so the same
/// editor kernel can later power LaTeX, Markdown, rich text, and plain notes.
enum SourceBlockType {
  heading,
  paragraph,
  listItem,
  comment,
  math,
  sourceFallback,
  spacer,
  custom,
}

/// A visual block derived from canonical source.
///
/// The block stores both its full source range and the optional editable range
/// that should be replaced when the user edits the rendered content.
class SourceDocumentBlock {
  const SourceDocumentBlock({
    required this.id,
    required this.type,
    required this.sourceRange,
    required this.text,
    this.editableRange,
    this.level,
    this.metadata = const <String, Object?>{},
  });

  final String id;
  final SourceBlockType type;
  final SourceRange sourceRange;
  final SourceRange? editableRange;
  final String text;
  final int? level;
  final Map<String, Object?> metadata;

  bool get isEditable => editableRange != null;
  bool get isFallback => type == SourceBlockType.sourceFallback;

  SourceDocumentBlock copyWith({
    String? id,
    SourceBlockType? type,
    SourceRange? sourceRange,
    SourceRange? editableRange,
    String? text,
    int? level,
    Map<String, Object?>? metadata,
  }) {
    return SourceDocumentBlock(
      id: id ?? this.id,
      type: type ?? this.type,
      sourceRange: sourceRange ?? this.sourceRange,
      editableRange: editableRange ?? this.editableRange,
      text: text ?? this.text,
      level: level ?? this.level,
      metadata: metadata ?? this.metadata,
    );
  }
}

class ParsedSourceDocument {
  const ParsedSourceDocument({
    required this.source,
    required this.blocks,
    this.errors = const <String>[],
  });

  final String source;
  final List<SourceDocumentBlock> blocks;
  final List<String> errors;
}
