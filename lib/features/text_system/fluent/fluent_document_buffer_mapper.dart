import '../core/text_mark.dart';
import '../core/text_system_block.dart';
import '../core/text_system_document_position.dart';
import '../core/text_system_document_range.dart';
import '../core/text_system_document.dart';
import 'fluent_buffer_segment.dart';
import 'fluent_document_buffer.dart';

/// Converts between the structured text-system document and the single visible
/// text buffer used by [FluentDocumentSurface].
class FluentDocumentBufferMapper {
  const FluentDocumentBufferMapper._();

  static FluentDocumentBuffer fromDocument(TextSystemDocument document) {
    if (document.blocks.isEmpty) {
      final empty = TextSystemDocument(
        id: document.id,
        title: document.title,
        blocks: const <TextSystemBlock>[],
        metadata: document.metadata,
        createdAt: document.createdAt,
        updatedAt: document.updatedAt,
      );
      return FluentDocumentBuffer(document: empty, text: '', segments: const <FluentBufferSegment>[]);
    }

    final buffer = StringBuffer();
    final segments = <FluentBufferSegment>[];

    for (var i = 0; i < document.blocks.length; i++) {
      final block = document.blocks[i];
      if (i > 0) buffer.write('\n');
      final lineStart = buffer.length;
      final prefix = _visiblePrefixForBlock(block, i);
      buffer.write(prefix);
      final contentStart = buffer.length;
      buffer.write(block.text);
      final lineEnd = buffer.length;

      segments.add(
        FluentBufferSegment(
          blockId: block.id,
          blockIndex: i,
          blockType: block.type,
          bufferStart: lineStart,
          bufferEnd: lineEnd,
          contentStart: contentStart,
          contentEnd: lineEnd,
          level: block.level,
          checked: block.checked,
          ordered: block.metadata['ordered'] == true,
        ),
      );
    }

    return FluentDocumentBuffer(
      document: document,
      text: buffer.toString(),
      segments: segments,
    );
  }

  static TextSystemDocument documentFromBuffer({
    required TextSystemDocument previousDocument,
    required String bufferText,
  }) {
    final lines = bufferText.split('\n');
    final blocks = <TextSystemBlock>[];
    final usedPreviousIndices = <int>{};
    var orderedIndex = 1;
    final seed = DateTime.now().microsecondsSinceEpoch;

    for (var i = 0; i < lines.length; i++) {
      final rawLine = lines[i];
      final sameIndexPrevious = i < previousDocument.blocks.length ? previousDocument.blocks[i] : null;
      final textWithoutMarker = _plainTextFromVisibleLine(rawLine);
      final previous = _bestPreviousBlockForLine(
        previousDocument: previousDocument,
        sameIndexPrevious: sameIndexPrevious,
        lineIndex: i,
        plainText: textWithoutMarker,
        usedPreviousIndices: usedPreviousIndices,
      );
      if (previous != null) {
        final previousIndex = previousDocument.blocks.indexWhere((block) => block.id == previous.id);
        if (previousIndex >= 0) usedPreviousIndices.add(previousIndex);
      }

      final parsed = _parseVisibleLine(rawLine, previous, orderedIndex);
      if (parsed.ordered) orderedIndex++;

      final text = parsed.text;
      final marks = previous != null && previous.text == text
          ? _clampMarks(previous.marks, text.length)
          : const <TextMark>[];

      blocks.add(
        TextSystemBlock(
          id: previous?.id ?? 'fluent-$seed-$i',
          type: parsed.type,
          text: text,
          marks: marks,
          level: parsed.level,
          checked: parsed.checked,
          metadata: <String, Object?>{
            if (parsed.ordered) 'ordered': true,
            if (parsed.ordered) 'index': parsed.orderedIndex,
          },
        ).normalizeMarks(),
      );
    }

    return previousDocument.copyWith(
      blocks: blocks,
      updatedAt: DateTime.now(),
    );
  }


