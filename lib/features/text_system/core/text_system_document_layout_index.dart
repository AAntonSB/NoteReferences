import 'dart:ui';

import 'text_system_document_position.dart';
import 'text_system_document_range.dart';

/// Visual/layout fragment kinds that can be mapped back to document positions.
///
/// This is intentionally model-facing. Widgets and render objects may register
/// fragments here, but selection/copy/comment/citation systems should consume
/// [TextSystemDocumentPosition] and [TextSystemDocumentRange], not widget-local
/// coordinates.
enum TextSystemDocumentLayoutFragmentKind {
  page,
  textLine,
  textRun,
  inlineAtom,
  objectBlock,
  figure,
  table,
  equation,
  tableCell,
  pageBreak,
  sectionBreak,
  pageMargin,
  commentRail,
  unknown,
}

/// One visual fragment in the paged editor that can map back to a document
/// position or range.
class TextSystemDocumentLayoutFragment {
  const TextSystemDocumentLayoutFragment({
    required this.id,
    required this.kind,
    required this.pageIndex,
    required this.globalRect,
    this.blockId,
    this.blockIndex,
    this.start,
    this.end,
    this.lineIndex,
    this.atomId,
    this.tableRow,
    this.tableColumn,
    this.metadata = const <String, Object?>{},
  })  : assert(pageIndex >= 0),
        assert(blockIndex == null || blockIndex >= 0),
        assert(lineIndex == null || lineIndex >= 0),
        assert(tableRow == null || tableRow >= 0),
        assert(tableColumn == null || tableColumn >= 0);

  final String id;
  final TextSystemDocumentLayoutFragmentKind kind;
  final int pageIndex;

  /// Rect in the same global/surface coordinate system used by hit testing.
  final Rect globalRect;

  final String? blockId;
  final int? blockIndex;
  final TextSystemDocumentPosition? start;
  final TextSystemDocumentPosition? end;
  final int? lineIndex;
  final String? atomId;
  final int? tableRow;
  final int? tableColumn;
  final Map<String, Object?> metadata;

  bool get isPage => kind == TextSystemDocumentLayoutFragmentKind.page;
  bool get isTextLike =>
      kind == TextSystemDocumentLayoutFragmentKind.textLine ||
      kind == TextSystemDocumentLayoutFragmentKind.textRun;
  bool get isInlineAtom => kind == TextSystemDocumentLayoutFragmentKind.inlineAtom;
  bool get isTableCell => kind == TextSystemDocumentLayoutFragmentKind.tableCell;
  bool get isObjectLike => <TextSystemDocumentLayoutFragmentKind>{
        TextSystemDocumentLayoutFragmentKind.objectBlock,
        TextSystemDocumentLayoutFragmentKind.figure,
        TextSystemDocumentLayoutFragmentKind.table,
        TextSystemDocumentLayoutFragmentKind.equation,
        TextSystemDocumentLayoutFragmentKind.pageBreak,
        TextSystemDocumentLayoutFragmentKind.sectionBreak,
      }.contains(kind);

  bool containsGlobalOffset(Offset offset, {double tolerance = 0}) {
    if (tolerance <= 0) return globalRect.contains(offset);
    return globalRect.inflate(tolerance).contains(offset);
  }

  double distanceSquaredTo(Offset offset) {
    final dx = offset.dx < globalRect.left
        ? globalRect.left - offset.dx
        : offset.dx > globalRect.right
            ? offset.dx - globalRect.right
            : 0.0;
    final dy = offset.dy < globalRect.top
        ? globalRect.top - offset.dy
        : offset.dy > globalRect.bottom
            ? offset.dy - globalRect.bottom
            : 0.0;
    return dx * dx + dy * dy;
  }

  int get _hitPriority {
    switch (kind) {
      case TextSystemDocumentLayoutFragmentKind.inlineAtom:
      case TextSystemDocumentLayoutFragmentKind.tableCell:
        return 0;
      case TextSystemDocumentLayoutFragmentKind.textRun:
        return 1;
      case TextSystemDocumentLayoutFragmentKind.textLine:
        return 2;
      case TextSystemDocumentLayoutFragmentKind.figure:
      case TextSystemDocumentLayoutFragmentKind.table:
      case TextSystemDocumentLayoutFragmentKind.equation:
      case TextSystemDocumentLayoutFragmentKind.objectBlock:
        return 3;
      case TextSystemDocumentLayoutFragmentKind.pageBreak:
      case TextSystemDocumentLayoutFragmentKind.sectionBreak:
        return 4;
      case TextSystemDocumentLayoutFragmentKind.pageMargin:
      case TextSystemDocumentLayoutFragmentKind.commentRail:
        return 5;
      case TextSystemDocumentLayoutFragmentKind.page:
        return 9;
      case TextSystemDocumentLayoutFragmentKind.unknown:
        return 8;
    }
  }

