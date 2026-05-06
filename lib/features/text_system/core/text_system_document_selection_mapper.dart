import 'text_mark.dart';
import 'text_system_block.dart';
import 'text_system_document.dart';
import 'text_system_document_fragment.dart';
import 'text_system_document_position.dart';
import 'text_system_document_range.dart';
import 'text_system_range.dart';

/// Maps between the user's future fluent text coordinates and the structured
/// document model underneath.
///
/// This is a foundation layer only. Current lightweight surfaces may still edit
/// one paragraph/list item at a time, but this class gives the engine a stable
/// vocabulary for cross-paragraph selection, copy, paste, and mark application.
class TextSystemDocumentSelectionMapper {
  const TextSystemDocumentSelectionMapper._();

  static int documentLength(TextSystemDocument document) {
    if (document.blocks.isEmpty) return 0;
    final textLength = document.blocks.fold<int>(0, (sum, block) => sum + block.text.length);
    return textLength + document.blocks.length - 1;
  }

  static String flattenedText(TextSystemDocument document) {
    return document.blocks.map((block) => block.text).join('\n');
  }

  static TextSystemDocumentPosition positionForOffset(TextSystemDocument document, int offset) {
    if (document.blocks.isEmpty) {
      return const TextSystemDocumentPosition(blockId: 'document-start', blockIndex: 0, offset: 0);
    }

    final clamped = offset.clamp(0, documentLength(document)).toInt();
    var cursor = 0;
    for (var i = 0; i < document.blocks.length; i++) {
      final block = document.blocks[i];
      final blockStart = cursor;
      final blockEnd = blockStart + block.text.length;
      if (clamped <= blockEnd || i == document.blocks.length - 1) {
        return TextSystemDocumentPosition(
          blockId: block.id,
          blockIndex: i,
          offset: (clamped - blockStart).clamp(0, block.text.length).toInt(),
        );
      }
      cursor = blockEnd + 1;
    }

    final last = document.blocks.last;
    return TextSystemDocumentPosition(
      blockId: last.id,
      blockIndex: document.blocks.length - 1,
      offset: last.text.length,
    );
  }

  static int offsetForPosition(TextSystemDocument document, TextSystemDocumentPosition position) {
    if (document.blocks.isEmpty) return 0;

    final index = _resolveBlockIndex(document, position);
    var offset = 0;
    for (var i = 0; i < index; i++) {
      offset += document.blocks[i].text.length + 1;
    }
    return offset + position.offset.clamp(0, document.blocks[index].text.length).toInt();
  }

  static TextSystemDocumentRange rangeFromOffsets(
    TextSystemDocument document,
    int start,
    int end,
  ) {
    final length = documentLength(document);
    final safeStart = start.clamp(0, length).toInt();
    final safeEnd = end.clamp(0, length).toInt();
    final normalizedStart = safeStart <= safeEnd ? safeStart : safeEnd;
    final normalizedEnd = safeStart <= safeEnd ? safeEnd : safeStart;
    return TextSystemDocumentRange(
      start: positionForOffset(document, normalizedStart),
      end: positionForOffset(document, normalizedEnd),
    );
  }

  static TextSystemDocumentOffsetRange offsetRangeForRange(
    TextSystemDocument document,
    TextSystemDocumentRange range,
  ) {
    final start = offsetForPosition(document, range.start);
    final end = offsetForPosition(document, range.end);
    return start <= end
        ? TextSystemDocumentOffsetRange(start, end)
        : TextSystemDocumentOffsetRange(end, start);
  }

  static String plainTextForRange(TextSystemDocument document, TextSystemDocumentRange range) {
    final offsets = offsetRangeForRange(document, range);
    if (offsets.isCollapsed) return '';
    final text = flattenedText(document);
    return text.substring(offsets.start, offsets.end);
  }

