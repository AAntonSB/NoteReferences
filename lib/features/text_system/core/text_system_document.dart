import 'text_system_block.dart';

/// Project-wide structured text document.
///
/// This is deliberately format-neutral: it can back a tiny note field, a normal
/// rich text document, a LaTeX-aware adapter, or the future premium writer.
class TextSystemDocument {
  const TextSystemDocument({
    required this.id,
    required this.title,
    required this.blocks,
    this.metadata = const <String, Object?>{},
    this.createdAt,
    this.updatedAt,
  });

  factory TextSystemDocument.singleParagraph({
    required String id,
    required String title,
    required String text,
  }) {
    final now = DateTime.now();
    return TextSystemDocument(
      id: id,
      title: title,
      blocks: <TextSystemBlock>[
        TextSystemBlock.paragraph(id: 'paragraph-1', text: text),
      ],
      createdAt: now,
      updatedAt: now,
    );
  }

  factory TextSystemDocument.fromJson(Map<String, Object?> json) {
    DateTime? parseDate(Object? value) {
      if (value is String && value.isNotEmpty) return DateTime.tryParse(value);
      return null;
    }

    return TextSystemDocument(
      id: json['id'] as String? ?? 'document',
      title: json['title'] as String? ?? 'Untitled',
      blocks: (json['blocks'] as List? ?? const <Object?>[])
          .whereType<Map>()
          .map((block) => TextSystemBlock.fromJson(Map<String, Object?>.from(block)))
          .toList(),
      metadata: Map<String, Object?>.from(json['metadata'] as Map? ?? const <String, Object?>{}),
      createdAt: parseDate(json['createdAt']),
      updatedAt: parseDate(json['updatedAt']),
    );
  }

  final String id;
  final String title;
  final List<TextSystemBlock> blocks;
  final Map<String, Object?> metadata;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  String get plainText => blocks.map((block) => block.text).join('\n');

  TextSystemBlock? blockById(String id) {
    for (final block in blocks) {
      if (block.id == id) return block;
    }
    return null;
  }

  TextSystemDocument copyWith({
    String? id,
    String? title,
    List<TextSystemBlock>? blocks,
    Map<String, Object?>? metadata,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return TextSystemDocument(
      id: id ?? this.id,
      title: title ?? this.title,
      blocks: blocks ?? this.blocks,
      metadata: metadata ?? this.metadata,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  TextSystemDocument replaceBlock(TextSystemBlock block) {
    return copyWith(
      blocks: <TextSystemBlock>[
        for (final existing in blocks) existing.id == block.id ? block : existing,
      ],
      updatedAt: DateTime.now(),
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'title': title,
      'blocks': blocks.map((block) => block.toJson()).toList(),
      if (metadata.isNotEmpty) 'metadata': metadata,
      if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
      if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
    };
  }
}
