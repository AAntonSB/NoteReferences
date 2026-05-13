import 'dart:math' as math;
import 'dart:ui' show Rect;

import 'package:flutter/widgets.dart';

import '../core/text_mark.dart';
import '../core/text_system_block.dart';
import '../core/text_system_document.dart';
import '../styles/text_system_document_style.dart';
import 'text_system_layout_tree.dart';
import 'text_system_page_furniture.dart';
import 'text_system_page_setup.dart';
import 'text_system_paged_block_layout.dart';

class TextSystemLayoutTreeBuilder {
  const TextSystemLayoutTreeBuilder._();

  static TextSystemDocumentLayoutTree build({
    required BuildContext context,
    required TextSystemDocument document,
    required TextSystemPageSetup pageSetup,
    required TextSystemPageFurniture pageFurniture,
    required double pageWidthPx,
    int documentRevision = 0,
  }) {
    return _LineMeasuredLayoutPass(
      context: context,
      document: document,
      pageSetup: pageSetup,
      pageFurniture: pageFurniture,
      pageWidthPx: pageWidthPx,
      documentRevision: documentRevision,
    ).build();
  }

  /// Compatibility adapter kept for callers/tests that still have the old
  /// block-estimated page layout. Phase 15B's main [build] path is now the
  /// TextPainter-measured pass above.
  static TextSystemDocumentLayoutTree fromPagedBlockLayout({
    required TextSystemDocument document,
    required TextSystemPageSetup pageSetup,
    required TextSystemPageFurniture pageFurniture,
    required TextSystemPagedBlockLayout pagedLayout,
    int documentRevision = 0,
  }) {
    final visualPageWidthPx = pagedLayout.pageWidthPx;
    final visualPageHeightPx = pagedLayout.pageHeightPx;
    final margins = pageSetup.margins.toPagePadding(
      visualPageWidthPx,
      pageSetup.pageWidthMm,
    );

    final pageRect = Rect.fromLTWH(0, 0, visualPageWidthPx, visualPageHeightPx);
    final contentRect = Rect.fromLTWH(
      margins.left,
      margins.top,
      pagedLayout.contentWidthPx,
      pagedLayout.contentHeightPx,
    );
    final headerRect = Rect.fromLTWH(
      margins.left,
      math.max(0.0, margins.top * 0.18),
      pagedLayout.contentWidthPx,
      math.max(18.0, margins.top * 0.48),
    );
    final footerHeight = math.max(18.0, margins.bottom * 0.48);
    final footerRect = Rect.fromLTWH(
      margins.left,
      visualPageHeightPx - margins.bottom + math.max(0.0, margins.bottom * 0.18),
      pagedLayout.contentWidthPx,
      footerHeight,
    );
    final footnoteRect = Rect.fromLTWH(
      margins.left,
      visualPageHeightPx - margins.bottom - 150.0,
      pagedLayout.contentWidthPx,
      140.0,
    );

    final pages = <TextSystemLayoutPage>[];

    for (var pageIndex = 0; pageIndex < pagedLayout.pages.length; pageIndex++) {
      final page = pagedLayout.pages[pageIndex];
      final logicalPageNumber = page.displayPageNumber;
      final blockFragments = <TextSystemLayoutBlockFragment>[];
      final lineFragments = <TextSystemLayoutLineFragment>[];

      for (var fragmentIndex = 0; fragmentIndex < page.fragments.length; fragmentIndex++) {
        final fragment = page.fragments[fragmentIndex];
        final fragmentRect = fragment.rect.shift(contentRect.topLeft);
        final styleId = textSystemStyleIdForBlockType(fragment.blockType, fragment.blockLevel);

        blockFragments.add(
          TextSystemLayoutBlockFragment(
            blockId: fragment.blockId,
            blockIndex: fragment.blockIndex,
            blockType: fragment.blockType,
            blockLevel: fragment.blockLevel,
            fragmentIndexOnPage: fragmentIndex,
            pageIndex: pageIndex,
            physicalPageNumber: page.pageNumber,
            logicalPageNumber: logicalPageNumber,
            textStartOffset: fragment.visualTextStartOffset,
            textEndOffset: fragment.visualTextEndOffset,
            rect: fragmentRect,
            visibleText: fragment.text,
            isSplitFragment: fragment.isSplitFragment,
            continuesFromPreviousPage: fragment.continuesFromPreviousPage,
            continuesOnNextPage: fragment.continuesOnNextPage,
            oversized: fragment.oversized,
            styleId: styleId,
          ),
        );

        lineFragments.add(
          TextSystemLayoutLineFragment(
            blockId: fragment.blockId,
            blockIndex: fragment.blockIndex,
            pageIndex: pageIndex,
            physicalPageNumber: page.pageNumber,
            logicalPageNumber: logicalPageNumber,
            lineIndexInBlock: 0,
            textStartOffset: fragment.visualTextStartOffset,
            textEndOffset: fragment.visualTextEndOffset,
            rect: fragmentRect,
            baseline: fragmentRect.top + math.min(fragmentRect.height, 14.0),
            text: fragment.text,
            styleId: styleId,
          ),
        );
      }

      final footnotes = <TextSystemLayoutFootnote>[
        for (var index = 0; index < page.footnotes.length; index++)
          TextSystemLayoutFootnote(
            footnoteId: page.footnotes[index].footnoteId,
            blockId: page.footnotes[index].blockId,
            anchorBlockId: page.footnotes[index].anchorBlockId,
            anchorOffset: page.footnotes[index].anchorOffset,
            number: page.footnotes[index].number,
            text: page.footnotes[index].text,
            rect: _footnoteRectForIndex(footnoteRect, index, page.footnotes.length),
          ),
      ];

      pages.add(
        TextSystemLayoutPage(
          pageIndex: pageIndex,
          physicalPageNumber: page.pageNumber,
          logicalPageNumber: logicalPageNumber,
          sectionIndex: page.sectionIndex,
          sectionId: page.sectionId,
          pageRect: pageRect,
          contentRect: contentRect,
          headerRect: headerRect,
          footerRect: footerRect,
          footnoteRect: footnoteRect,
          blockFragments: List<TextSystemLayoutBlockFragment>.unmodifiable(blockFragments),
          lineFragments: List<TextSystemLayoutLineFragment>.unmodifiable(lineFragments),
          footnotes: List<TextSystemLayoutFootnote>.unmodifiable(footnotes),
        ),
      );
    }

    return TextSystemDocumentLayoutTree(
      documentId: document.id,
      documentRevision: documentRevision,
      generatedAt: DateTime.now(),
      pageSetup: pageSetup,
      pageFurniture: pageFurniture,
      measurementMode: TextSystemLayoutMeasurementMode.blockEstimated,
      visualPageWidthPx: visualPageWidthPx,
      visualPageHeightPx: visualPageHeightPx,
      pages: List<TextSystemLayoutPage>.unmodifiable(pages),
    );
  }