  TextSystemDocumentPosition? positionForGlobalOffset(Offset offset) {
    if (isTextLike) return _textPositionForGlobalOffset(offset);
    if (isInlineAtom) {
      final currentStart = start;
      if (currentStart == null) return null;
      return currentStart.copyWith(
        affinity: TextSystemDocumentPositionAffinity.insideInlineAtom,
        atomId: atomId ?? currentStart.atomId,
      );
    }
    if (isTableCell) {
      final currentStart = start;
      if (currentStart != null) {
        return currentStart.copyWith(
          affinity: TextSystemDocumentPositionAffinity.insideTableCell,
          tableRow: tableRow ?? currentStart.tableRow,
          tableColumn: tableColumn ?? currentStart.tableColumn,
        );
      }
      final currentBlockId = blockId;
      final currentBlockIndex = blockIndex;
      final row = tableRow;
      final column = tableColumn;
      if (currentBlockId == null || currentBlockIndex == null || row == null || column == null) {
        return null;
      }
      return TextSystemDocumentPosition.tableCell(
        blockId: currentBlockId,
        blockIndex: currentBlockIndex,
        row: row,
        column: column,
      );
    }
    if (isObjectLike) {
      final currentBlockId = blockId;
      final currentBlockIndex = blockIndex;
      if (currentBlockId == null || currentBlockIndex == null) return start;
      return TextSystemDocumentPosition.onBlock(
        blockId: currentBlockId,
        blockIndex: currentBlockIndex,
      );
    }
    return start;
  }

  TextSystemDocumentPosition? _textPositionForGlobalOffset(Offset offset) {
    final currentStart = start;
    final currentEnd = end;
    if (currentStart == null || currentEnd == null) return currentStart;
    final startOffset = currentStart.offset;
    final endOffset = currentEnd.offset;
    if (endOffset <= startOffset || globalRect.width <= 0) return currentStart;

    final ratio = ((offset.dx - globalRect.left) / globalRect.width).clamp(0.0, 1.0);
    final mappedOffset = startOffset + ((endOffset - startOffset) * ratio).round();
    return TextSystemDocumentPosition.text(
      blockId: currentStart.blockId,
      blockIndex: currentStart.blockIndex,
      offset: mappedOffset.clamp(startOffset, endOffset).toInt(),
    );
  }

  bool intersectsRange(TextSystemDocumentRange range) {
    final currentStart = start;
    final currentEnd = end;
    if (currentStart == null || currentEnd == null) return false;
    final normalized = range.normalized();
    final fragmentRange = TextSystemDocumentRange(start: currentStart, end: currentEnd).normalized();
    return fragmentRange.start.compareTo(normalized.end) <= 0 &&
        normalized.start.compareTo(fragmentRange.end) <= 0;
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'kind': kind.name,
      'pageIndex': pageIndex,
      'globalRect': _rectToJson(globalRect),
      if (blockId != null) 'blockId': blockId,
      if (blockIndex != null) 'blockIndex': blockIndex,
      if (start != null) 'start': start!.toJson(),
      if (end != null) 'end': end!.toJson(),
      if (lineIndex != null) 'lineIndex': lineIndex,
      if (atomId != null) 'atomId': atomId,
      if (tableRow != null) 'tableRow': tableRow,
      if (tableColumn != null) 'tableColumn': tableColumn,
      if (metadata.isNotEmpty) 'metadata': metadata,
    };
  }
}

/// Hit-test result from the layout index.
class TextSystemDocumentLayoutHit {
  const TextSystemDocumentLayoutHit({
    required this.globalOffset,
    required this.fragment,
    required this.position,
    required this.isExactHit,
  });

  final Offset globalOffset;
  final TextSystemDocumentLayoutFragment fragment;
  final TextSystemDocumentPosition position;
  final bool isExactHit;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'globalOffset': _offsetToJson(globalOffset),
      'fragment': fragment.toJson(),
      'position': position.toJson(),
      'isExactHit': isExactHit,
    };
  }

  String get diagnosticLabel {
    return 'page ${fragment.pageIndex + 1} → ${fragment.kind.name} → ${position.diagnosticLabel}';
  }
}

