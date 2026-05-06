import 'text_mark.dart';
import 'text_system_block.dart';
import 'text_system_document.dart';
import 'text_system_document_fragment.dart';
import 'text_system_document_fragment_edit.dart';
import 'text_system_document_position.dart';
import 'text_system_document_range.dart';
import 'text_system_range.dart';

/// Structured document-fragment operations used by the fluent text foundation.
///
/// The current visual surfaces may still edit one text unit at a time. These
/// helpers keep cross-paragraph copy/paste semantics centralized so future
/// continuous editors can paste rich structured selections without exposing
/// internal blocks to the user.
class TextSystemDocumentFragmentOps {
  const TextSystemDocumentFragmentOps._();

  static TextSystemDocumentFragmentEditResult replaceRangeWithFragment({
    required TextSystemDocument document,
    required TextSystemDocumentRange range,
    required TextSystemDocumentFragment fragment,
    String idPrefix = 'pasted',
  }) {
    if (document.blocks.isEmpty) {
      final insertedBlocks = _cloneFragmentBlocks(fragment, idPrefix);
      final nextDocument = document.copyWith(
        blocks: insertedBlocks,
        updatedAt: DateTime.now(),
      );
      final insertedRange = _rangeForInsertedBlocks(insertedBlocks);
      return TextSystemDocumentFragmentEditResult(
        document: nextDocument,
        replacementRange: range,
        insertedRange: insertedRange,
        affectedBlockIds: insertedBlocks.map((block) => block.id).toList(),
        insertedPlainText: fragment.plainText,
      );
    }

    final normalized = range.normalized();
    final startIndex = _resolveBlockIndex(document, normalized.start);
    final endIndex = _resolveBlockIndex(document, normalized.end);
    final startBlock = document.blocks[startIndex];
    final endBlock = document.blocks[endIndex];
    final startOffset = normalized.start.offset.clamp(0, startBlock.text.length).toInt();
    final endOffset = normalized.end.offset.clamp(0, endBlock.text.length).toInt();

    final beforeText = startBlock.text.substring(0, startOffset);
    final afterText = endBlock.text.substring(endOffset);
    final beforeMarks = _marksBefore(startBlock.marks, startOffset);
    final afterMarks = _marksAfter(endBlock.marks, endOffset);
    final pastedBlocks = _cloneFragmentBlocks(fragment, idPrefix);

    final replacementBlocks = pastedBlocks.isEmpty
        ? _buildDeletionReplacement(
            startBlock: startBlock,
            beforeText: beforeText,
            beforeMarks: beforeMarks,
            afterText: afterText,
            afterMarks: afterMarks,
            endOffset: endOffset,
          )
        : _buildPasteReplacement(
            startBlock: startBlock,
            beforeText: beforeText,
            beforeMarks: beforeMarks,
            pastedBlocks: pastedBlocks,
            afterText: afterText,
            afterMarks: afterMarks,
            endOffset: endOffset,
          );

    final nextBlocks = <TextSystemBlock>[
      ...document.blocks.take(startIndex),
      ...replacementBlocks,
      ...document.blocks.skip(endIndex + 1),
    ];
    final nextDocument = document.copyWith(
      blocks: nextBlocks,
      updatedAt: DateTime.now(),
    );
    final affectedIds = replacementBlocks.map((block) => block.id).toList();
    final insertedRange = _insertedRange(
      document: nextDocument,
      startBlockIndex: startIndex,
      startOffset: startOffset,
      insertedBlocks: replacementBlocks,
      insertedTextLength: fragment.plainText.length,
    );

    return TextSystemDocumentFragmentEditResult(
      document: nextDocument,
      replacementRange: normalized,
      insertedRange: insertedRange,
      affectedBlockIds: affectedIds,
      insertedPlainText: fragment.plainText,
    );
  }

  static List<TextSystemBlock> _buildDeletionReplacement({
    required TextSystemBlock startBlock,
    required String beforeText,
    required List<TextMark> beforeMarks,
    required String afterText,
    required List<TextMark> afterMarks,
    required int endOffset,
  }) {
    final nextText = '$beforeText$afterText';
    final shiftedAfterMarks = afterMarks
        .map((mark) => mark.copyWith(range: mark.range.shift(beforeText.length - endOffset)))
        .toList();
    return <TextSystemBlock>[
      startBlock.copyWith(
        text: nextText,
        marks: <TextMark>[...beforeMarks, ...shiftedAfterMarks],
      ).normalizeMarks(),
    ];
  }

