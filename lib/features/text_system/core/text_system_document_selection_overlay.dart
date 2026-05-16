import 'dart:math' as math;
import 'dart:ui';

import 'text_system_document_layout_index.dart';
import 'text_system_document_position.dart';
import 'text_system_document_range.dart';
import 'text_system_document_selection_controller.dart';

/// Visual categories produced by [TextSystemDocumentSelectionOverlay].
///
/// These are intentionally model-facing. The actual Flutter painter can decide
/// colors, opacity, corner radius, and animation later. The important point is
/// that selection visuals are derived from [TextSystemDocumentSelection] and the
/// layout index, not from widget-local state.
enum TextSystemDocumentSelectionVisualKind {
  caret,
  text,
  inlineAtom,
  object,
  tableCell,
  structuralBlock,
  fullBlock,
}

/// One visual rectangle for a model-level document selection.
class TextSystemDocumentSelectionVisual {
  const TextSystemDocumentSelectionVisual({
    required this.kind,
    required this.rect,
    required this.pageIndex,
    this.blockId,
    this.fragmentId,
    this.metadata = const <String, Object?>{},
  });

  final TextSystemDocumentSelectionVisualKind kind;
  final Rect rect;
  final int pageIndex;
  final String? blockId;
  final String? fragmentId;
  final Map<String, Object?> metadata;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'kind': kind.name,
      'rect': _rectToJson(rect),
      'pageIndex': pageIndex,
      if (blockId != null) 'blockId': blockId,
      if (fragmentId != null) 'fragmentId': fragmentId,
      if (metadata.isNotEmpty) 'metadata': metadata,
    };
  }
}

/// Builds visual selection/caret rectangles from the model-layer selection and
/// the layout-to-document index.
///
/// The overlay is not the source of truth. It is a pure projection:
///
///     TextSystemDocumentSelection + TextSystemDocumentLayoutIndex
///         -> visual rectangles
///
/// This keeps later mouse selection, shift-arrow selection, comments, citations,
/// and source-link ranges anchored in document coordinates rather than widget
/// state.
class TextSystemDocumentSelectionOverlay {
  const TextSystemDocumentSelectionOverlay({
    required this.layoutIndex,
    this.caretWidth = 1.5,
    this.minimumSelectionWidth = 1.0,
  });

  final TextSystemDocumentLayoutIndex layoutIndex;
  final double caretWidth;
  final double minimumSelectionWidth;

  /// Compatibility API requested by the architecture plan.
  ///
  /// Returns only the rectangles for a range. Call [buildVisualsForRange] when
  /// callers also need block/page/fragment diagnostics.
  List<Rect> buildSelectionRects(TextSystemDocumentRange range) {
    return buildVisualsForRange(range).map((visual) => visual.rect).toList(growable: false);
  }

  /// Builds visuals for a full selection model, including object selections,
  /// inline atom selections, table-cell selections, collapsed caret positions,
  /// and mixed document ranges.
  List<TextSystemDocumentSelectionVisual> buildVisuals(
    TextSystemDocumentSelection? selection,
  ) {
    if (selection == null) return const <TextSystemDocumentSelectionVisual>[];

    switch (selection.kind) {
      case TextSystemDocumentSelectionKind.collapsed:
        final caret = buildCaretVisual(selection.focus);
        return caret == null ? const <TextSystemDocumentSelectionVisual>[] : <TextSystemDocumentSelectionVisual>[caret];
      case TextSystemDocumentSelectionKind.object:
        return _buildObjectVisuals(selection.objectBlockId ?? selection.anchor.blockId);
      case TextSystemDocumentSelectionKind.inlineAtom:
        return _buildInlineAtomVisuals(selection);
      case TextSystemDocumentSelectionKind.tableCell:
        return _buildTableCellVisuals(selection);
      case TextSystemDocumentSelectionKind.textRange:
      case TextSystemDocumentSelectionKind.mixedRange:
        return buildVisualsForRange(selection.range);
    }
  }