  static Rect _footnoteRectForIndex(Rect footnoteArea, int index, int count) {
    final safeCount = math.max(1, count);
    final height = math.min(28.0, footnoteArea.height / safeCount);
    return Rect.fromLTWH(
      footnoteArea.left,
      footnoteArea.top + index * height,
      footnoteArea.width,
      height,
    );
  }
}

class _LineMeasuredLayoutPass {
  _LineMeasuredLayoutPass({
    required this.context,
    required this.document,
    required this.pageSetup,
    required this.pageFurniture,
    required this.pageWidthPx,
    required this.documentRevision,
  })  : visualPageHeightPx = pageWidthPx * pageSetup.heightToWidthRatio,
        textDirection = Directionality.maybeOf(context) ?? TextDirection.ltr,
        textScaler = MediaQuery.maybeTextScalerOf(context) ?? TextScaler.noScaling {
    styleSheet = TextSystemDocumentStyleSheet.academicDefault(pageSetup: pageSetup);
    margins = pageSetup.margins.toPagePadding(pageWidthPx, pageSetup.pageWidthMm);
    pageRect = Rect.fromLTWH(0, 0, pageWidthPx, visualPageHeightPx);
    contentRect = Rect.fromLTWH(
      margins.left,
      margins.top,
      math.max(48.0, pageWidthPx - margins.left - margins.right),
      math.max(48.0, visualPageHeightPx - margins.top - margins.bottom),
    );
    headerRect = Rect.fromLTWH(
      margins.left,
      math.max(0.0, margins.top * 0.18),
      contentRect.width,
      math.max(18.0, margins.top * 0.48),
    );
    final footerHeight = math.max(18.0, margins.bottom * 0.48);
    footerRect = Rect.fromLTWH(
      margins.left,
      visualPageHeightPx - margins.bottom + math.max(0.0, margins.bottom * 0.18),
      contentRect.width,
      footerHeight,
    );
    footnoteRect = Rect.fromLTWH(
      margins.left,
      visualPageHeightPx - margins.bottom - 150.0,
      contentRect.width,
      140.0,
    );

    footnoteBlocksById = _footnoteBlocksById(document);
    footnoteReferencesByBlockId = _footnoteReferencesByBlockId(document);
  }