/// Layout-to-document map for a laid-out document surface.
///
/// This class is the bridge between visual coordinates and the backend document
/// model. It is intentionally independent of widget state so future selection,
/// comments, citations, source links, diagnostics, and AI actions can operate on
/// [TextSystemDocumentPosition] and [TextSystemDocumentRange].
class TextSystemDocumentLayoutIndex {
  const TextSystemDocumentLayoutIndex({
    required this.documentId,
    required this.fragments,
  });

  factory TextSystemDocumentLayoutIndex.empty(String documentId) {
    return TextSystemDocumentLayoutIndex(
      documentId: documentId,
      fragments: const <TextSystemDocumentLayoutFragment>[],
    );
  }

  final String documentId;
  final List<TextSystemDocumentLayoutFragment> fragments;

  List<TextSystemDocumentLayoutFragment> get pages => fragments
      .where((fragment) => fragment.kind == TextSystemDocumentLayoutFragmentKind.page)
      .toList(growable: false);

  List<TextSystemDocumentLayoutFragment> get nonPageFragments => fragments
      .where((fragment) => fragment.kind != TextSystemDocumentLayoutFragmentKind.page)
      .toList(growable: false);

  List<TextSystemDocumentLayoutFragment> fragmentsForBlock(String blockId) {
    return fragments.where((fragment) => fragment.blockId == blockId).toList(growable: false);
  }

  List<TextSystemDocumentLayoutFragment> fragmentsForPage(int pageIndex) {
    return fragments.where((fragment) => fragment.pageIndex == pageIndex).toList(growable: false);
  }

  /// Returns the best document position for a pointer/global offset.
  TextSystemDocumentPosition? positionAtGlobalOffset(
    Offset offset, {
    double tolerance = 0,
  }) {
    return hitAtGlobalOffset(offset, tolerance: tolerance)?.position;
  }

  TextSystemDocumentLayoutHit? hitAtGlobalOffset(
    Offset offset, {
    double tolerance = 0,
  }) {
    final exact = _bestFragmentContaining(offset, tolerance: 0);
    if (exact != null) {
      final position = exact.positionForGlobalOffset(offset);
      if (position != null) {
        return TextSystemDocumentLayoutHit(
          globalOffset: offset,
          fragment: exact,
          position: position,
          isExactHit: true,
        );
      }
    }

    if (tolerance <= 0) return null;
    final nearby = _bestFragmentContaining(offset, tolerance: tolerance) ??
        nearestFragmentAtGlobalOffset(offset, maxDistance: tolerance);
    if (nearby == null) return null;
    final position = nearby.positionForGlobalOffset(offset);
    if (position == null) return null;
    return TextSystemDocumentLayoutHit(
      globalOffset: offset,
      fragment: nearby,
      position: position,
      isExactHit: nearby.containsGlobalOffset(offset),
    );
  }

  TextSystemDocumentLayoutFragment? nearestFragmentAtGlobalOffset(
    Offset offset, {
    double? maxDistance,
  }) {
    final candidates = nonPageFragments.toList(growable: false);
    if (candidates.isEmpty) return null;
    candidates.sort((a, b) {
      final distanceCompare = a.distanceSquaredTo(offset).compareTo(b.distanceSquaredTo(offset));
      if (distanceCompare != 0) return distanceCompare;
      return a._hitPriority.compareTo(b._hitPriority);
    });
    final candidate = candidates.first;
    if (maxDistance != null) {
      final squared = maxDistance * maxDistance;
      if (candidate.distanceSquaredTo(offset) > squared) return null;
    }
    return candidate;
  }

  Rect? rectForPosition(TextSystemDocumentPosition position) {
    final exact = _exactFragmentForPosition(position);
    if (exact != null) return exact.globalRect;

    if (position.isTextOffset) {
      final textFragments = fragmentsForBlock(position.blockId)
          .where((fragment) => fragment.isTextLike && fragment.start != null && fragment.end != null)
          .toList(growable: false);
      for (final fragment in textFragments) {
        final startOffset = fragment.start!.offset;
        final endOffset = fragment.end!.offset;
        if (position.offset < startOffset || position.offset > endOffset) continue;
        if (endOffset <= startOffset || fragment.globalRect.width <= 0) {
          return Rect.fromLTWH(fragment.globalRect.left, fragment.globalRect.top, 1, fragment.globalRect.height);
        }
        final ratio = (position.offset - startOffset) / (endOffset - startOffset);
        final x = fragment.globalRect.left + fragment.globalRect.width * ratio.clamp(0.0, 1.0);
        return Rect.fromLTWH(x, fragment.globalRect.top, 1, fragment.globalRect.height);
      }
    }

    final blockFragments = fragmentsForBlock(position.blockId);
    if (blockFragments.isEmpty) return null;
    if (position.isBeforeBlock) {
      final first = blockFragments.first;
      return Rect.fromLTWH(first.globalRect.left, first.globalRect.top, first.globalRect.width, 1);
    }
    if (position.isAfterBlock) {
      final last = blockFragments.last;
      return Rect.fromLTWH(last.globalRect.left, last.globalRect.bottom, last.globalRect.width, 1);
    }
    return blockFragments.first.globalRect;
  }