  /// Builds text/object selection visuals for [range].
  ///
  /// The implementation supports:
  ///
  /// * partial selection in the start/end text fragments,
  /// * full selection across middle text fragments,
  /// * full-object outlines/fills for figures, tables, equations, page breaks,
  ///   and section breaks,
  /// * inline atoms as semantic inline rectangles,
  /// * table cells as explicit cell rectangles when a range touches them.
  List<TextSystemDocumentSelectionVisual> buildVisualsForRange(TextSystemDocumentRange range) {
    final normalized = range.normalized();
    if (normalized.isCollapsed) {
      final caret = buildCaretVisual(normalized.start);
      return caret == null ? const <TextSystemDocumentSelectionVisual>[] : <TextSystemDocumentSelectionVisual>[caret];
    }

    final visuals = <TextSystemDocumentSelectionVisual>[];
    for (final fragment in layoutIndex.nonPageFragments) {
      if (!_fragmentIntersectsNormalizedRange(fragment, normalized)) continue;

      if (fragment.isTextLike) {
        final rect = _textSelectionRectForFragment(fragment, normalized);
        if (rect == null) continue;
        visuals.add(TextSystemDocumentSelectionVisual(
          kind: TextSystemDocumentSelectionVisualKind.text,
          rect: rect,
          pageIndex: fragment.pageIndex,
          blockId: fragment.blockId,
          fragmentId: fragment.id,
          metadata: <String, Object?>{
            'fragmentKind': fragment.kind.name,
          },
        ));
        continue;
      }

      if (fragment.isInlineAtom) {
        visuals.add(TextSystemDocumentSelectionVisual(
          kind: TextSystemDocumentSelectionVisualKind.inlineAtom,
          rect: fragment.globalRect,
          pageIndex: fragment.pageIndex,
          blockId: fragment.blockId,
          fragmentId: fragment.id,
          metadata: <String, Object?>{
            'atomId': fragment.atomId,
            'fragmentKind': fragment.kind.name,
          },
        ));
        continue;
      }

      if (fragment.isTableCell) {
        visuals.add(TextSystemDocumentSelectionVisual(
          kind: TextSystemDocumentSelectionVisualKind.tableCell,
          rect: fragment.globalRect,
          pageIndex: fragment.pageIndex,
          blockId: fragment.blockId,
          fragmentId: fragment.id,
          metadata: <String, Object?>{
            'row': fragment.tableRow,
            'column': fragment.tableColumn,
          },
        ));
        continue;
      }

      if (fragment.isObjectLike) {
        visuals.add(TextSystemDocumentSelectionVisual(
          kind: _visualKindForObjectFragment(fragment),
          rect: fragment.globalRect,
          pageIndex: fragment.pageIndex,
          blockId: fragment.blockId,
          fragmentId: fragment.id,
          metadata: <String, Object?>{
            'fragmentKind': fragment.kind.name,
          },
        ));
      }
    }

    return List<TextSystemDocumentSelectionVisual>.unmodifiable(_mergeAdjacentTextRects(visuals));
  }

  TextSystemDocumentSelectionVisual? buildCaretVisual(TextSystemDocumentPosition position) {
    final rect = layoutIndex.rectForPosition(position);
    if (rect == null) return null;
    final caretRect = Rect.fromLTWH(
      rect.left,
      rect.top,
      math.max(caretWidth, rect.width),
      math.max(1.0, rect.height),
    );
    return TextSystemDocumentSelectionVisual(
      kind: TextSystemDocumentSelectionVisualKind.caret,
      rect: caretRect,
      pageIndex: _pageIndexForPosition(position),
      blockId: position.blockId,
      metadata: <String, Object?>{
        'position': position.toJson(),
      },
    );
  }

  Map<String, Object?> diagnosticsForSelection(TextSystemDocumentSelection? selection) {
    final visuals = buildVisuals(selection);
    return <String, Object?>{
      'selection': selection?.toJson(),
      'visualCount': visuals.length,
      'visuals': visuals.map((visual) => visual.toJson()).toList(growable: false),
    };
  }

  Map<String, Object?> diagnosticsForRange(TextSystemDocumentRange range) {
    final visuals = buildVisualsForRange(range);
    return <String, Object?>{
      'range': range.toJson(),
      'visualCount': visuals.length,
      'visuals': visuals.map((visual) => visual.toJson()).toList(growable: false),
    };
  }

  List<TextSystemDocumentSelectionVisual> _buildObjectVisuals(String blockId) {
    final fragments = layoutIndex.fragmentsForBlock(blockId)
        .where((fragment) => fragment.isObjectLike)
        .toList(growable: false);
    if (fragments.isEmpty) {
      final fallbackFragments = layoutIndex.fragmentsForBlock(blockId);
      return fallbackFragments
          .map((fragment) => TextSystemDocumentSelectionVisual(
                kind: TextSystemDocumentSelectionVisualKind.fullBlock,
                rect: fragment.globalRect,
                pageIndex: fragment.pageIndex,
                blockId: blockId,
                fragmentId: fragment.id,
                metadata: <String, Object?>{'fragmentKind': fragment.kind.name},
              ))
          .toList(growable: false);
    }
    return fragments
        .map((fragment) => TextSystemDocumentSelectionVisual(
              kind: _visualKindForObjectFragment(fragment),
              rect: fragment.globalRect,
              pageIndex: fragment.pageIndex,
              blockId: blockId,
              fragmentId: fragment.id,
              metadata: <String, Object?>{'fragmentKind': fragment.kind.name},
            ))
        .toList(growable: false);
  }