  final BuildContext context;
  final TextSystemDocument document;
  final TextSystemPageSetup pageSetup;
  final TextSystemPageFurniture pageFurniture;
  final double pageWidthPx;
  final double visualPageHeightPx;
  final int documentRevision;
  final TextDirection textDirection;
  final TextScaler textScaler;

  late final EdgeInsets margins;
  late final Rect pageRect;
  late final Rect contentRect;
  late final Rect headerRect;
  late final Rect footerRect;
  late final Rect footnoteRect;
  late final TextSystemDocumentStyleSheet styleSheet;
  late final Map<String, TextSystemBlock> footnoteBlocksById;
  late final Map<String, List<_MeasuredFootnoteReference>> footnoteReferencesByBlockId;

  final List<_MutableMeasuredPage> pages = <_MutableMeasuredPage>[];
  _MutableMeasuredPage? currentPage;
  double cursorY = 0;
  int currentSectionIndex = 0;
  String? currentSectionId = 'section-0';
  int currentLogicalPageNumber = 1;

  TextSystemDocumentLayoutTree build() {
    _startPage();

    for (var blockIndex = 0; blockIndex < document.blocks.length; blockIndex++) {
      final block = document.blocks[blockIndex];

      if (_isFootnoteBlock(block)) continue;

      if (_isPageBreakBlock(block)) {
        _startPage();
        continue;
      }

      if (_isSectionBreakBlock(block)) {
        _layoutSectionBreak(block, blockIndex);
        continue;
      }

      _layoutBlock(block, blockIndex);
    }

    final immutablePages = <TextSystemLayoutPage>[
      for (final page in pages) page.toImmutable(footnoteRect),
    ];

    return TextSystemDocumentLayoutTree(
      documentId: document.id,
      documentRevision: documentRevision,
      generatedAt: DateTime.now(),
      pageSetup: pageSetup,
      pageFurniture: pageFurniture,
      measurementMode: TextSystemLayoutMeasurementMode.lineMeasured,
      visualPageWidthPx: pageWidthPx,
      visualPageHeightPx: visualPageHeightPx,
      pages: List<TextSystemLayoutPage>.unmodifiable(immutablePages),
    );
  }

  void _startPage({
    bool startsSection = false,
    String? sectionId,
    int? logicalPageStartAt,
  }) {
    if (startsSection) {
      currentSectionIndex += 1;
      currentSectionId = sectionId ?? 'section-$currentSectionIndex';
      currentLogicalPageNumber = logicalPageStartAt ?? 1;
    } else if (pages.isEmpty) {
      currentLogicalPageNumber = 1;
    } else {
      currentLogicalPageNumber += 1;
    }

    final page = _MutableMeasuredPage(
      pageIndex: pages.length,
      physicalPageNumber: pages.length + 1,
      logicalPageNumber: currentLogicalPageNumber,
      sectionIndex: currentSectionIndex,
      sectionId: currentSectionId,
      pageRect: pageRect,
      contentRect: contentRect,
      headerRect: headerRect,
      footerRect: footerRect,
      footnoteRect: footnoteRect,
    );

    pages.add(page);
    currentPage = page;
    cursorY = contentRect.top;
  }

  void _layoutSectionBreak(TextSystemBlock block, int blockIndex) {
    const sectionBreakHeight = 44.0;
    _ensureVerticalSpace(sectionBreakHeight, const <_MeasuredFootnoteReference>[]);

    final rect = Rect.fromLTWH(
      contentRect.left,
      cursorY,
      contentRect.width,
      sectionBreakHeight,
    );

    currentPage!.addMeasuredLine(
      block: block,
      blockIndex: blockIndex,
      blockType: block.type,
      blockLevel: block.level,
      textStartOffset: 0,
      textEndOffset: 0,
      lineIndexInBlock: 0,
      rect: rect,
      baseline: rect.top + 14.0,
      text: 'Section break',
      styleId: textSystemStyleIdForBlockType(block.type, block.level),
      footnotes: const <_MeasuredFootnoteReference>[],
    );

    cursorY += sectionBreakHeight;

    final restart = block.metadata['restartPageNumbering'] != false;
    final rawStartAt = block.metadata['pageNumberStartAt'];
    final startAt = rawStartAt is int ? rawStartAt.clamp(1, 9999).toInt() : 1;
    _startPage(
      startsSection: true,
      sectionId: block.metadata['sectionId'] as String?,
      logicalPageStartAt: restart ? startAt : currentLogicalPageNumber + 1,
    );
  }