  List<Rect> rectsForRange(TextSystemDocumentRange range) {
    final normalized = range.normalized();
    final rects = <Rect>[];
    for (final fragment in nonPageFragments) {
      if (fragment.intersectsRange(normalized)) rects.add(fragment.globalRect);
    }
    return List<Rect>.unmodifiable(rects);
  }

  Map<String, Object?> diagnosticsAtGlobalOffset(
    Offset offset, {
    double tolerance = 8,
  }) {
    final hit = hitAtGlobalOffset(offset, tolerance: tolerance);
    if (hit == null) {
      return <String, Object?>{
        'globalOffset': _offsetToJson(offset),
        'hit': null,
      };
    }
    return <String, Object?>{
      'globalOffset': _offsetToJson(offset),
      'hit': hit.toJson(),
      'label': hit.diagnosticLabel,
    };
  }

  Map<String, Object?> toDiagnosticsJson() {
    final byKind = <String, int>{};
    final byPage = <String, int>{};
    for (final fragment in fragments) {
      byKind.update(fragment.kind.name, (value) => value + 1, ifAbsent: () => 1);
      byPage.update('${fragment.pageIndex}', (value) => value + 1, ifAbsent: () => 1);
    }
    return <String, Object?>{
      'documentId': documentId,
      'fragmentCount': fragments.length,
      'byKind': byKind,
      'byPage': byPage,
      'fragments': fragments.map((fragment) => fragment.toJson()).toList(),
    };
  }

  TextSystemDocumentLayoutFragment? _bestFragmentContaining(Offset offset, {double tolerance = 0}) {
    final matches = nonPageFragments
        .where((fragment) => fragment.containsGlobalOffset(offset, tolerance: tolerance))
        .toList(growable: false);
    if (matches.isEmpty) return null;
    matches.sort((a, b) {
      final priorityCompare = a._hitPriority.compareTo(b._hitPriority);
      if (priorityCompare != 0) return priorityCompare;
      final areaCompare = (a.globalRect.width * a.globalRect.height)
          .compareTo(b.globalRect.width * b.globalRect.height);
      if (areaCompare != 0) return areaCompare;
      return a.pageIndex.compareTo(b.pageIndex);
    });
    return matches.first;
  }

  TextSystemDocumentLayoutFragment? _exactFragmentForPosition(TextSystemDocumentPosition position) {
    for (final fragment in nonPageFragments) {
      if (fragment.blockId != position.blockId) continue;
      if (position.isOnBlock && fragment.isObjectLike) return fragment;
      if (position.isInlineAtom &&
          fragment.isInlineAtom &&
          (position.atomId == null || position.atomId == fragment.atomId)) {
        return fragment;
      }
      if (position.isTableCell &&
          fragment.isTableCell &&
          position.tableRow == fragment.tableRow &&
          position.tableColumn == fragment.tableColumn) {
        return fragment;
      }
    }
    return null;
  }
}

/// Incremental builder that page/layout code can use while it computes visual
/// fragments. The editor does not need to allocate this during normal painting
/// until diagnostics/selection need it.
class TextSystemDocumentLayoutIndexBuilder {
  TextSystemDocumentLayoutIndexBuilder({required this.documentId});

  final String documentId;
  final List<TextSystemDocumentLayoutFragment> _fragments = <TextSystemDocumentLayoutFragment>[];