  List<TextSystemDocumentSelectionVisual> _buildInlineAtomVisuals(
    TextSystemDocumentSelection selection,
  ) {
    final atomId = selection.inlineAtomId;
    final blockId = selection.anchor.blockId;
    final atomStart = selection.anchor.atomStartOffset;
    final atomEnd = selection.anchor.atomEndOffset;

    final exact = layoutIndex.fragmentsForBlock(blockId).where((fragment) {
      if (!fragment.isInlineAtom) return false;
      if (atomId != null && fragment.atomId == atomId) return true;
      final start = fragment.start?.offset;
      final end = fragment.end?.offset;
      return atomStart != null && atomEnd != null && start == atomStart && end == atomEnd;
    }).toList(growable: false);

    if (exact.isNotEmpty) {
      return exact
          .map((fragment) => TextSystemDocumentSelectionVisual(
                kind: TextSystemDocumentSelectionVisualKind.inlineAtom,
                rect: fragment.globalRect,
                pageIndex: fragment.pageIndex,
                blockId: fragment.blockId,
                fragmentId: fragment.id,
                metadata: <String, Object?>{
                  'atomId': fragment.atomId,
                  'fragmentKind': fragment.kind.name,
                },
              ))
          .toList(growable: false);
    }

    return buildVisualsForRange(selection.range);
  }

  List<TextSystemDocumentSelectionVisual> _buildTableCellVisuals(
    TextSystemDocumentSelection selection,
  ) {
    final tableBlockId = selection.tableBlockId ?? selection.anchor.blockId;
    final startRow = math.min(selection.tableRow ?? 0, selection.tableEndRow ?? selection.tableRow ?? 0);
    final endRow = math.max(selection.tableRow ?? 0, selection.tableEndRow ?? selection.tableRow ?? 0);
    final startColumn = math.min(selection.tableColumn ?? 0, selection.tableEndColumn ?? selection.tableColumn ?? 0);
    final endColumn = math.max(selection.tableColumn ?? 0, selection.tableEndColumn ?? selection.tableColumn ?? 0);

    return layoutIndex.fragmentsForBlock(tableBlockId).where((fragment) {
      if (!fragment.isTableCell) return false;
      final row = fragment.tableRow;
      final column = fragment.tableColumn;
      if (row == null || column == null) return false;
      return row >= startRow && row <= endRow && column >= startColumn && column <= endColumn;
    }).map((fragment) {
      return TextSystemDocumentSelectionVisual(
        kind: TextSystemDocumentSelectionVisualKind.tableCell,
        rect: fragment.globalRect,
        pageIndex: fragment.pageIndex,
        blockId: fragment.blockId,
        fragmentId: fragment.id,
        metadata: <String, Object?>{
          'row': fragment.tableRow,
          'column': fragment.tableColumn,
        },
      );
    }).toList(growable: false);
  }

  bool _fragmentIntersectsNormalizedRange(
    TextSystemDocumentLayoutFragment fragment,
    TextSystemDocumentRange normalized,
  ) {
    final start = fragment.start;
    final end = fragment.end;
    if (start == null || end == null) return false;

    // Half-open overlap: fragmentEnd > rangeStart && fragmentStart < rangeEnd.
    return end.compareTo(normalized.start) > 0 && start.compareTo(normalized.end) < 0;
  }

  Rect? _textSelectionRectForFragment(
    TextSystemDocumentLayoutFragment fragment,
    TextSystemDocumentRange normalized,
  ) {
    final start = fragment.start;
    final end = fragment.end;
    if (start == null || end == null) return null;
    final fragmentStartOffset = start.offset;
    final fragmentEndOffset = end.offset;
    if (fragmentEndOffset <= fragmentStartOffset) return null;

    var selectedStart = fragmentStartOffset;
    var selectedEnd = fragmentEndOffset;

    if (normalized.start.blockId == fragment.blockId) {
      selectedStart = math.max(selectedStart, normalized.start.offset);
    }
    if (normalized.end.blockId == fragment.blockId) {
      selectedEnd = math.min(selectedEnd, normalized.end.offset);
    }

    selectedStart = selectedStart.clamp(fragmentStartOffset, fragmentEndOffset).toInt();
    selectedEnd = selectedEnd.clamp(fragmentStartOffset, fragmentEndOffset).toInt();
    if (selectedEnd <= selectedStart) return null;

    final width = fragment.globalRect.width;
    if (width <= 0) {
      return Rect.fromLTWH(
        fragment.globalRect.left,
        fragment.globalRect.top,
        minimumSelectionWidth,
        fragment.globalRect.height,
      );
    }

    final fragmentLength = fragmentEndOffset - fragmentStartOffset;
    final startRatio = (selectedStart - fragmentStartOffset) / fragmentLength;
    final endRatio = (selectedEnd - fragmentStartOffset) / fragmentLength;
    final left = fragment.globalRect.left + width * startRatio.clamp(0.0, 1.0);
    final right = fragment.globalRect.left + width * endRatio.clamp(0.0, 1.0);
    return Rect.fromLTRB(
      math.min(left, right),
      fragment.globalRect.top,
      math.max(left + minimumSelectionWidth, right),
      fragment.globalRect.bottom,
    );
  }