  void _layoutBlock(TextSystemBlock block, int blockIndex) {
    final style = _blockStyle(block);
    final markerGutter = _markerGutterForBlock(block, style.fontSize);
    final textWidth = math.max(20.0, contentRect.width - markerGutter);
    final measuredLines = _measureBlockLines(block, style, textWidth);

    final spacingAfter = _spacingAfter(block, style.fontSize);
    final styleId = style.paragraphStyle.id;

    if (measuredLines.isEmpty) {
      final lineHeight = style.lineHeight;
      _ensureVerticalSpace(lineHeight + spacingAfter, const <_MeasuredFootnoteReference>[]);
      final rect = Rect.fromLTWH(
        contentRect.left + markerGutter,
        cursorY,
        textWidth,
        lineHeight,
      );
      currentPage!.addMeasuredLine(
        block: block,
        blockIndex: blockIndex,
        blockType: block.type,
        blockLevel: block.level,
        textStartOffset: 0,
        textEndOffset: 0,
        lineIndexInBlock: 0,
        rect: rect,
        baseline: rect.top + lineHeight * 0.78,
        text: '',
        styleId: styleId,
        footnotes: const <_MeasuredFootnoteReference>[],
      );
      cursorY += lineHeight + spacingAfter;
      return;
    }

    for (var lineIndex = 0; lineIndex < measuredLines.length; lineIndex++) {
      final line = measuredLines[lineIndex];
      final isLastLine = lineIndex == measuredLines.length - 1;
      final lineFootnotes = _footnotesForLine(block, line.startOffset, line.endOffset);
      final requiredHeight = line.height + (isLastLine ? spacingAfter : 0.0);

      _ensureVerticalSpace(requiredHeight, lineFootnotes);

      final rect = Rect.fromLTWH(
        contentRect.left + markerGutter,
        cursorY,
        textWidth,
        line.height,
      );

      currentPage!.addMeasuredLine(
        block: block,
        blockIndex: blockIndex,
        blockType: block.type,
        blockLevel: block.level,
        textStartOffset: line.startOffset,
        textEndOffset: line.endOffset,
        lineIndexInBlock: lineIndex,
        rect: rect,
        baseline: rect.top + line.baseline,
        text: _displayTextForRange(block, line.startOffset, line.endOffset),
        styleId: styleId,
        footnotes: lineFootnotes,
      );

      cursorY += line.height;
      if (isLastLine) cursorY += spacingAfter;
    }
  }

  List<_MeasuredTextLine> _measureBlockLines(
    TextSystemBlock block,
    _MeasuredBlockStyle style,
    double maxWidth,
  ) {
    if (block.text.isEmpty) {
      return <_MeasuredTextLine>[];
    }

    final painter = TextPainter(
      text: _textSpanForBlock(block, style.textStyle),
      textDirection: textDirection,
      textScaler: textScaler,
      maxLines: null,
    )..layout(maxWidth: maxWidth);

    final metrics = painter.computeLineMetrics();
    if (metrics.isEmpty) {
      return <_MeasuredTextLine>[];
    }

    final lines = <_MeasuredTextLine>[];
    var offset = 0;

    for (final metric in metrics) {
      if (offset >= block.text.length) break;

      final boundary = painter.getLineBoundary(TextPosition(offset: offset));
      var start = boundary.start.clamp(0, block.text.length).toInt();
      var end = boundary.end.clamp(0, block.text.length).toInt();

      if (end <= start) {
        start = offset.clamp(0, block.text.length).toInt();
        end = math.min(block.text.length, start + 1);
      }

      lines.add(
        _MeasuredTextLine(
          startOffset: start,
          endOffset: end,
          width: metric.width,
          height: math.max(metric.height, style.lineHeight),
          baseline: metric.baseline,
        ),
      );

      final nextOffset = end <= offset ? offset + 1 : end;
      offset = nextOffset.clamp(0, block.text.length).toInt();
    }

    if (lines.isEmpty) {
      return <_MeasuredTextLine>[
        _MeasuredTextLine(
          startOffset: 0,
          endOffset: block.text.length,
          width: painter.width,
          height: style.lineHeight,
          baseline: style.lineHeight * 0.78,
        ),
      ];
    }

    return lines;
  }

