import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show TextSelection;

import '../core/text_system_block.dart';
import '../core/text_system_document_layout_index.dart';
import '../core/text_system_document_range.dart';
import '../core/text_system_document_selection_controller.dart';
import '../core/text_system_document_selection_overlay.dart';
import '../core/text_system_range.dart';
import '../page/text_system_layout_style_resolver.dart';
import '../page/text_system_page_setup.dart';
import 'text_system_editor_layout_snapshot.dart';
import 'text_system_editor_marked_text_layout.dart';
import 'text_system_editor_selection_state.dart';
import 'objects/owned_content_object_geometry.dart';

/// Renders owned-editor document selections from the model selection and the
/// current layout snapshot.
///
/// This is deliberately separate from [TextSystemEditorCaretOverlay]. The caret
/// overlay handles the collapsed insertion point; this overlay handles real
/// document selections: partial text selections, cross-block ranges, cross-page
/// ranges, and atomic object/table/equation/structural-break selection visuals.
class TextSystemEditorSelectionOverlay extends StatelessWidget {
  const TextSystemEditorSelectionOverlay({
    super.key,
    required this.snapshot,
    required this.selectionState,
    required this.pageIndex,
    required this.pageSetup,
    this.activeInlineAtomSourceRange,
    required this.selectionColor,
    this.borderColor,
  });

  final TextSystemEditorLayoutSnapshot snapshot;
  final TextSystemEditorSelectionState selectionState;
  final int pageIndex;
  final TextSystemPageSetup pageSetup;
  final TextSystemDocumentRange? activeInlineAtomSourceRange;
  final Color selectionColor;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final selection = selectionState.selection;
    final pageRect = _pageRect;
    if (selection == null || pageRect == null) {
      return const SizedBox.shrink();
    }

    final visuallyCollapsed = selection.kind == TextSystemDocumentSelectionKind.collapsed && selection.isCollapsed;
    if (visuallyCollapsed) {
      return const SizedBox.shrink();
    }

    final visuals = _buildVisuals(context, selection)
        .where((visual) => visual.pageIndex == pageIndex)
        .toList(growable: false);
    if (visuals.isEmpty) return const SizedBox.shrink();

