import '../core/text_mark.dart';
import '../core/text_system_block.dart';
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
    var orderedIndex = 1;
    final seed = DateTime.now().microsecondsSinceEpoch;

    for (var i = 0; i < lines.length; i++) {
      final previous = i < previousDocument.blocks.length ? previousDocument.blocks[i] : null;
      final parsed = _parseVisibleLine(lines[i], previous, orderedIndex);
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