  InlineSpan _textSpanForBlock(TextSystemBlock block, TextStyle baseStyle) {
    if (block.marks.isEmpty) {
      return TextSpan(text: block.text, style: baseStyle);
    }

    final boundaries = <int>{0, block.text.length};
    for (final mark in block.marks) {
      boundaries
        ..add(mark.range.start.clamp(0, block.text.length).toInt())
        ..add(mark.range.end.clamp(0, block.text.length).toInt());
    }

    final ordered = boundaries.toList()..sort();
    final spans = <InlineSpan>[];

    for (var i = 0; i < ordered.length - 1; i++) {
      final start = ordered[i];
      final end = ordered[i + 1];
      if (start >= end) continue;

      final coveringMarks = block.marks
          .where((mark) => mark.range.start <= start && mark.range.end >= end)
          .toList(growable: false);
      final footnoteMark = _firstFootnoteReferenceMark(coveringMarks);

      spans.add(
        TextSpan(
          text: footnoteMark == null
              ? block.text.substring(start, end)
              : _superscriptNumber(int.tryParse(footnoteMark.attributes['number'] ?? '') ?? 0),
          style: _styleWithMarks(baseStyle, coveringMarks),
        ),
      );
    }

    return TextSpan(style: baseStyle, children: spans);
  }

  TextStyle _styleWithMarks(TextStyle baseStyle, List<TextMark> marks) {
    var style = baseStyle;
    var decorations = <TextDecoration>[];

    for (final mark in marks) {
      switch (mark.kind) {
        case TextMarkKind.bold:
          style = style.merge(const TextStyle(fontWeight: FontWeight.w700));
          break;
        case TextMarkKind.italic:
          style = style.merge(const TextStyle(fontStyle: FontStyle.italic));
          break;
        case TextMarkKind.underline:
          decorations.add(TextDecoration.underline);
          break;
        case TextMarkKind.strikethrough:
          decorations.add(TextDecoration.lineThrough);
          break;
        case TextMarkKind.highlight:
          style = style.copyWith(backgroundColor: const Color(0x33FFD54F));
          break;
        case TextMarkKind.code:
          style = style.copyWith(
            fontFamily: styleSheet.inlineCodeFontFamily,
            fontSize: (style.fontSize ?? pageSetup.defaultFontSize) * 0.94,
          );
          break;
        case TextMarkKind.link:
          if (_isFootnoteReferenceMark(mark)) {
            style = style.copyWith(
              fontSize: (style.fontSize ?? pageSetup.defaultFontSize) * styleSheet.footnoteReferenceScale,
              fontWeight: FontWeight.w700,
              height: 0.95,
            );
          } else {
            decorations.add(TextDecoration.underline);
            style = style.copyWith(color: const Color(0xFF2B6CB0));
          }
          break;
      }
    }

    if (decorations.isNotEmpty) {
      style = style.copyWith(decoration: TextDecoration.combine(decorations));
    }

    return style;
  }

  _MeasuredBlockStyle _blockStyle(TextSystemBlock block) {
    final paragraphStyle = styleSheet.styleForBlock(block);
    final textStyle = paragraphStyle.toTextStyle();
    final fontSize = paragraphStyle.textStyle.fontSize;

    return _MeasuredBlockStyle(
      textStyle: textStyle,
      fontSize: fontSize,
      lineHeight: fontSize * paragraphStyle.textStyle.lineHeight,
      paragraphStyle: paragraphStyle,
    );
  }

  double _markerGutterForBlock(TextSystemBlock block, double fontSize) {
    return styleSheet.styleForBlock(block).markerGutter;
  }

  double _spacingAfter(TextSystemBlock block, double fontSize) {
    return styleSheet.styleForBlock(block).spacingAfter;
  }

