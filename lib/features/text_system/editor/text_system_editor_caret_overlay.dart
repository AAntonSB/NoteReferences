import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show TextSelection;

import '../core/text_system_block.dart';
import '../core/text_system_document_layout_index.dart';
import '../core/text_system_document_position.dart';
import '../core/text_system_document_range.dart';
import '../core/text_system_document_selection_controller.dart';
import '../core/text_system_range.dart';
import '../page/text_system_layout_style_resolver.dart';
import '../page/text_system_page_setup.dart';
import 'text_system_editor_layout_snapshot.dart';
import 'text_system_editor_marked_text_layout.dart';
import 'text_system_editor_selection_state.dart';

/// Paints the owned-editor caret and atomic block selection affordances.
///
/// The generic layout index stores block-fragment rectangles, not glyph-level
/// caret geometry. For collapsed text selections this overlay therefore
/// reconstructs the visible fragment with [TextPainter] and asks Flutter for the
/// exact caret offset inside the line/paragraph. This prevents short paragraphs
/// from placing the caret at the far right edge of the page simply because the
/// fragment's layout rectangle spans the full content column.
class TextSystemEditorCaretOverlay extends StatelessWidget {
  const TextSystemEditorCaretOverlay({
    super.key,
    required this.snapshot,
    required this.selectionState,
    required this.pageIndex,
    required this.pageSetup,
    this.activeInlineAtomSourceRange,
    required this.caretColor,
    required this.selectionColor,
    this.caretWidth = 2.0,
  });

  final TextSystemEditorLayoutSnapshot snapshot;
  final TextSystemEditorSelectionState selectionState;
  final int pageIndex;
  final TextSystemPageSetup pageSetup;
  final TextSystemDocumentRange? activeInlineAtomSourceRange;
  final Color caretColor;
  final Color selectionColor;
  final double caretWidth;

  @override
  Widget build(BuildContext context) {
    final pageRect = _pageRect;
    if (pageRect == null || !selectionState.hasSelection) {
      return const SizedBox.shrink();
    }

    final selection = selectionState.selection;
    if (selection == null) return const SizedBox.shrink();

    if (!selection.isCollapsed || !selection.focus.isTextOffset) {
      return const SizedBox.shrink();
    }

    final rect = _caretRectForSelection(context, selection);
    if (rect == null) return const SizedBox.shrink();
    return _buildCaret(rect, pageRect);
  }

  Rect? get _pageRect {
    for (final page in snapshot.layoutIndex.pages) {
      if (page.pageIndex == pageIndex) return page.globalRect;
    }
    return null;
  }