  void registerPage({
    required int pageIndex,
    required Rect globalRect,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    _fragments.add(TextSystemDocumentLayoutFragment(
      id: 'page:$pageIndex',
      kind: TextSystemDocumentLayoutFragmentKind.page,
      pageIndex: pageIndex,
      globalRect: globalRect,
      metadata: metadata,
    ));
  }

  void registerTextFragment({
    required String fragmentId,
    required String blockId,
    required int blockIndex,
    required int pageIndex,
    required Rect globalRect,
    required int startOffset,
    required int endOffset,
    int? lineIndex,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    _fragments.add(TextSystemDocumentLayoutFragment(
      id: fragmentId,
      kind: TextSystemDocumentLayoutFragmentKind.textRun,
      pageIndex: pageIndex,
      globalRect: globalRect,
      blockId: blockId,
      blockIndex: blockIndex,
      start: TextSystemDocumentPosition.text(
        blockId: blockId,
        blockIndex: blockIndex,
        offset: startOffset,
      ),
      end: TextSystemDocumentPosition.text(
        blockId: blockId,
        blockIndex: blockIndex,
        offset: endOffset,
      ),
      lineIndex: lineIndex,
      metadata: metadata,
    ));
  }

  void registerObjectFragment({
    required String fragmentId,
    required TextSystemDocumentLayoutFragmentKind kind,
    required String blockId,
    required int blockIndex,
    required int pageIndex,
    required Rect globalRect,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    _fragments.add(TextSystemDocumentLayoutFragment(
      id: fragmentId,
      kind: kind,
      pageIndex: pageIndex,
      globalRect: globalRect,
      blockId: blockId,
      blockIndex: blockIndex,
      start: TextSystemDocumentPosition.onBlock(blockId: blockId, blockIndex: blockIndex),
      end: TextSystemDocumentPosition.afterBlock(blockId: blockId, blockIndex: blockIndex),
      metadata: metadata,
    ));
  }

  void registerInlineAtomFragment({
    required String fragmentId,
    required String blockId,
    required int blockIndex,
    required int pageIndex,
    required Rect globalRect,
    required int startOffset,
    required int endOffset,
    String? atomId,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    _fragments.add(TextSystemDocumentLayoutFragment(
      id: fragmentId,
      kind: TextSystemDocumentLayoutFragmentKind.inlineAtom,
      pageIndex: pageIndex,
      globalRect: globalRect,
      blockId: blockId,
      blockIndex: blockIndex,
      start: TextSystemDocumentPosition.inlineAtom(
        blockId: blockId,
        blockIndex: blockIndex,
        atomStartOffset: startOffset,
        atomEndOffset: endOffset,
        atomId: atomId,
      ),
      end: TextSystemDocumentPosition.text(
        blockId: blockId,
        blockIndex: blockIndex,
        offset: endOffset,
      ),
      atomId: atomId,
      metadata: metadata,
    ));
  }

  void registerTableCellFragment({
    required String fragmentId,
    required String blockId,
    required int blockIndex,
    required int pageIndex,
    required Rect globalRect,
    required int row,
    required int column,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    _fragments.add(TextSystemDocumentLayoutFragment(
      id: fragmentId,
      kind: TextSystemDocumentLayoutFragmentKind.tableCell,
      pageIndex: pageIndex,
      globalRect: globalRect,
      blockId: blockId,
      blockIndex: blockIndex,
      start: TextSystemDocumentPosition.tableCell(
        blockId: blockId,
        blockIndex: blockIndex,
        row: row,
        column: column,
      ),
      end: TextSystemDocumentPosition.tableCell(
        blockId: blockId,
        blockIndex: blockIndex,
        row: row,
        column: column,
      ),
      tableRow: row,
      tableColumn: column,
      metadata: metadata,
    ));
  }

  TextSystemDocumentLayoutIndex build() {
    final sorted = _fragments.toList(growable: false)
      ..sort((a, b) {
        final pageCompare = a.pageIndex.compareTo(b.pageIndex);
        if (pageCompare != 0) return pageCompare;
        final topCompare = a.globalRect.top.compareTo(b.globalRect.top);
        if (topCompare != 0) return topCompare;
        final leftCompare = a.globalRect.left.compareTo(b.globalRect.left);
        if (leftCompare != 0) return leftCompare;
        return a.id.compareTo(b.id);
      });
    return TextSystemDocumentLayoutIndex(
      documentId: documentId,
      fragments: List<TextSystemDocumentLayoutFragment>.unmodifiable(sorted),
    );
  }
}

Map<String, Object?> _rectToJson(Rect rect) {
  return <String, Object?>{
    'left': rect.left,
    'top': rect.top,
    'right': rect.right,
    'bottom': rect.bottom,
    'width': rect.width,
    'height': rect.height,
  };
}

Map<String, Object?> _offsetToJson(Offset offset) {
  return <String, Object?>{
    'dx': offset.dx,
    'dy': offset.dy,
  };
}