  void _ensureVerticalSpace(
    double requiredHeight,
    List<_MeasuredFootnoteReference> incomingFootnotes,
  ) {
    final page = currentPage!;
    final futureFootnoteCount = page.uniqueFootnoteCountIncluding(incomingFootnotes);
    final reserve = futureFootnoteCount == 0 ? 0.0 : math.min(132.0, 24.0 + futureFootnoteCount * 28.0);
    final availableBottom = contentRect.bottom - reserve;

    if (cursorY + requiredHeight <= availableBottom) return;
    _startPage();
  }

  List<_MeasuredFootnoteReference> _footnotesForLine(
    TextSystemBlock block,
    int start,
    int end,
  ) {
    final references = footnoteReferencesByBlockId[block.id];
    if (references == null || references.isEmpty) return const <_MeasuredFootnoteReference>[];

    final result = <_MeasuredFootnoteReference>[];
    for (final reference in references) {
      if (reference.anchorOffset < start || reference.anchorOffset >= end) continue;
      final footnoteBlock = footnoteBlocksById[reference.footnoteId];
      if (footnoteBlock == null) continue;
      reference.footnoteBlock = footnoteBlock;
      result.add(reference);
    }
    return result;
  }

  String _displayTextForRange(TextSystemBlock block, int start, int end) {
    if (start >= end || block.text.isEmpty) return '';
    final safeStart = start.clamp(0, block.text.length).toInt();
    final safeEnd = end.clamp(safeStart, block.text.length).toInt();
    var result = block.text.substring(safeStart, safeEnd).replaceAll('\n', '');

    final references = footnoteReferencesByBlockId[block.id] ?? const <_MeasuredFootnoteReference>[];
    for (final reference in references.reversed) {
      if (reference.anchorOffset < safeStart || reference.anchorOffset >= safeEnd) continue;
      final localOffset = reference.anchorOffset - safeStart;
      if (localOffset < 0 || localOffset >= result.length) continue;
      result = result.replaceRange(
        localOffset,
        localOffset + 1,
        _superscriptNumber(reference.number),
      );
    }

    return result;
  }

  static Map<String, TextSystemBlock> _footnoteBlocksById(TextSystemDocument document) {
    final result = <String, TextSystemBlock>{};
    for (final block in document.blocks) {
      if (!_isFootnoteBlock(block)) continue;
      final footnoteId = block.metadata['footnoteId'] as String?;
      if (footnoteId == null) continue;
      result[footnoteId] = block;
    }
    return result;
  }

  static Map<String, List<_MeasuredFootnoteReference>> _footnoteReferencesByBlockId(
    TextSystemDocument document,
  ) {
    final result = <String, List<_MeasuredFootnoteReference>>{};
    var nextNumber = 1;

    for (var blockIndex = 0; blockIndex < document.blocks.length; blockIndex++) {
      final block = document.blocks[blockIndex];
      if (_isFootnoteBlock(block)) continue;

      for (final mark in block.marks) {
        if (!_isFootnoteReferenceMark(mark)) continue;
        final footnoteId = mark.attributes['footnoteId'];
        if (footnoteId == null) continue;

        final reference = _MeasuredFootnoteReference(
          footnoteId: footnoteId,
          anchorBlockId: block.id,
          anchorBlockIndex: blockIndex,
          anchorOffset: mark.range.start,
          number: nextNumber,
        );
        result.putIfAbsent(block.id, () => <_MeasuredFootnoteReference>[]).add(reference);
        nextNumber += 1;
      }
    }

    for (final references in result.values) {
      references.sort((a, b) => a.anchorOffset.compareTo(b.anchorOffset));
    }

    return result;
  }

  static TextMark? _firstFootnoteReferenceMark(List<TextMark> marks) {
    for (final mark in marks) {
      if (_isFootnoteReferenceMark(mark)) return mark;
    }
    return null;
  }

  static bool _isFootnoteBlock(TextSystemBlock block) {
    return block.type == TextSystemBlockType.custom && block.metadata['kind'] == 'footnote';
  }

  static bool _isFootnoteReferenceMark(TextMark mark) {
    return mark.kind == TextMarkKind.link && mark.attributes['role'] == 'footnoteReference';
  }

  static bool _isPageBreakBlock(TextSystemBlock block) {
    return block.type == TextSystemBlockType.divider && block.metadata['kind'] == 'pageBreak';
  }

  static bool _isSectionBreakBlock(TextSystemBlock block) {
    return block.type == TextSystemBlockType.divider && block.metadata['kind'] == 'sectionBreak';
  }

