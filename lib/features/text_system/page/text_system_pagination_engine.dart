import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/text_system_block.dart';
import '../core/text_system_document.dart';
import 'text_system_layout_style_resolver.dart';
import 'text_system_page_map.dart';
import 'text_system_page_setup.dart';

/// Passive, measured pagination for the feature-length writer.
///
/// This engine is intentionally read-only. It measures the current
/// [TextSystemDocument] with TextPainter and returns a [TextSystemPageMap]. It
/// must not call TextSystemController or create transactions.
class TextSystemPaginationEngine {
  const TextSystemPaginationEngine._();

  static TextSystemPageMap paginate({
    required BuildContext context,
    required TextSystemDocument document,
    required TextSystemPageSetup pageSetup,
    required int documentRevision,
    required double pageWidthPx,
  }) {
    final safePageWidth = math.max(240.0, pageWidthPx);
    final pageHeightPx = safePageWidth * pageSetup.heightToWidthRatio;
    final margins = pageSetup.margins.toPagePadding(
      safePageWidth,
      pageSetup.pageWidthMm,
    );
    final contentWidthPx = math.max(80.0, safePageWidth - margins.horizontal);
    final contentHeightPx = math.max(120.0, pageHeightPx - margins.vertical);

    final measuredBlocks = <_MeasuredBlock>[];
    var totalContentHeight = 0.0;

    for (var i = 0; i < document.blocks.length; i++) {
      final block = document.blocks[i];
      final style = TextSystemLayoutStyleResolver.blockStyle(
        context: context,
        block: block,
        pageSetup: pageSetup,
      );
      final visibleText = TextSystemLayoutStyleResolver.visibleTextForBlock(block, i);
      final painter = TextPainter(
        text: TextSpan(text: visibleText, style: style),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout(maxWidth: contentWidthPx);

      final spacingAfter = TextSystemLayoutStyleResolver.afterBlockSpacing(
        block: block,
        style: style,
        pageSetup: pageSetup,
      );
      final blockHeight = math.max(_minimumBlockHeight(style), painter.height) + spacingAfter;

      measuredBlocks.add(
        _MeasuredBlock(
          block: block,
          blockIndex: i,
          visibleText: visibleText,
          heightPx: blockHeight,
          textLineCount: math.max(1, painter.computeLineMetrics().length),
        ),
      );
      totalContentHeight += blockHeight;
    }

    if (measuredBlocks.isEmpty) {
      totalContentHeight = _emptyDocumentHeight(context, pageSetup);
    }

    final pageCount = math.max(1, (math.max(1.0, totalContentHeight) / contentHeightPx).ceil());
    final pages = <TextSystemPageMapPage>[];
    final fragments = <TextSystemPageFragment>[];

    for (var page = 1; page <= pageCount; page++) {
      final start = (page - 1) * contentHeightPx;
      final end = page * contentHeightPx;
      pages.add(
        TextSystemPageMapPage(
          pageNumber: page,
          contentStartY: start,
          contentEndY: end,
          fragmentCount: 0,
        ),
      );
    }

    var cursorY = 0.0;
    final fragmentCounts = List<int>.filled(pageCount, 0);

    for (final measured in measuredBlocks) {
      final blockStartY = cursorY;
      final blockEndY = cursorY + measured.heightPx;
      final firstPage = _pageForOffset(blockStartY, contentHeightPx, pageCount);
      final lastPage = _pageForOffset(math.max(blockStartY, blockEndY - 0.001), contentHeightPx, pageCount);

      for (var page = firstPage; page <= lastPage; page++) {
        final pageStart = (page - 1) * contentHeightPx;
        final pageEnd = page * contentHeightPx;
        final fragmentStart = math.max(blockStartY, pageStart);
        final fragmentEnd = math.min(blockEndY, pageEnd);
        final fractionStart = measured.heightPx <= 0
            ? 0.0
            : ((fragmentStart - blockStartY) / measured.heightPx).clamp(0.0, 1.0).toDouble();
        final fractionEnd = measured.heightPx <= 0
            ? 1.0
            : ((fragmentEnd - blockStartY) / measured.heightPx).clamp(0.0, 1.0).toDouble();
        final textLength = measured.block.text.length;
        final startOffset = (textLength * fractionStart).floor().clamp(0, textLength).toInt();
        final endOffset = (textLength * fractionEnd).ceil().clamp(startOffset, textLength).toInt();

        fragments.add(
          TextSystemPageFragment(
            blockId: measured.block.id,
            blockIndex: measured.blockIndex,
            blockType: measured.block.type,
            pageNumber: page,
            contentStartY: fragmentStart,
            contentEndY: fragmentEnd,
            blockStartOffset: startOffset,
            blockEndOffset: endOffset,
            continuesFromPreviousPage: page > firstPage,
            continuesOnNextPage: page < lastPage,
          ),
        );
        fragmentCounts[page - 1] += 1;
      }

      cursorY = blockEndY;
    }

    final pagesWithCounts = <TextSystemPageMapPage>[
      for (var i = 0; i < pages.length; i++)
        TextSystemPageMapPage(
          pageNumber: pages[i].pageNumber,
          contentStartY: pages[i].contentStartY,
          contentEndY: pages[i].contentEndY,
          fragmentCount: fragmentCounts[i],
        ),
    ];

    final breakMarkers = <TextSystemPageBreakMarker>[
      for (var page = 2; page <= pageCount; page++)
        TextSystemPageBreakMarker(
          beforePageNumber: page - 1,
          afterPageNumber: page,
          contentOffsetY: (page - 1) * contentHeightPx,
        ),
    ];

    return TextSystemPageMap(
      documentRevision: documentRevision,
      setup: pageSetup,
      pageWidthPx: safePageWidth,
      pageHeightPx: pageHeightPx,
      contentWidthPx: contentWidthPx,
      contentHeightPx: contentHeightPx,
      totalContentHeightPx: math.max(totalContentHeight, _emptyDocumentHeight(context, pageSetup)),
      pages: pagesWithCounts,
      fragments: fragments,
      breakMarkers: breakMarkers,
    );
  }

  static int _pageForOffset(double offsetY, double contentHeightPx, int pageCount) {
    return ((math.max(0.0, offsetY) / math.max(1.0, contentHeightPx)).floor() + 1)
        .clamp(1, math.max(1, pageCount))
        .toInt();
  }

  static double _minimumBlockHeight(TextStyle style) {
    final fontSize = style.fontSize ?? 16;
    final height = style.height ?? 1.3;
    return fontSize * height;
  }

  static double _emptyDocumentHeight(BuildContext context, TextSystemPageSetup pageSetup) {
    final style = Theme.of(context).textTheme.bodyLarge ?? TextStyle(fontSize: pageSetup.defaultFontSize);
    return _minimumBlockHeight(style) * 2;
  }
}

class _MeasuredBlock {
  const _MeasuredBlock({
    required this.block,
    required this.blockIndex,
    required this.visibleText,
    required this.heightPx,
    required this.textLineCount,
  });

  final TextSystemBlock block;
  final int blockIndex;
  final String visibleText;
  final double heightPx;
  final int textLineCount;
}