    return Stack(
      children: [
        for (final visual in visuals)
          Positioned.fromRect(
            rect: _toPageLocal(_rectForVisual(visual), pageRect),
            child: IgnorePointer(child: _SelectionVisualBox(visual: visual, color: selectionColor, borderColor: borderColor)),
          ),
      ],
    );
  }

  Rect? get _pageRect {
    for (final page in snapshot.layoutIndex.pages) {
      if (page.pageIndex == pageIndex) return page.globalRect;
    }
    return null;
  }

  List<TextSystemDocumentSelectionVisual> _buildVisuals(
    BuildContext context,
    TextSystemDocumentSelection selection,
  ) {
    if (!selection.isRange) {
      return TextSystemDocumentSelectionOverlay(layoutIndex: snapshot.layoutIndex)
          .buildVisuals(selection)
          .where((visual) => visual.kind != TextSystemDocumentSelectionVisualKind.caret)
          .toList(growable: false);
    }

    final range = selection.range.normalized();
    final visuals = <TextSystemDocumentSelectionVisual>[];
    for (final fragment in snapshot.layoutIndex.nonPageFragments) {
      if (!_fragmentIntersectsRange(fragment, range)) continue;

      if (fragment.isTextLike) {
        visuals.addAll(_preciseTextVisualsForFragment(context, fragment, range));
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
    return List<TextSystemDocumentSelectionVisual>.unmodifiable(_mergeAdjacentTextVisuals(visuals));
  }

  bool _fragmentIntersectsRange(
    TextSystemDocumentLayoutFragment fragment,
    TextSystemDocumentRange normalized,
  ) {
    final start = fragment.start;
    final end = fragment.end;
    if (start == null || end == null) return false;
    return end.compareTo(normalized.start) > 0 && start.compareTo(normalized.end) < 0;
  }

  List<TextSystemDocumentSelectionVisual> _preciseTextVisualsForFragment(
    BuildContext context,
    TextSystemDocumentLayoutFragment fragment,
    TextSystemDocumentRange normalized,
  ) {
    final blockId = fragment.blockId;
    final block = blockId == null ? null : snapshot.blockById(blockId);
    final start = fragment.start;
    final end = fragment.end;
    if (block == null || start == null || end == null) {
      return const <TextSystemDocumentSelectionVisual>[];
    }

    final fragmentStart = start.offset.clamp(0, block.text.length).toInt();
    final fragmentEnd = end.offset.clamp(fragmentStart, block.text.length).toInt();
    if (fragmentEnd <= fragmentStart) return const <TextSystemDocumentSelectionVisual>[];

    var selectedStart = fragmentStart;
    var selectedEnd = fragmentEnd;
    if (normalized.start.blockId == block.id) {
      selectedStart = math.max(selectedStart, normalized.start.offset);
    }
    if (normalized.end.blockId == block.id) {
      selectedEnd = math.min(selectedEnd, normalized.end.offset);
    }
    selectedStart = selectedStart.clamp(fragmentStart, fragmentEnd).toInt();
    selectedEnd = selectedEnd.clamp(fragmentStart, fragmentEnd).toInt();
    if (selectedEnd <= selectedStart) return const <TextSystemDocumentSelectionVisual>[];

    final visible = TextSystemEditorMarkedTextLayout.visibleFragmentFor(
      block: block,
      blockIndex: fragment.start?.blockIndex ?? 0,
      sourceStart: fragmentStart,
      sourceEnd: fragmentEnd,
      continuesFromPreviousPage: fragment.metadata['continuesFromPreviousPage'] == true,
    );
    final visualStart = visible.documentOffsetToVisual(selectedStart);
    final visualEnd = visible.documentOffsetToVisual(selectedEnd);
    if (visualEnd <= visualStart) return const <TextSystemDocumentSelectionVisual>[];

    final style = TextSystemEditorMarkedTextLayout.effectiveTextStyleFor(
      context,
      block,
      TextSystemLayoutStyleResolver.blockStyle(
        context: context,
        block: block,
        pageSetup: pageSetup,
      ),
    );
    final isDisplayEquationBlock = TextSystemEditorMarkedTextLayout.isDisplayEquationBlock(block);
    final layoutTextStyle = isDisplayEquationBlock
        ? TextSystemEditorMarkedTextLayout.displayEquationSourceTextStyleFor(context, style)
        : style;
    final codePadding = block.type == TextSystemBlockType.code
        ? const EdgeInsets.symmetric(horizontal: 10, vertical: 8)
        : EdgeInsets.zero;
    final listTextInset = TextSystemEditorMarkedTextLayout.listTextInsetFor(block);
    final availableTextWidth = math.max(1.0, fragment.globalRect.width - codePadding.horizontal - listTextInset);
    final maxWidth = isDisplayEquationBlock
        ? TextSystemEditorMarkedTextLayout.displayEquationSourceTextMaxWidth(availableWidth: availableTextWidth)
        : availableTextWidth;
    final activeSourceTextRange = _activeSourceTextRangeForBlock(block);
    final painter = TextPainter(
      text: TextSystemEditorMarkedTextLayout.textSpanForVisibleFragment(
        context: context,
        visible: visible,
        baseStyle: layoutTextStyle,
        activeInlineAtomSourceRange: activeSourceTextRange,
      ),
      textAlign: TextSystemEditorMarkedTextLayout.sourceTextAlignFor(block),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout(maxWidth: maxWidth);

    final boxes = painter.getBoxesForSelection(
      TextSelection(baseOffset: visualStart, extentOffset: visualEnd),
    );
    if (boxes.isEmpty) {
      final fallback = snapshot.layoutIndex.rectForPosition(start);
      if (fallback == null) return const <TextSystemDocumentSelectionVisual>[];
      return <TextSystemDocumentSelectionVisual>[
        TextSystemDocumentSelectionVisual(
          kind: TextSystemDocumentSelectionVisualKind.text,
          rect: Rect.fromLTWH(fallback.left, fallback.top, 1, fallback.height),
          pageIndex: fragment.pageIndex,
          blockId: block.id,
          fragmentId: fragment.id,
          metadata: <String, Object?>{'preciseTextSelection': false},
        ),
      ];
    }

    final displayEquationTextTopInset = isDisplayEquationBlock
        ? TextSystemEditorMarkedTextLayout.displayEquationVerticalTextInset(
            fragmentHeight: fragment.globalRect.height - codePadding.vertical,
            textHeight: painter.height,
          )
        : 0.0;
    final displayEquationTextLeftInset = isDisplayEquationBlock
        ? TextSystemEditorMarkedTextLayout.displayEquationSourceHorizontalInset(
            painter: painter,
            visibleText: visible.visibleText,
            maxWidth: maxWidth,
          )
        : 0.0;
    final origin = Offset(
      fragment.globalRect.left + codePadding.left + listTextInset + displayEquationTextLeftInset,
      fragment.globalRect.top + codePadding.top + displayEquationTextTopInset,
    );
    return boxes.map((box) {
      final rect = box.toRect().shift(origin);
      final safeRect = Rect.fromLTRB(
        rect.left,
        rect.top,
        math.max(rect.left + 1.0, rect.right),
        math.max(rect.top + 1.0, rect.bottom),
      );
      return TextSystemDocumentSelectionVisual(
        kind: TextSystemDocumentSelectionVisualKind.text,
        rect: safeRect,
        pageIndex: fragment.pageIndex,
        blockId: block.id,
        fragmentId: fragment.id,
        metadata: <String, Object?>{
          'fragmentKind': fragment.kind.name,
          'preciseTextSelection': true,
        },
      );
    }).toList(growable: false);
  }

  TextSystemRange? _activeSourceTextRangeForBlock(TextSystemBlock block) {
    final range = activeInlineAtomSourceRange?.normalized();
    if (range == null || range.start.blockId != block.id || range.end.blockId != block.id) return null;
    return TextSystemRange(
      range.start.offset.clamp(0, block.text.length).toInt(),
      range.end.offset.clamp(0, block.text.length).toInt(),
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

  List<TextSystemDocumentSelectionVisual> _mergeAdjacentTextVisuals(
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
          (previous.rect.top - visual.rect.top).abs() < 0.75 &&
          (previous.rect.bottom - visual.rect.bottom).abs() < 0.75 &&
          visual.rect.left <= previous.rect.right + 1.0;
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
        metadata: <String, Object?>{...previous.metadata, 'merged': true},
      );
    }
    return merged;
  }

  Rect _rectForVisual(TextSystemDocumentSelectionVisual visual) {
    if (visual.kind == TextSystemDocumentSelectionVisualKind.object && visual.metadata['fragmentKind'] == 'figure') {
      final blockId = visual.blockId;
      final block = blockId == null ? null : snapshot.blockById(blockId);
      return OwnedContentObjectGeometry.figureImageRectInsideBlock(
        blockRect: visual.rect,
        block: block,
      );
    }
    if (visual.kind != TextSystemDocumentSelectionVisualKind.structuralBlock) {
      return visual.rect;
    }
    final height = visual.rect.height <= 0 ? 3.0 : math.min(8.0, math.max(3.0, visual.rect.height));
    return Rect.fromLTWH(
      visual.rect.left,
      visual.rect.center.dy - height / 2,
      visual.rect.width,
      height,
    );
  }

  Rect _toPageLocal(Rect globalRect, Rect pageRect) {
    return globalRect.shift(Offset(-pageRect.left, -pageRect.top));
  }
}

class _SelectionVisualBox extends StatelessWidget {
  const _SelectionVisualBox({
    required this.visual,
    required this.color,
    this.borderColor,
  });

  final TextSystemDocumentSelectionVisual visual;
  final Color color;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final border = borderColor ?? color;
    final decoration = switch (visual.kind) {
      TextSystemDocumentSelectionVisualKind.text => BoxDecoration(
          color: color.withValues(alpha: 0.22),
          borderRadius: BorderRadius.circular(3),
        ),
      TextSystemDocumentSelectionVisualKind.inlineAtom => BoxDecoration(
          color: color.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: border.withValues(alpha: 0.56), width: 1.2),
        ),
      TextSystemDocumentSelectionVisualKind.tableCell => BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: border.withValues(alpha: 0.72), width: 1.5),
        ),
      TextSystemDocumentSelectionVisualKind.object => BoxDecoration(
          color: visual.metadata['fragmentKind'] == 'figure'
              ? Colors.transparent
              : color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(visual.metadata['fragmentKind'] == 'figure' ? 2 : 10),
          border: Border.all(color: border.withValues(alpha: 0.82), width: 2),
        ),
      TextSystemDocumentSelectionVisualKind.structuralBlock => BoxDecoration(
          color: color.withValues(alpha: 0.34),
          borderRadius: BorderRadius.circular(999),
        ),
      TextSystemDocumentSelectionVisualKind.fullBlock => BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: border.withValues(alpha: 0.64), width: 1.5),
        ),
      TextSystemDocumentSelectionVisualKind.caret => BoxDecoration(color: color),
    };
    return DecoratedBox(decoration: decoration);
  }
}