  static String _superscriptNumber(int value) {
    const superscripts = <String, String>{
      '0': '⁰',
      '1': '¹',
      '2': '²',
      '3': '³',
      '4': '⁴',
      '5': '⁵',
      '6': '⁶',
      '7': '⁷',
      '8': '⁸',
      '9': '⁹',
    };

    final safeValue = value <= 0 ? 0 : value;
    return safeValue
        .toString()
        .split('')
        .map((digit) => superscripts[digit] ?? digit)
        .join();
  }
}

class _MutableMeasuredPage {
  _MutableMeasuredPage({
    required this.pageIndex,
    required this.physicalPageNumber,
    required this.logicalPageNumber,
    required this.sectionIndex,
    required this.sectionId,
    required this.pageRect,
    required this.contentRect,
    required this.headerRect,
    required this.footerRect,
    required this.footnoteRect,
  });

  final int pageIndex;
  final int physicalPageNumber;
  final int logicalPageNumber;
  final int sectionIndex;
  final String? sectionId;
  final Rect pageRect;
  final Rect contentRect;
  final Rect headerRect;
  final Rect footerRect;
  final Rect footnoteRect;

  final List<_MutableMeasuredBlockFragment> blockFragments = <_MutableMeasuredBlockFragment>[];
  final List<TextSystemLayoutLineFragment> lineFragments = <TextSystemLayoutLineFragment>[];
  final List<_MeasuredFootnoteReference> footnoteReferences = <_MeasuredFootnoteReference>[];

  void addMeasuredLine({
    required TextSystemBlock block,
    required int blockIndex,
    required TextSystemBlockType blockType,
    required int? blockLevel,
    required int textStartOffset,
    required int textEndOffset,
    required int lineIndexInBlock,
    required Rect rect,
    required double baseline,
    required String text,
    required String styleId,
    required List<_MeasuredFootnoteReference> footnotes,
  }) {
    final line = TextSystemLayoutLineFragment(
      blockId: block.id,
      blockIndex: blockIndex,
      pageIndex: pageIndex,
      physicalPageNumber: physicalPageNumber,
      logicalPageNumber: logicalPageNumber,
      lineIndexInBlock: lineIndexInBlock,
      textStartOffset: textStartOffset,
      textEndOffset: textEndOffset,
      rect: rect,
      baseline: baseline,
      text: text,
      styleId: styleId,
    );
    lineFragments.add(line);

    final previous = blockFragments.isNotEmpty ? blockFragments.last : null;
    if (previous != null && previous.blockId == block.id) {
      previous.includeLine(
        rect: rect,
        textEndOffset: textEndOffset,
        visibleText: text,
      );
    } else {
      blockFragments.add(
        _MutableMeasuredBlockFragment(
          blockId: block.id,
          blockIndex: blockIndex,
          blockType: blockType,
          blockLevel: blockLevel,
          fragmentIndexOnPage: blockFragments.length,
          pageIndex: pageIndex,
          physicalPageNumber: physicalPageNumber,
          logicalPageNumber: logicalPageNumber,
          textStartOffset: textStartOffset,
          textEndOffset: textEndOffset,
          rect: rect,
          visibleText: text,
          styleId: styleId,
        ),
      );
    }

    for (final footnote in footnotes) {
      if (footnoteReferences.any((candidate) => candidate.footnoteId == footnote.footnoteId)) {
        continue;
      }
      footnoteReferences.add(footnote);
      footnoteReferences.sort((a, b) => a.number.compareTo(b.number));
    }
  }

  int uniqueFootnoteCountIncluding(List<_MeasuredFootnoteReference> incoming) {
    final ids = <String>{
      for (final footnote in footnoteReferences) footnote.footnoteId,
      for (final footnote in incoming) footnote.footnoteId,
    };
    return ids.length;
  }