  static TextSystemDocumentRange rangeFromBufferSelection(
    FluentDocumentBuffer buffer,
    int start,
    int end,
  ) {
    final safeStart = start.clamp(0, buffer.text.length).toInt();
    final safeEnd = end.clamp(0, buffer.text.length).toInt();
    final normalizedStart = safeStart <= safeEnd ? safeStart : safeEnd;
    final normalizedEnd = safeStart <= safeEnd ? safeEnd : safeStart;

    return TextSystemDocumentRange(
      start: positionForBufferOffset(buffer, normalizedStart),
      end: positionForBufferOffset(buffer, normalizedEnd),
    );
  }

  static TextSystemDocumentPosition positionForBufferOffset(
    FluentDocumentBuffer buffer,
    int offset,
  ) {
    if (buffer.segments.isEmpty) {
      return const TextSystemDocumentPosition(blockId: 'document-start', blockIndex: 0, offset: 0);
    }

    final clamped = offset.clamp(0, buffer.text.length).toInt();
    for (var i = 0; i < buffer.segments.length; i++) {
      final segment = buffer.segments[i];
      final isLast = i == buffer.segments.length - 1;
      final nextStart = isLast ? buffer.text.length + 1 : buffer.segments[i + 1].bufferStart;
      if (clamped <= segment.bufferEnd) {
        return segment.positionForBufferOffset(clamped);
      }
      if (clamped < nextStart) {
        return segment.positionForBufferOffset(segment.bufferEnd);
      }
    }

    final last = buffer.segments.last;
    return last.positionForBufferOffset(last.bufferEnd);
  }

  static bool equivalentDocumentShape(TextSystemDocument a, TextSystemDocument b) {
    if (a.title != b.title || a.blocks.length != b.blocks.length) return false;
    for (var i = 0; i < a.blocks.length; i++) {
      final left = a.blocks[i];
      final right = b.blocks[i];
      if (left.id != right.id ||
          left.type != right.type ||
          left.text != right.text ||
          left.level != right.level ||
          left.checked != right.checked ||
          left.metadata['ordered'] != right.metadata['ordered']) {
        return false;
      }
      if (left.marks.length != right.marks.length) return false;
      for (var j = 0; j < left.marks.length; j++) {
        if (left.marks[j].kind != right.marks[j].kind ||
            left.marks[j].range != right.marks[j].range) {
          return false;
        }
      }
    }
    return true;
  }

  static String _visiblePrefixForBlock(TextSystemBlock block, int index) {
    return switch (block.type) {
      TextSystemBlockType.listItem => block.metadata['ordered'] == true
          ? '${block.metadata['index'] is int ? block.metadata['index'] : index + 1}. '
          : '• ',
      TextSystemBlockType.todo => block.checked == true ? '☑ ' : '☐ ',
      _ => '',
    };
  }

  static _ParsedVisibleLine _parseVisibleLine(
    String line,
    TextSystemBlock? previous,
    int orderedIndex,
  ) {
    final orderedMatch = RegExp(r'^\s*(\d+)[\.)]\s+(.*)$').firstMatch(line);
    if (orderedMatch != null) {
      return _ParsedVisibleLine(
        type: TextSystemBlockType.listItem,
        text: orderedMatch.group(2) ?? '',
        ordered: true,
        orderedIndex: orderedIndex,
      );
    }

    final bulletMatch = RegExp(r'^\s*(?:[-*•])\s+(.*)$').firstMatch(line);
    if (bulletMatch != null) {
      return _ParsedVisibleLine(
        type: TextSystemBlockType.listItem,
        text: bulletMatch.group(1) ?? '',
      );
    }

    final todoMatch = RegExp(r'^\s*([☐☑])\s+(.*)$').firstMatch(line);
    if (todoMatch != null) {
      return _ParsedVisibleLine(
        type: TextSystemBlockType.todo,
        text: todoMatch.group(2) ?? '',
        checked: todoMatch.group(1) == '☑',
      );
    }

    // Blank lines created by pressing Enter after a heading should become normal
    // paragraphs. Existing headings must not turn following headings into
    // paragraphs, and new blank lines must not inherit heading style.
    if (line.trim().isEmpty) {
      return const _ParsedVisibleLine(type: TextSystemBlockType.paragraph, text: '');
    }

    if (previous != null &&
        previous.type != TextSystemBlockType.listItem &&
        previous.type != TextSystemBlockType.todo) {
      return _ParsedVisibleLine(
        type: previous.type,
        text: line,
        level: previous.level,
        checked: previous.checked,
      );
    }

    return _ParsedVisibleLine(type: TextSystemBlockType.paragraph, text: line);
  }

