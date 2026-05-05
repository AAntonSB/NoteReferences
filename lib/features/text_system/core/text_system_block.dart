import 'text_mark.dart';
import 'text_system_range.dart';

enum TextSystemBlockType {
  paragraph,
  heading,
  listItem,
  todo,
  quote,
  code,
  divider,
  custom,
}

TextSystemBlockType _textSystemBlockTypeFromName(String? name) {
  return TextSystemBlockType.values.firstWhere(
    (type) => type.name == name,
    orElse: () => TextSystemBlockType.paragraph,
  );
}

/// One structured block in the reusable text system.
///
/// A todo field may only need one paragraph block. A premium writer document can
/// compose many blocks. Source-aware formats can map these blocks to source
/// ranges through adapters without making source concepts global.
class TextSystemBlock {
  const TextSystemBlock({
    required this.id,
    required this.type,
    required this.text,
    this.marks = const <TextMark>[],
    this.level,
    this.checked,
    this.metadata = const <String, Object?>{},
  });

  factory TextSystemBlock.paragraph({
    required String id,
    required String text,
    List<TextMark> marks = const <TextMark>[],
  }) {
    return TextSystemBlock(
      id: id,
      type: TextSystemBlockType.paragraph,
      text: text,
      marks: marks,
    );
  }

  factory TextSystemBlock.fromJson(Map<String, Object?> json) {
    return TextSystemBlock(
      id: json['id'] as String? ?? 'block',
      type: _textSystemBlockTypeFromName(json['type'] as String?),
      text: json['text'] as String? ?? '',
      marks: (json['marks'] as List? ?? const <Object?>[])
          .whereType<Map>()
          .map((mark) => TextMark.fromJson(Map<String, Object?>.from(mark)))
          .toList(),
      level: (json['level'] as num?)?.toInt(),
      checked: json['checked'] as bool?,
      metadata: Map<String, Object?>.from(json['metadata'] as Map? ?? const <String, Object?>{}),
    ).normalizeMarks();
  }

  final String id;
  final TextSystemBlockType type;
  final String text;
  final List<TextMark> marks;
  final int? level;
  final bool? checked;
  final Map<String, Object?> metadata;

  int get length => text.length;
  TextSystemRange get fullRange => TextSystemRange(0, text.length);

  TextSystemBlock copyWith({
    String? id,
    TextSystemBlockType? type,
    String? text,
    List<TextMark>? marks,
    int? level,
    bool? checked,
    Map<String, Object?>? metadata,
  }) {
    return TextSystemBlock(
      id: id ?? this.id,
      type: type ?? this.type,
      text: text ?? this.text,
      marks: marks ?? this.marks,
      level: level ?? this.level,
      checked: checked ?? this.checked,
      metadata: metadata ?? this.metadata,
    );
  }

  TextSystemBlock normalizeMarks() {
    final normalized = marks
        .map((mark) => mark.clamp(text.length))
        .where((mark) => !mark.isEmpty)
        .toList()
      ..sort((a, b) {
        final startCompare = a.range.start.compareTo(b.range.start);
        if (startCompare != 0) return startCompare;
        return a.range.end.compareTo(b.range.end);
      });

    return copyWith(marks: normalized);
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'type': type.name,
      'text': text,
      if (marks.isNotEmpty) 'marks': marks.map((mark) => mark.toJson()).toList(),
      if (level != null) 'level': level,
      if (checked != null) 'checked': checked,
      if (metadata.isNotEmpty) 'metadata': metadata,
    };
  }
}