  Widget _buildCaret(Rect globalRect, Rect pageRect) {
    final local = _toPageLocal(globalRect, pageRect);
    final height = math.max(12.0, local.height);
    final top = local.top;
    return Positioned(
      left: local.left - caretWidth / 2,
      top: top,
      width: caretWidth,
      height: height,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: caretColor,
            borderRadius: BorderRadius.circular(caretWidth),
          ),
        ),
      ),
    );
  }

  Rect? _caretRectForSelection(
    BuildContext context,
    TextSystemDocumentSelection selection,
  ) {
    final precise = _preciseCaretRectForPosition(context, selection.focus);
    if (precise != null) return precise;

    final focusHit = selectionState.focusHit;
    final metadataRect = focusHit?.metadata['caretGlobalRect'];
    if (metadataRect is Rect && focusHit?.pageIndex == pageIndex) {
      return metadataRect;
    }

    final rect = snapshot.rectForPosition(selection.focus);
    if (rect == null) return null;
    final fragmentPage = _pageIndexForGlobalRect(rect);
    if (fragmentPage != pageIndex) return null;
    return Rect.fromLTWH(rect.left, rect.top, math.max(1.0, rect.width), rect.height);
  }

  Rect? _preciseCaretRectForPosition(
    BuildContext context,
    TextSystemDocumentPosition position,
  ) {
    if (!position.isTextOffset) return null;

    final block = snapshot.blockById(position.blockId);
    if (block == null) return null;

    final fragment = _textFragmentForPosition(position);
    if (fragment == null) return null;

    final startOffset = fragment.start?.offset ?? 0;
    final endOffset = fragment.end?.offset ?? startOffset;
    final safeStart = startOffset.clamp(0, block.text.length).toInt();
    final safeEnd = endOffset.clamp(safeStart, block.text.length).toInt();
    final visible = TextSystemEditorMarkedTextLayout.visibleFragmentFor(
      block: block,
      blockIndex: position.blockIndex,
      sourceStart: safeStart,
      sourceEnd: safeEnd,
      continuesFromPreviousPage: fragment.metadata['continuesFromPreviousPage'] == true,
    );
    final visualCaretOffset = visible.documentOffsetToVisual(position.offset);

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

    final caretOffset = painter.getOffsetForCaret(
      TextPosition(offset: visualCaretOffset),
      Rect.fromLTWH(0, 0, 1, painter.preferredLineHeight),
    );
    final caretHeight = math.max(12.0, _heightNearCaret(painter, visualCaretOffset, visible.visibleText.length));
    return Rect.fromLTWH(
      fragment.globalRect.left + codePadding.left + listTextInset + displayEquationTextLeftInset + caretOffset.dx,
      fragment.globalRect.top + codePadding.top + displayEquationTextTopInset + caretOffset.dy,
      1,
      caretHeight,
    );
  }


  TextSystemRange? _activeSourceTextRangeForBlock(TextSystemBlock block) {
    final range = activeInlineAtomSourceRange?.normalized();
    if (range == null || range.start.blockId != block.id || range.end.blockId != block.id) return null;
    return TextSystemRange(
      range.start.offset.clamp(0, block.text.length).toInt(),
      range.end.offset.clamp(0, block.text.length).toInt(),
    );
  }

  double _heightNearCaret(
    TextPainter painter,
    int visualCaretOffset,
    int visibleTextLength,
  ) {
    if (visibleTextLength <= 0) return painter.preferredLineHeight;
    final start = visualCaretOffset.clamp(0, math.max(0, visibleTextLength - 1)).toInt();
    final end = math.min(visibleTextLength, start + 1);
    final forwardBoxes = painter.getBoxesForSelection(
      TextSelection(baseOffset: start, extentOffset: end),
    );
    if (forwardBoxes.isNotEmpty) return forwardBoxes.first.toRect().height;

    if (visualCaretOffset > 0) {
      final backwardStart = math.max(0, visualCaretOffset - 1);
      final backwardBoxes = painter.getBoxesForSelection(
        TextSelection(baseOffset: backwardStart, extentOffset: visualCaretOffset),
      );
      if (backwardBoxes.isNotEmpty) return backwardBoxes.last.toRect().height;
    }
    return painter.preferredLineHeight;
  }

  TextSystemDocumentLayoutFragment? _textFragmentForPosition(
    TextSystemDocumentPosition position,
  ) {
    final candidates = snapshot.layoutIndex
        .fragmentsForBlock(position.blockId)
        .where((fragment) => fragment.pageIndex == pageIndex && fragment.isTextLike && fragment.start != null && fragment.end != null)
        .toList(growable: false);
    if (candidates.isEmpty) return null;

    for (final fragment in candidates) {
      final startOffset = fragment.start!.offset;
      final endOffset = fragment.end!.offset;
      if (position.offset >= startOffset && position.offset < endOffset) {
        return fragment;
      }
    }

    for (final fragment in candidates) {
      final startOffset = fragment.start!.offset;
      final endOffset = fragment.end!.offset;
      if (position.offset >= startOffset && position.offset <= endOffset) {
        return fragment;
      }
    }

    candidates.sort((a, b) {
      final aDistance = _distanceToFragmentOffset(position.offset, a);
      final bDistance = _distanceToFragmentOffset(position.offset, b);
      return aDistance.compareTo(bDistance);
    });
    return candidates.first;
  }

  int _distanceToFragmentOffset(
    int offset,
    TextSystemDocumentLayoutFragment fragment,
  ) {
    final startOffset = fragment.start?.offset ?? 0;
    final endOffset = fragment.end?.offset ?? startOffset;
    if (offset < startOffset) return startOffset - offset;
    if (offset > endOffset) return offset - endOffset;
    return 0;
  }
  Rect? _objectRectForSelection(TextSystemDocumentSelection selection) {
    final blockId = selection.objectBlockId ?? selection.tableBlockId ?? selection.anchor.blockId;
    final fragments = snapshot.layoutIndex.fragmentsForBlock(blockId);
    for (final fragment in fragments) {
      if (fragment.pageIndex != pageIndex) continue;
      if (fragment.isObjectLike || fragment.isTableCell) return fragment.globalRect;
    }
    return null;
  }

  int? _pageIndexForGlobalRect(Rect rect) {
    final center = rect.center;
    for (final page in snapshot.layoutIndex.pages) {
      if (page.globalRect.inflate(1).contains(center)) return page.pageIndex;
    }
    return null;
  }

  Rect _toPageLocal(Rect globalRect, Rect pageRect) {
    return globalRect.shift(Offset(-pageRect.left, -pageRect.top));
  }
}
