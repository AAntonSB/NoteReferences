import 'text_clipboard_fragment.dart';
import 'text_mark.dart';
import 'text_system_block.dart';
import 'text_system_range.dart';

/// Structured internal copy payload for document-level ranges.
///
/// The existing [TextClipboardFragment] is intentionally lightweight and works
/// inside one text unit. This fragment preserves paragraph/list/heading shape so
/// future cross-document copy/paste can move rich text without flattening away
/// important user choices.
class TextSystemDocumentFragment {
  const TextSystemDocumentFragment({
    required this.blocks,
    this.metadata = const <String, Object?>{},
  });

  factory TextSystemDocumentFragment.empty() {
    return const TextSystemDocumentFragment(blocks: <TextSystemBlock>[]);
  }

  factory TextSystemDocumentFragment.fromJson(Map<String, Object?> json) {
    return TextSystemDocumentFragment(
      blocks: (json['blocks'] as List? ?? const <Object?>[])
          .whereType<Map>()
          .map((block) => TextSystemBlock.fromJson(Map<String, Object?>.from(block)))
          .toList(),
      metadata: Map<String, Object?>.from(json['metadata'] as Map? ?? const <String, Object?>{}),
    );
  }

  final List<TextSystemBlock> blocks;
  final Map<String, Object?> metadata;

  bool get isEmpty => blocks.isEmpty || blocks.every((block) => block.text.isEmpty);
  int get blockCount => blocks.length;
  int get markCount => blocks.fold<int>(0, (count, block) => count + block.marks.length);
  String get plainText => blocks.map((block) => block.text).join('\n');

  TextClipboardFragment toFlatClipboardFragment() {
    var offset = 0;
    final flattenedMarks = <TextMark>[];
    for (var i = 0; i < blocks.length; i++) {
      final block = blocks[i];
      flattenedMarks.addAll(
        block.marks.map(
          (mark) => mark.copyWith(
            range: TextSystemRange(mark.range.start + offset, mark.range.end + offset),
          ),
        ),
      );
      offset += block.text.length;
      if (i < blocks.length - 1) offset += 1;
    }

    return TextClipboardFragment(
      text: plainText,
      marks: flattenedMarks,
      metadata: <String, Object?>{
        ...metadata,
        'documentFragment': true,
        'blockCount': blocks.length,
      },
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'blocks': blocks.map((block) => block.toJson()).toList(),
      if (metadata.isNotEmpty) 'metadata': metadata,
    };
  }
}