  TextSystemDocumentSelectionVisualKind _visualKindForObjectFragment(
    TextSystemDocumentLayoutFragment fragment,
  ) {
    switch (fragment.kind) {
      case TextSystemDocumentLayoutFragmentKind.figure:
      case TextSystemDocumentLayoutFragmentKind.table:
      case TextSystemDocumentLayoutFragmentKind.equation:
      case TextSystemDocumentLayoutFragmentKind.objectBlock:
        return TextSystemDocumentSelectionVisualKind.object;
      case TextSystemDocumentLayoutFragmentKind.pageBreak:
      case TextSystemDocumentLayoutFragmentKind.sectionBreak:
        return TextSystemDocumentSelectionVisualKind.structuralBlock;
      case TextSystemDocumentLayoutFragmentKind.tableCell:
        return TextSystemDocumentSelectionVisualKind.tableCell;
      case TextSystemDocumentLayoutFragmentKind.inlineAtom:
        return TextSystemDocumentSelectionVisualKind.inlineAtom;
      case TextSystemDocumentLayoutFragmentKind.textLine:
      case TextSystemDocumentLayoutFragmentKind.textRun:
        return TextSystemDocumentSelectionVisualKind.text;
      case TextSystemDocumentLayoutFragmentKind.page:
      case TextSystemDocumentLayoutFragmentKind.pageMargin:
      case TextSystemDocumentLayoutFragmentKind.commentRail:
      case TextSystemDocumentLayoutFragmentKind.unknown:
        return TextSystemDocumentSelectionVisualKind.fullBlock;
    }
  }

  int _pageIndexForPosition(TextSystemDocumentPosition position) {
    final fragments = layoutIndex.fragmentsForBlock(position.blockId);
    if (fragments.isEmpty) return 0;
    final exactRect = layoutIndex.rectForPosition(position);
    if (exactRect != null) {
      for (final fragment in fragments) {
        if (fragment.globalRect.overlaps(exactRect) || fragment.globalRect.contains(exactRect.center)) {
          return fragment.pageIndex;
        }
      }
    }
    return fragments.first.pageIndex;
  }

  List<TextSystemDocumentSelectionVisual> _mergeAdjacentTextRects(
    List<TextSystemDocumentSelectionVisual> visuals,
  ) {
    if (visuals.length < 2) return visuals;
    final sorted = visuals.toList(growable: false)
      ..sort((a, b) {
        final pageCompare = a.pageIndex.compareTo(b.pageIndex);
        if (pageCompare != 0) return pageCompare;
        final topCompare = a.rect.top.compareTo(b.rect.top);
        if (topCompare != 0) return topCompare;
        return a.rect.left.compareTo(b.rect.left);
      });

    final merged = <TextSystemDocumentSelectionVisual>[];
    for (final visual in sorted) {
      if (visual.kind != TextSystemDocumentSelectionVisualKind.text || merged.isEmpty) {
        merged.add(visual);
        continue;
      }
      final previous = merged.last;
      final sameLine = previous.kind == TextSystemDocumentSelectionVisualKind.text &&
          previous.pageIndex == visual.pageIndex &&
          previous.blockId == visual.blockId &&
          (previous.rect.top - visual.rect.top).abs() < 0.5 &&
          (previous.rect.bottom - visual.rect.bottom).abs() < 0.5 &&
          visual.rect.left <= previous.rect.right + 0.75;
      if (!sameLine) {
        merged.add(visual);
        continue;
      }
      merged[merged.length - 1] = TextSystemDocumentSelectionVisual(
        kind: previous.kind,
        rect: previous.rect.expandToInclude(visual.rect),
        pageIndex: previous.pageIndex,
        blockId: previous.blockId,
        fragmentId: previous.fragmentId,
        metadata: <String, Object?>{
          ...previous.metadata,
          'merged': true,
        },
      );
    }
    return merged;
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
