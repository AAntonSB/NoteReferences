import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/text_system_block.dart';
import '../core/text_system_document_layout_index.dart';
import '../core/text_system_document_position.dart';
import '../page/text_system_layout_style_resolver.dart';
import '../page/text_system_page_setup.dart';
import 'text_system_editor_layout_snapshot.dart';
import 'text_system_editor_marked_text_layout.dart';
import 'text_system_editor_text_input_client.dart';

/// Draws the active IME/dead-key composition buffer at the owned editor caret.
///
/// The text is intentionally transient: it is not inserted into the document
/// model until the platform commits it through [TextSystemEditorTextInputClient].
class TextSystemEditorComposingOverlay extends StatelessWidget {
  const TextSystemEditorComposingOverlay({
    super.key,
    required this.snapshot,
    required this.textInputClient,
    required this.pageIndex,
    required this.pageSetup,
    required this.color,
  });

  final TextSystemEditorLayoutSnapshot snapshot;
  final TextSystemEditorTextInputClient textInputClient;
  final int pageIndex;
  final TextSystemPageSetup pageSetup;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: textInputClient,
      builder: (context, child) {
        final text = textInputClient.composingText;
        final anchor = textInputClient.compositionAnchor;
        if (text.isEmpty || anchor == null || !anchor.isTextOffset) {
          return const SizedBox.shrink();
        }
        final pageRect = _pageRect;
        if (pageRect == null) return const SizedBox.shrink();
        final caretRect = _preciseCaretRectForPosition(context, anchor) ?? snapshot.rectForPosition(anchor);
        if (caretRect == null) return const SizedBox.shrink();
        if (!_isOnThisPage(caretRect)) return const SizedBox.shrink();

        final local = caretRect.shift(Offset(-pageRect.left, -pageRect.top));
        final block = snapshot.blockById(anchor.blockId);
        final baseStyle = block == null
            ? Theme.of(context).textTheme.bodyMedium ?? const TextStyle(fontSize: 15)
            : TextSystemLayoutStyleResolver.blockStyle(
                context: context,
                block: block,
                pageSetup: pageSetup,
              );
        final style = baseStyle.copyWith(
          color: color,
          decoration: TextDecoration.underline,
          decorationStyle: TextDecorationStyle.solid,
          decorationThickness: 1.3,
        );
        return Positioned(
          left: local.right,
          top: local.top,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1),
                child: Text(text, style: style),
              ),
            ),
          ),
        );
      },
    );
  }

  Rect? get _pageRect {
    for (final page in snapshot.layoutIndex.pages) {
      if (page.pageIndex == pageIndex) return page.globalRect;
    }
    return null;
  }

  bool _isOnThisPage(Rect rect) {
    final center = rect.center;
    for (final page in snapshot.layoutIndex.pages) {
      if (page.pageIndex == pageIndex) {
        return page.globalRect.inflate(1).contains(center);
      }
    }
    return false;
  }

  Rect? _preciseCaretRectForPosition(
    BuildContext context,
    TextSystemDocumentPosition position,
  ) {
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
      sourceStart: safeStart,
      sourceEnd: safeEnd,
      continuesFromPreviousPage: fragment.metadata['continuesFromPreviousPage'] == true,
    );
    final visualCaretOffset = visible.documentOffsetToVisual(position.offset);

    final style = TextSystemLayoutStyleResolver.blockStyle(
      context: context,
      block: block,
      pageSetup: pageSetup,
    );
    final codePadding = block.type == TextSystemBlockType.code
        ? const EdgeInsets.symmetric(horizontal: 10, vertical: 8)
        : EdgeInsets.zero;
    final maxWidth = math.max(1.0, fragment.globalRect.width - codePadding.horizontal);
    final painter = TextPainter(
      text: TextSystemEditorMarkedTextLayout.textSpanForVisibleFragment(
        context: context,
        visible: visible,
        baseStyle: style,
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout(maxWidth: maxWidth);

    final offset = painter.getOffsetForCaret(
      TextPosition(offset: visualCaretOffset),
      Rect.fromLTWH(0, 0, 1, painter.preferredLineHeight),
    );
    return Rect.fromLTWH(
      fragment.globalRect.left + codePadding.left + offset.dx,
      fragment.globalRect.top + codePadding.top + offset.dy,
      1,
      math.max(12.0, painter.preferredLineHeight),
    );
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
      final start = fragment.start!.offset;
      final end = fragment.end!.offset;
      if (position.offset >= start && position.offset <= end) return fragment;
    }

    candidates.sort((a, b) {
      final ad = _distanceToFragmentOffset(position.offset, a);
      final bd = _distanceToFragmentOffset(position.offset, b);
      return ad.compareTo(bd);
    });
    return candidates.first;
  }

  int _distanceToFragmentOffset(int offset, TextSystemDocumentLayoutFragment fragment) {
    final start = fragment.start?.offset ?? 0;
    final end = fragment.end?.offset ?? start;
    if (offset < start) return start - offset;
    if (offset > end) return offset - end;
    return 0;
  }
}