  static TextSystemBlock? _bestPreviousBlockForLine({
    required TextSystemDocument previousDocument,
    required TextSystemBlock? sameIndexPrevious,
    required int lineIndex,
    required String plainText,
    required Set<int> usedPreviousIndices,
  }) {
    // Prefer exact same-index mapping when the visible text still matches.
    if (sameIndexPrevious != null && sameIndexPrevious.text == plainText) {
      return sameIndexPrevious;
    }

    // If a new blank paragraph was inserted, do not steal the style from a
    // nearby heading/list item. It should be a normal paragraph.
    if (plainText.trim().isEmpty) return null;

    // Then preserve structure for shifted lines, especially headings below an
    // inserted paragraph/newline. Search nearby first so repeated headings do
    // not jump across the whole document unless necessary.
    for (final radius in const <int>[1, 2, 3, 5]) {
      final start = (lineIndex - radius).clamp(0, previousDocument.blocks.length - 1).toInt();
      final end = (lineIndex + radius).clamp(0, previousDocument.blocks.length - 1).toInt();
      for (var i = start; i <= end; i++) {
        if (usedPreviousIndices.contains(i)) continue;
        final candidate = previousDocument.blocks[i];
        if (candidate.text == plainText) return candidate;
      }
    }

    // If same-index text changed because the user edited the line, preserving
    // that line's previous style is still correct for non-list/todo structures.
    if (sameIndexPrevious != null &&
        sameIndexPrevious.type != TextSystemBlockType.listItem &&
        sameIndexPrevious.type != TextSystemBlockType.todo) {
      return sameIndexPrevious;
    }

    return null;
  }

  static String _plainTextFromVisibleLine(String line) {
    final orderedMatch = RegExp(r'^\s*(\d+)[\.)]\s+(.*)$').firstMatch(line);
    if (orderedMatch != null) return orderedMatch.group(2) ?? '';
    final bulletMatch = RegExp(r'^\s*(?:[-*•])\s+(.*)$').firstMatch(line);
    if (bulletMatch != null) return bulletMatch.group(1) ?? '';
    final todoMatch = RegExp(r'^\s*([☐☑])\s+(.*)$').firstMatch(line);
    if (todoMatch != null) return todoMatch.group(2) ?? '';
    return line;
  }


  static List<TextMark> _clampMarks(List<TextMark> marks, int textLength) {
    return marks
        .map((mark) => mark.clamp(textLength))
        .where((mark) => !mark.isEmpty)
        .toList()
      ..sort((a, b) {
        final startCompare = a.range.start.compareTo(b.range.start);
        if (startCompare != 0) return startCompare;
        return a.range.end.compareTo(b.range.end);
      });
  }
}

class _ParsedVisibleLine {
  const _ParsedVisibleLine({
    required this.type,
    required this.text,
    this.level,
    this.checked,
    this.ordered = false,
    this.orderedIndex,
  });

  final TextSystemBlockType type;
  final String text;
  final int? level;
  final bool? checked;
  final bool ordered;
  final int? orderedIndex;
}
