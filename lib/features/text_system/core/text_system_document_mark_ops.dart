import 'text_mark.dart';
import 'text_system_block.dart';
import 'text_system_document.dart';
import 'text_system_document_range.dart';
import 'text_system_document_selection_mapper.dart';
import 'text_system_range.dart';

/// Applies inline marks to fluent document ranges that may span multiple
/// internal text units.
///
/// This keeps the user-facing model text-first: a visible selection can cross
/// paragraph/list boundaries while the engine splits the mark operation across
/// the structured document underneath.
class TextSystemDocumentMarkOps {
  const TextSystemDocumentMarkOps._();

  static TextSystemDocument toggleMark({
    required TextSystemDocument document,
    required TextSystemDocumentRange range,
    required TextMarkKind kind,
  }) {
    final affected = _affectedLocalRanges(document, range);
    if (affected.isEmpty) return document;

    final shouldRemove = affected.every((entry) {
      final block = document.blocks[entry.blockIndex];
      return _rangeFullyCoveredByKind(block.marks, entry.range, kind);
    });

    final affectedByBlock = <int, TextSystemRange>{
      for (final entry in affected) entry.blockIndex: entry.range,
    };

    final nextBlocks = <TextSystemBlock>[];
    for (var i = 0; i < document.blocks.length; i++) {
      final block = document.blocks[i];
      final localRange = affectedByBlock[i];
      if (localRange == null || localRange.isCollapsed) {
        nextBlocks.add(block);
        continue;
      }

      final nextMarks = shouldRemove
          ? _removeKindFromRange(block.marks, localRange, kind)
          : _applyKindToRange(block.marks, localRange, kind);
      nextBlocks.add(block.copyWith(marks: nextMarks).normalizeMarks());
    }

    return document.copyWith(blocks: nextBlocks, updatedAt: DateTime.now());
  }

  static List<_AffectedBlockRange> _affectedLocalRanges(
    TextSystemDocument document,
    TextSystemDocumentRange range,
  ) {
    if (document.blocks.isEmpty || range.isCollapsed) return const <_AffectedBlockRange>[];

    final offsets = TextSystemDocumentSelectionMapper.offsetRangeForRange(document, range);
    if (offsets.isCollapsed) return const <_AffectedBlockRange>[];

    final affected = <_AffectedBlockRange>[];
    var blockStart = 0;
    for (var i = 0; i < document.blocks.length; i++) {
      final block = document.blocks[i];
      final blockEnd = blockStart + block.text.length;
      final localStart = (offsets.start - blockStart).clamp(0, block.text.length).toInt();
      final localEnd = (offsets.end - blockStart).clamp(0, block.text.length).toInt();
      if (localStart < localEnd) {
        affected.add(_AffectedBlockRange(i, TextSystemRange(localStart, localEnd)));
      }
      blockStart = blockEnd + 1;
    }
    return affected;
  }

  static bool _rangeFullyCoveredByKind(
    List<TextMark> marks,
    TextSystemRange range,
    TextMarkKind kind,
  ) {
    final intervals = marks
        .where((mark) => mark.kind == kind)
        .map((mark) => mark.range.intersection(range))
        .whereType<TextSystemRange>()
        .toList()
      ..sort((a, b) => a.start.compareTo(b.start));

    var cursor = range.start;
    for (final interval in intervals) {
      if (interval.start > cursor) return false;
      if (interval.end > cursor) cursor = interval.end;
      if (cursor >= range.end) return true;
    }
    return cursor >= range.end;
  }

  static List<TextMark> _removeKindFromRange(
    List<TextMark> marks,
    TextSystemRange range,
    TextMarkKind kind,
  ) {
    final result = <TextMark>[];
    for (final mark in marks) {
      if (mark.kind != kind || !mark.range.overlaps(range)) {
        result.add(mark);
        continue;
      }

      if (mark.range.start < range.start) {
        result.add(mark.copyWith(range: TextSystemRange(mark.range.start, range.start)));
      }
      if (mark.range.end > range.end) {
        result.add(mark.copyWith(range: TextSystemRange(range.end, mark.range.end)));
      }
    }
    return _normalize(result);
  }

  static List<TextMark> _applyKindToRange(
    List<TextMark> marks,
    TextSystemRange range,
    TextMarkKind kind,
  ) {
    var merged = range;
    final result = <TextMark>[];

    for (final mark in marks) {
      final sameKind = mark.kind == kind;
      final touchesOrOverlaps = mark.range.start <= merged.end && mark.range.end >= merged.start;
      if (sameKind && touchesOrOverlaps) {
        merged = TextSystemRange(
          mark.range.start < merged.start ? mark.range.start : merged.start,
          mark.range.end > merged.end ? mark.range.end : merged.end,
        );
      } else {
        result.add(mark);
      }
    }

    result.add(TextMark(kind: kind, range: merged));
    return _normalize(result);
  }

  static List<TextMark> _normalize(List<TextMark> marks) {
    return marks.where((mark) => !mark.isEmpty).toList()
      ..sort((a, b) {
        final start = a.range.start.compareTo(b.range.start);
        if (start != 0) return start;
        final end = a.range.end.compareTo(b.range.end);
        if (end != 0) return end;
        return a.kind.name.compareTo(b.kind.name);
      });
  }
}

class _AffectedBlockRange {
  const _AffectedBlockRange(this.blockIndex, this.range);

  final int blockIndex;
  final TextSystemRange range;
}