  static TextSystemDocumentFragment fragmentForRange(
    TextSystemDocument document,
    TextSystemDocumentRange range,
  ) {
    final offsets = offsetRangeForRange(document, range);
    if (offsets.isCollapsed || document.blocks.isEmpty) {
      return TextSystemDocumentFragment.empty();
    }

    final fragmentBlocks = <TextSystemBlock>[];
    var blockStart = 0;
    for (var i = 0; i < document.blocks.length; i++) {
      final block = document.blocks[i];
      final blockEnd = blockStart + block.text.length;
      final intersectsText = offsets.start < blockEnd && offsets.end > blockStart;
      final fullySelectsEmptyBlock = block.text.isEmpty && offsets.start <= blockStart && offsets.end >= blockEnd;

      if (intersectsText || fullySelectsEmptyBlock) {
        final localStart = (offsets.start - blockStart).clamp(0, block.text.length).toInt();
        final localEnd = (offsets.end - blockStart).clamp(localStart, block.text.length).toInt();
        final selectedText = block.text.substring(localStart, localEnd);
        final marks = _marksForLocalRange(block.marks, TextSystemRange(localStart, localEnd));

        fragmentBlocks.add(
          block.copyWith(
            id: 'fragment-${block.id}',
            text: selectedText,
            marks: marks,
            metadata: <String, Object?>{
              ...block.metadata,
              'sourceBlockId': block.id,
              'sourceBlockIndex': i,
              'partial': localStart != 0 || localEnd != block.text.length,
            },
          ).normalizeMarks(),
        );
      }

      blockStart = blockEnd + 1;
    }

    return TextSystemDocumentFragment(
      blocks: fragmentBlocks,
      metadata: <String, Object?>{
        'sourceDocumentId': document.id,
        'sourceDocumentTitle': document.title,
        'startOffset': offsets.start,
        'endOffset': offsets.end,
      },
    );
  }

  static String describePosition(TextSystemDocument document, TextSystemDocumentPosition position) {
    if (document.blocks.isEmpty) return 'empty document';
    final index = _resolveBlockIndex(document, position);
    final block = document.blocks[index];
    final style = _styleLabel(block);
    final offset = position.offset.clamp(0, block.text.length).toInt();
    return '$style ${index + 1}, character $offset of ${block.text.length}';
  }

  static String describeRange(TextSystemDocument document, TextSystemDocumentRange range) {
    final offsets = offsetRangeForRange(document, range);
    if (offsets.isCollapsed) return 'collapsed at ${describePosition(document, range.start)}';
    return '${offsets.length} characters from ${describePosition(document, range.start)} to ${describePosition(document, range.end)}';
  }

  static int _resolveBlockIndex(TextSystemDocument document, TextSystemDocumentPosition position) {
    final byId = document.blocks.indexWhere((block) => block.id == position.blockId);
    if (byId >= 0) return byId;
    return position.blockIndex.clamp(0, document.blocks.length - 1).toInt();
  }

  static List<TextMark> _marksForLocalRange(List<TextMark> marks, TextSystemRange range) {
    if (range.isCollapsed) return const <TextMark>[];
    final result = <TextMark>[];
    for (final mark in marks) {
      final intersection = mark.range.intersection(range);
      if (intersection == null) continue;
      result.add(mark.copyWith(range: intersection.relativeTo(range.start)));
    }
    return result;
  }

  static String _styleLabel(TextSystemBlock block) {
    return switch (block.type) {
      TextSystemBlockType.heading => 'heading',
      TextSystemBlockType.listItem => block.metadata['ordered'] == true ? 'numbered item' : 'bullet item',
      TextSystemBlockType.todo => 'todo',
      TextSystemBlockType.quote => 'quote',
      TextSystemBlockType.code => 'code paragraph',
      TextSystemBlockType.divider => 'divider',
      TextSystemBlockType.custom => 'custom paragraph',
      TextSystemBlockType.paragraph => 'paragraph',
    };
  }
}