  TextSystemLayoutPage toImmutable(Rect footnoteArea) {
    final immutableFootnotes = <TextSystemLayoutFootnote>[
      for (var index = 0; index < footnoteReferences.length; index++)
        TextSystemLayoutFootnote(
          footnoteId: footnoteReferences[index].footnoteId,
          blockId: footnoteReferences[index].footnoteBlock?.id ?? '',
          anchorBlockId: footnoteReferences[index].anchorBlockId,
          anchorOffset: footnoteReferences[index].anchorOffset,
          number: footnoteReferences[index].number,
          text: footnoteReferences[index].footnoteBlock?.text ?? '',
          rect: _footnoteRectForIndex(footnoteArea, index, footnoteReferences.length),
        ),
    ];

    return TextSystemLayoutPage(
      pageIndex: pageIndex,
      physicalPageNumber: physicalPageNumber,
      logicalPageNumber: logicalPageNumber,
      sectionIndex: sectionIndex,
      sectionId: sectionId,
      pageRect: pageRect,
      contentRect: contentRect,
      headerRect: headerRect,
      footerRect: footerRect,
      footnoteRect: footnoteRect,
      blockFragments: List<TextSystemLayoutBlockFragment>.unmodifiable(
        blockFragments.map((fragment) => fragment.toImmutable()).toList(),
      ),
      lineFragments: List<TextSystemLayoutLineFragment>.unmodifiable(lineFragments),
      footnotes: List<TextSystemLayoutFootnote>.unmodifiable(immutableFootnotes),
    );
  }

  static Rect _footnoteRectForIndex(Rect footnoteArea, int index, int count) {
    final safeCount = math.max(1, count);
    final height = math.min(28.0, footnoteArea.height / safeCount);
    return Rect.fromLTWH(
      footnoteArea.left,
      footnoteArea.top + index * height,
      footnoteArea.width,
      height,
    );
  }
}

class _MutableMeasuredBlockFragment {
  _MutableMeasuredBlockFragment({
    required this.blockId,
    required this.blockIndex,
    required this.blockType,
    required this.blockLevel,
    required this.fragmentIndexOnPage,
    required this.pageIndex,
    required this.physicalPageNumber,
    required this.logicalPageNumber,
    required this.textStartOffset,
    required this.textEndOffset,
    required this.rect,
    required this.visibleText,
    required this.styleId,
  });

  final String blockId;
  final int blockIndex;
  final TextSystemBlockType blockType;
  final int? blockLevel;
  final int fragmentIndexOnPage;
  final int pageIndex;
  final int physicalPageNumber;
  final int logicalPageNumber;
  final int textStartOffset;
  int textEndOffset;
  Rect rect;
  String visibleText;
  final String styleId;

  void includeLine({
    required Rect rect,
    required int textEndOffset,
    required String visibleText,
  }) {
    this.rect = this.rect.expandToInclude(rect);
    this.textEndOffset = math.max(this.textEndOffset, textEndOffset);
    if (visibleText.isNotEmpty) {
      this.visibleText = this.visibleText.isEmpty ? visibleText : '${this.visibleText}\n$visibleText';
    }
  }

  TextSystemLayoutBlockFragment toImmutable() {
    return TextSystemLayoutBlockFragment(
      blockId: blockId,
      blockIndex: blockIndex,
      blockType: blockType,
      blockLevel: blockLevel,
      fragmentIndexOnPage: fragmentIndexOnPage,
      pageIndex: pageIndex,
      physicalPageNumber: physicalPageNumber,
      logicalPageNumber: logicalPageNumber,
      textStartOffset: textStartOffset,
      textEndOffset: textEndOffset,
      rect: rect,
      visibleText: visibleText,
      isSplitFragment: false,
      continuesFromPreviousPage: false,
      continuesOnNextPage: false,
      oversized: rect.height > 0,
      styleId: styleId,
    );
  }
}

class _MeasuredTextLine {
  const _MeasuredTextLine({
    required this.startOffset,
    required this.endOffset,
    required this.width,
    required this.height,
    required this.baseline,
  });

  final int startOffset;
  final int endOffset;
  final double width;
  final double height;
  final double baseline;
}

class _MeasuredBlockStyle {
  const _MeasuredBlockStyle({
    required this.textStyle,
    required this.fontSize,
    required this.lineHeight,
    required this.paragraphStyle,
  });

  final TextStyle textStyle;
  final double fontSize;
  final double lineHeight;
  final TextSystemParagraphStyleSpec paragraphStyle;
}

class _MeasuredFootnoteReference {
  _MeasuredFootnoteReference({
    required this.footnoteId,
    required this.anchorBlockId,
    required this.anchorBlockIndex,
    required this.anchorOffset,
    required this.number,
    this.footnoteBlock,
  });

  final String footnoteId;
  final String anchorBlockId;
  final int anchorBlockIndex;
  final int anchorOffset;
  final int number;
  TextSystemBlock? footnoteBlock;
}