  static List<TextSystemBlock> _buildPasteReplacement({
    required TextSystemBlock startBlock,
    required String beforeText,
    required List<TextMark> beforeMarks,
    required List<TextSystemBlock> pastedBlocks,
    required String afterText,
    required List<TextMark> afterMarks,
    required int endOffset,
  }) {
    if (pastedBlocks.length == 1) {
      final pasted = pastedBlocks.single;
      final nextText = '$beforeText${pasted.text}$afterText';
      final pastedMarks = pasted.marks
          .map((mark) => mark.copyWith(range: mark.range.shift(beforeText.length)))
          .toList();
      final shiftedAfterMarks = afterMarks
          .map((mark) => mark.copyWith(range: mark.range.shift(beforeText.length + pasted.text.length - endOffset)))
          .toList();
      return <TextSystemBlock>[
        startBlock.copyWith(
          text: nextText,
          marks: <TextMark>[...beforeMarks, ...pastedMarks, ...shiftedAfterMarks],
        ).normalizeMarks(),
      ];
    }

    final first = pastedBlocks.first;
    final last = pastedBlocks.last;
    final firstBlock = startBlock.copyWith(
      text: '$beforeText${first.text}',
      marks: <TextMark>[
        ...beforeMarks,
        ...first.marks.map((mark) => mark.copyWith(range: mark.range.shift(beforeText.length))),
      ],
    ).normalizeMarks();

    final lastBlock = last.copyWith(
      text: '${last.text}$afterText',
      marks: <TextMark>[
        ...last.marks,
        ...afterMarks.map((mark) => mark.copyWith(range: mark.range.shift(last.text.length - endOffset))),
      ],
    ).normalizeMarks();

    return <TextSystemBlock>[
      firstBlock,
      ...pastedBlocks.skip(1).take(pastedBlocks.length - 2).map((block) => block.normalizeMarks()),
      lastBlock,
    ];
  }

  static List<TextSystemBlock> _cloneFragmentBlocks(TextSystemDocumentFragment fragment, String idPrefix) {
    final result = <TextSystemBlock>[];
    for (var i = 0; i < fragment.blocks.length; i++) {
      final block = fragment.blocks[i];
      result.add(
        block.copyWith(
          id: '$idPrefix-${DateTime.now().microsecondsSinceEpoch}-$i',
          metadata: <String, Object?>{
            ...block.metadata,
            'pastedFromDocumentFragment': true,
          },
        ).normalizeMarks(),
      );
    }
    return result;
  }

  static List<TextMark> _marksBefore(List<TextMark> marks, int offset) {
    final range = TextSystemRange(0, offset);
    return marks
        .map((mark) => mark.range.intersection(range) == null
            ? null
            : mark.copyWith(range: mark.range.intersection(range)!))
        .whereType<TextMark>()
        .toList();
  }

  static List<TextMark> _marksAfter(List<TextMark> marks, int offset) {
    return marks
        .where((mark) => mark.range.end > offset)
        .map((mark) {
          final start = mark.range.start < offset ? offset : mark.range.start;
          return mark.copyWith(range: TextSystemRange(start, mark.range.end));
        })
        .where((mark) => !mark.isEmpty)
        .toList();
  }

  static TextSystemDocumentRange _insertedRange({
    required TextSystemDocument document,
    required int startBlockIndex,
    required int startOffset,
    required List<TextSystemBlock> insertedBlocks,
    required int insertedTextLength,
  }) {
    if (document.blocks.isEmpty || insertedBlocks.isEmpty) {
      final position = const TextSystemDocumentPosition(blockId: 'document-start', blockIndex: 0, offset: 0);
      return TextSystemDocumentRange.collapsed(position);
    }

    final firstIndex = startBlockIndex.clamp(0, document.blocks.length - 1).toInt();
    final firstBlock = document.blocks[firstIndex];
    if (insertedTextLength == 0) {
      final position = TextSystemDocumentPosition(
        blockId: firstBlock.id,
        blockIndex: firstIndex,
        offset: startOffset.clamp(0, firstBlock.text.length).toInt(),
      );
      return TextSystemDocumentRange.collapsed(position);
    }

    final lastIndex = (firstIndex + insertedBlocks.length - 1).clamp(0, document.blocks.length - 1).toInt();
    final lastBlock = document.blocks[lastIndex];
    final endOffset = insertedBlocks.length == 1
        ? (startOffset + insertedTextLength).clamp(0, lastBlock.text.length).toInt()
        : insertedBlocks.last.text.length.clamp(0, lastBlock.text.length).toInt();

    return TextSystemDocumentRange(
      start: TextSystemDocumentPosition(
        blockId: firstBlock.id,
        blockIndex: firstIndex,
        offset: startOffset.clamp(0, firstBlock.text.length).toInt(),
      ),
      end: TextSystemDocumentPosition(
        blockId: lastBlock.id,
        blockIndex: lastIndex,
        offset: endOffset,
      ),
    );
  }

  static TextSystemDocumentRange _rangeForInsertedBlocks(List<TextSystemBlock> blocks) {
    if (blocks.isEmpty) {
      const position = TextSystemDocumentPosition(blockId: 'document-start', blockIndex: 0, offset: 0);
      return TextSystemDocumentRange.collapsed(position);
    }
    return TextSystemDocumentRange(
      start: TextSystemDocumentPosition(blockId: blocks.first.id, blockIndex: 0, offset: 0),
      end: TextSystemDocumentPosition(blockId: blocks.last.id, blockIndex: blocks.length - 1, offset: blocks.last.text.length),
    );
  }

  static int _resolveBlockIndex(TextSystemDocument document, TextSystemDocumentPosition position) {
    final byId = document.blocks.indexWhere((block) => block.id == position.blockId);
    if (byId >= 0) return byId;
    return position.blockIndex.clamp(0, document.blocks.length - 1).toInt();
  }
}
