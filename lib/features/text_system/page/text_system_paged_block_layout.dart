import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/text_mark.dart';
import '../core/text_system_block.dart';
import '../core/text_system_document.dart';
import 'text_system_layout_style_resolver.dart';
import 'text_system_page_setup.dart';

/// First real-page layout model for the experimental paged writer surface.
///
/// Unlike the hybrid overlay, this model places document blocks inside physical
/// page content boxes. It is still read-only layout metadata: the document owns
/// text, while pages own fragments.
@immutable
class TextSystemPagedBlockLayout {
  const TextSystemPagedBlockLayout({
    required this.pageWidthPx,
    required this.pageHeightPx,
    required this.contentWidthPx,
    required this.contentHeightPx,
    required this.pages,
    required this.oversizedFragmentCount,
  });

  final double pageWidthPx;
  final double pageHeightPx;
  final double contentWidthPx;
  final double contentHeightPx;
  final List<TextSystemPagedBlockPage> pages;
  final int oversizedFragmentCount;

  int get pageCount => pages.isEmpty ? 1 : pages.length;

  String get label => '$pageCount real page${pageCount == 1 ? '' : 's'}';

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'pageWidthPx': pageWidthPx,
      'pageHeightPx': pageHeightPx,
      'contentWidthPx': contentWidthPx,
      'contentHeightPx': contentHeightPx,
      'pageCount': pageCount,
      'oversizedFragmentCount': oversizedFragmentCount,
      'pages': [for (final page in pages) page.toJson()],
    };
  }
}

@immutable
class TextSystemPagedBlockPage {
  const TextSystemPagedBlockPage({
    required this.pageNumber,
    required this.fragments,
    this.footnotes = const <TextSystemPagedFootnote>[],
    this.logicalPageNumber,
    this.sectionIndex = 0,
    this.sectionId,
  });

  final int pageNumber;
  final int? logicalPageNumber;
  final int sectionIndex;
  final String? sectionId;
  final List<TextSystemPagedBlockFragment> fragments;
  final List<TextSystemPagedFootnote> footnotes;

  int get displayPageNumber => logicalPageNumber ?? pageNumber;
  bool get isEmpty => fragments.isEmpty;
  bool get hasFootnotes => footnotes.isNotEmpty;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'pageNumber': pageNumber,
      'logicalPageNumber': logicalPageNumber,
      'sectionIndex': sectionIndex,
      'sectionId': sectionId,
      'fragments': [for (final fragment in fragments) fragment.toJson()],
      'footnotes': [for (final footnote in footnotes) footnote.toJson()],
    };
  }
}

@immutable
class TextSystemPagedFootnote {
  const TextSystemPagedFootnote({
    required this.footnoteId,
    required this.blockId,
    required this.anchorBlockId,
    required this.anchorOffset,
    required this.number,
    required this.text,
  });

  final String footnoteId;
  final String blockId;
  final String anchorBlockId;
  final int anchorOffset;
  final int number;
  final String text;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'footnoteId': footnoteId,
      'blockId': blockId,
      'anchorBlockId': anchorBlockId,
      'anchorOffset': anchorOffset,
      'number': number,
      'text': text,
    };
  }
}

@immutable
class TextSystemPagedBlockFragment {
  const TextSystemPagedBlockFragment({
    required this.blockId,
    required this.blockIndex,
    required this.blockType,
    required this.blockLevel,
    required this.text,
    required this.visualTextStartOffset,
    required this.visualTextEndOffset,
    required this.rect,
    this.continuesFromPreviousPage = false,
    this.continuesOnNextPage = false,
    this.oversized = false,
  });

  final String blockId;
  final int blockIndex;
  final TextSystemBlockType blockType;
  final int? blockLevel;
  final String text;
  final int visualTextStartOffset;
  final int visualTextEndOffset;
  final Rect rect;
  final bool continuesFromPreviousPage;
  final bool continuesOnNextPage;
  final bool oversized;

  bool get isSplitFragment => continuesFromPreviousPage || continuesOnNextPage;
  bool get isWholeBlockFragment => !isSplitFragment && !oversized;
  int get visualTextLength => math.max(0, visualTextEndOffset - visualTextStartOffset);

  bool containsTextOffset(int offset) {
    if (visualTextStartOffset == visualTextEndOffset) {
      return offset == visualTextStartOffset;
    }
    return offset >= visualTextStartOffset && offset <= visualTextEndOffset;
  }

  double get heightPx => rect.height;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'blockId': blockId,
      'blockIndex': blockIndex,
      'blockType': blockType.name,
      'blockLevel': blockLevel,
      'textLength': text.length,
      'visualTextStartOffset': visualTextStartOffset,
      'visualTextEndOffset': visualTextEndOffset,
      'rect': <String, Object?>{
        'left': rect.left,
        'top': rect.top,
        'width': rect.width,
        'height': rect.height,
      },
      'continuesFromPreviousPage': continuesFromPreviousPage,
      'continuesOnNextPage': continuesOnNextPage,
      'oversized': oversized,
    };
  }
}

class TextSystemPagedBlockLayoutEngine {
  const TextSystemPagedBlockLayoutEngine._();

  static TextSystemPagedBlockLayout layout({
    required BuildContext context,
    required TextSystemDocument document,
    required TextSystemPageSetup pageSetup,
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

    final direction = Directionality.of(context);
    final textScaler = MediaQuery.textScalerOf(context);

    var currentSectionIndex = 0;
    var currentSectionId = 'section-0';
    var currentLogicalPageNumber = 1;

    final pages = <_MutablePagedBlockPage>[
      _MutablePagedBlockPage(
        pageNumber: 1,
        logicalPageNumber: currentLogicalPageNumber,
        sectionIndex: currentSectionIndex,
        sectionId: currentSectionId,
      ),
    ];
    var cursorY = 0.0;
    var oversizedCount = 0;

    _MutablePagedBlockPage getCurrentPage() => pages.last;

    void startNewPage({
      bool startsSection = false,
      String? sectionId,
      int? logicalPageStartAt,
    }) {
      if (startsSection) {
        currentSectionIndex += 1;
        currentSectionId = sectionId ?? 'section-$currentSectionIndex';
        currentLogicalPageNumber = logicalPageStartAt ?? 1;
      } else {
        currentLogicalPageNumber += 1;
      }

      pages.add(
        _MutablePagedBlockPage(
          pageNumber: pages.length + 1,
          logicalPageNumber: currentLogicalPageNumber,
          sectionIndex: currentSectionIndex,
          sectionId: currentSectionId,
        ),
      );
      cursorY = 0;
    }

    final orderedFootnoteReferences = _orderedFootnoteReferences(document);
    final footnoteBlocksById = _footnoteBlocksById(document);

    for (var blockIndex = 0; blockIndex < document.blocks.length; blockIndex++) {
      final block = document.blocks[blockIndex];

      if (_isFootnoteBlock(block)) {
        continue;
      }

      if (_isPageBreakBlock(block)) {
        const pageBreakHeight = 38.0;
        if (contentHeightPx - cursorY < pageBreakHeight && !getCurrentPage().isEmpty) {
          startNewPage();
        }

        getCurrentPage().fragments.add(
              TextSystemPagedBlockFragment(
                blockId: block.id,
                blockIndex: blockIndex,
                blockType: block.type,
                blockLevel: block.level,
                text: 'Page break',
                visualTextStartOffset: 0,
                visualTextEndOffset: 0,
                rect: Rect.fromLTWH(0, cursorY, contentWidthPx, pageBreakHeight),
              ),
            );
        cursorY += pageBreakHeight;
        startNewPage();
        continue;
      }

      if (_isSectionBreakBlock(block)) {
        const sectionBreakHeight = 44.0;
        if (contentHeightPx - cursorY < sectionBreakHeight && !getCurrentPage().isEmpty) {
          startNewPage();
        }

        getCurrentPage().fragments.add(
              TextSystemPagedBlockFragment(
                blockId: block.id,
                blockIndex: blockIndex,
                blockType: block.type,
                blockLevel: block.level,
                text: 'Section break',
                visualTextStartOffset: 0,
                visualTextEndOffset: 0,
                rect: Rect.fromLTWH(0, cursorY, contentWidthPx, sectionBreakHeight),
              ),
            );
        cursorY += sectionBreakHeight;

        final restart = block.metadata['restartPageNumbering'] != false;
        final rawStartAt = block.metadata['pageNumberStartAt'];
        final startAt = rawStartAt is int ? rawStartAt.clamp(1, 9999).toInt() : 1;
        final sectionId = block.metadata['sectionId'] as String?;
        startNewPage(
          startsSection: true,
          sectionId: sectionId,
          logicalPageStartAt: restart ? startAt : currentLogicalPageNumber + 1,
        );
        continue;
      }

      final style = TextSystemLayoutStyleResolver.blockStyle(
        context: context,
        block: block,
        pageSetup: pageSetup,
      );
      final fullText = _layoutTextForBlock(block, blockIndex);
      final textMaxWidth = _textMaxWidthForBlock(block, contentWidthPx);
      final spacingAfter = TextSystemLayoutStyleResolver.afterBlockSpacing(
        block: block,
        style: style,
        pageSetup: pageSetup,
      );
      final minHeight = _minimumBlockHeight(style);

      var remainingText = fullText.isEmpty ? ' ' : fullText;
      var sourceOffset = 0;
      var continuation = false;

      // Empty editable blocks still need one caret target. The fragment has a
      // zero-length source range but a measured visual height.
      if (_isPlainTextEditableBlock(block) && block.text.isEmpty) {
        final requiredHeight = minHeight + spacingAfter;
        if (contentHeightPx - cursorY < requiredHeight && !getCurrentPage().isEmpty) {
          startNewPage();
        }
        getCurrentPage().fragments.add(
              TextSystemPagedBlockFragment(
                blockId: block.id,
                blockIndex: blockIndex,
                blockType: block.type,
                blockLevel: block.level,
                text: '',
                visualTextStartOffset: 0,
                visualTextEndOffset: 0,
                rect: Rect.fromLTWH(0, cursorY, contentWidthPx, requiredHeight),
              ),
            );
        cursorY += requiredHeight;
        continue;
      }

      while (remainingText.isNotEmpty) {
        var availableHeight = contentHeightPx - cursorY;
        if (availableHeight < minHeight * 0.8 && !getCurrentPage().isEmpty) {
          startNewPage();
          availableHeight = contentHeightPx;
        }

        final remainingHeight = _measureTextHeight(
          text: remainingText,
          style: style,
          textDirection: direction,
          textScaler: textScaler,
          maxWidth: textMaxWidth,
          minimumHeight: minHeight,
        );
        final requiredHeight = remainingHeight + spacingAfter;

        if (requiredHeight <= availableHeight || getCurrentPage().isEmpty && requiredHeight <= contentHeightPx) {
          final fragmentHeight = math.min(requiredHeight, contentHeightPx - cursorY);
          getCurrentPage().fragments.add(
                TextSystemPagedBlockFragment(
                  blockId: block.id,
                  blockIndex: blockIndex,
                  blockType: block.type,
                  blockLevel: block.level,
                  text: remainingText,
                  visualTextStartOffset: sourceOffset,
                  visualTextEndOffset: sourceOffset + remainingText.length,
                  rect: Rect.fromLTWH(0, cursorY, contentWidthPx, fragmentHeight),
                  continuesFromPreviousPage: continuation,
                ),
              );
          cursorY += requiredHeight;
          break;
        }

        if (requiredHeight <= contentHeightPx && !getCurrentPage().isEmpty) {
          // Prefer true page flow for long editable prose blocks. Earlier
          // versions kept any block that could fit on a fresh page together,
          // which made a paragraph jump wholesale to the next page as soon as
          // it crossed the remaining page boundary. For real pages, ordinary
          // prose should be allowed to fragment across the current page and
          // the next page. Non-prose blocks still keep together for now.
          final canUseRemainingPage = _canSplitAcrossPages(block) &&
              availableHeight >= minHeight * 1.35;
          if (!canUseRemainingPage) {
            startNewPage();
            continue;
          }
        }

        final usableHeight = math.max(minHeight, availableHeight - spacingAfter * 0.25);
        final splitOffset = _splitOffsetForHeight(
          text: remainingText,
          style: style,
          textDirection: direction,
          textScaler: textScaler,
          maxWidth: textMaxWidth,
          maxHeight: usableHeight,
        );

        if (splitOffset <= 0 || splitOffset >= remainingText.length) {
          if (!getCurrentPage().isEmpty) {
            startNewPage();
            continue;
          }

          oversizedCount += 1;
          getCurrentPage().fragments.add(
                TextSystemPagedBlockFragment(
                  blockId: block.id,
                  blockIndex: blockIndex,
                  blockType: block.type,
                  blockLevel: block.level,
                  text: remainingText,
                  visualTextStartOffset: sourceOffset,
                  visualTextEndOffset: sourceOffset + remainingText.length,
                  rect: Rect.fromLTWH(0, cursorY, contentWidthPx, contentHeightPx - cursorY),
                  continuesFromPreviousPage: continuation,
                  oversized: true,
                ),
              );
          cursorY = contentHeightPx;
          break;
        }

        final rawFragmentText = remainingText.substring(0, splitOffset);
        final fragmentText = rawFragmentText.trimRight();
        if (fragmentText.isEmpty) {
          final trimmed = remainingText.trimLeft();
          final skippedLeadingWhitespace = remainingText.length - trimmed.length;
          if (skippedLeadingWhitespace > 0) {
            sourceOffset += skippedLeadingWhitespace;
            remainingText = trimmed;
            continue;
          }
          startNewPage();
          continue;
        }

        final fragmentHeight = _measureTextHeight(
          text: fragmentText,
          style: style,
          textDirection: direction,
          textScaler: textScaler,
          maxWidth: textMaxWidth,
          minimumHeight: minHeight,
        );

        getCurrentPage().fragments.add(
              TextSystemPagedBlockFragment(
                blockId: block.id,
                blockIndex: blockIndex,
                blockType: block.type,
                blockLevel: block.level,
                text: fragmentText,
                visualTextStartOffset: sourceOffset,
                visualTextEndOffset: sourceOffset + fragmentText.length,
                rect: Rect.fromLTWH(0, cursorY, contentWidthPx, math.min(fragmentHeight, availableHeight)),
                continuesFromPreviousPage: continuation,
                continuesOnNextPage: true,
              ),
            );

        final rawNextOffset = sourceOffset + splitOffset;
        final nextText = fullText.substring(rawNextOffset);
        final skippedLeadingWhitespace = nextText.length - nextText.trimLeft().length;
        sourceOffset = rawNextOffset + skippedLeadingWhitespace;
        remainingText = fullText.substring(sourceOffset);
        continuation = true;
        startNewPage();
      }
    }

    if (pages.isEmpty || (pages.length == 1 && pages.first.isEmpty)) {
      pages.clear();
      pages.add(_MutablePagedBlockPage(pageNumber: 1));
    }

    return TextSystemPagedBlockLayout(
      pageWidthPx: safePageWidth,
      pageHeightPx: pageHeightPx,
      contentWidthPx: contentWidthPx,
      contentHeightPx: contentHeightPx,
      oversizedFragmentCount: oversizedCount,
      pages: [
        for (final page in pages)
          TextSystemPagedBlockPage(
            pageNumber: page.pageNumber,
            logicalPageNumber: page.logicalPageNumber,
            sectionIndex: page.sectionIndex,
            sectionId: page.sectionId,
            fragments: List<TextSystemPagedBlockFragment>.unmodifiable(page.fragments),
            footnotes: List<TextSystemPagedFootnote>.unmodifiable(
              _footnotesForPage(
                page: page,
                orderedReferences: orderedFootnoteReferences,
                footnoteBlocksById: footnoteBlocksById,
              ),
            ),
          ),
      ],
    );
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

  static List<_PagedFootnoteReference> _orderedFootnoteReferences(TextSystemDocument document) {
    final result = <_PagedFootnoteReference>[];

    for (var blockIndex = 0; blockIndex < document.blocks.length; blockIndex++) {
      final block = document.blocks[blockIndex];
      if (_isFootnoteBlock(block)) continue;
      for (final mark in block.marks) {
        if (!_isFootnoteReferenceMark(mark)) continue;
        final footnoteId = mark.attributes['footnoteId'];
        if (footnoteId == null) continue;
        result.add(
          _PagedFootnoteReference(
            footnoteId: footnoteId,
            anchorBlockId: block.id,
            anchorBlockIndex: blockIndex,
            anchorOffset: mark.range.start,
            number: 0,
          ),
        );
      }
    }

    result.sort((a, b) {
      final blockCompare = a.anchorBlockIndex.compareTo(b.anchorBlockIndex);
      if (blockCompare != 0) return blockCompare;
      return a.anchorOffset.compareTo(b.anchorOffset);
    });

    return <_PagedFootnoteReference>[
      for (var i = 0; i < result.length; i++) result[i].copyWith(number: i + 1),
    ];
  }

  static List<TextSystemPagedFootnote> _footnotesForPage({
    required _MutablePagedBlockPage page,
    required List<_PagedFootnoteReference> orderedReferences,
    required Map<String, TextSystemBlock> footnoteBlocksById,
  }) {
    if (orderedReferences.isEmpty || page.fragments.isEmpty) return const <TextSystemPagedFootnote>[];

    final seenFootnoteIds = <String>{};
    final result = <TextSystemPagedFootnote>[];

    for (final fragment in page.fragments) {
      for (final reference in orderedReferences) {
        if (reference.anchorBlockId != fragment.blockId) continue;
        if (reference.anchorOffset < fragment.visualTextStartOffset ||
            reference.anchorOffset > fragment.visualTextEndOffset) {
          continue;
        }
        if (!seenFootnoteIds.add(reference.footnoteId)) continue;

        final footnoteBlock = footnoteBlocksById[reference.footnoteId];
        if (footnoteBlock == null) continue;

        result.add(
          TextSystemPagedFootnote(
            footnoteId: reference.footnoteId,
            blockId: footnoteBlock.id,
            anchorBlockId: reference.anchorBlockId,
            anchorOffset: reference.anchorOffset,
            number: reference.number,
            text: footnoteBlock.text,
          ),
        );
      }
    }

    result.sort((a, b) => a.number.compareTo(b.number));
    return result;
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

  static bool _isPlainTextEditableBlock(TextSystemBlock block) {
    return switch (block.type) {
      TextSystemBlockType.paragraph ||
      TextSystemBlockType.heading ||
      TextSystemBlockType.listItem ||
      TextSystemBlockType.todo ||
      TextSystemBlockType.quote ||
      TextSystemBlockType.code => true,
      _ => false,
    };
  }

  static bool _canSplitAcrossPages(TextSystemBlock block) {
    return switch (block.type) {
      TextSystemBlockType.paragraph ||
      TextSystemBlockType.listItem ||
      TextSystemBlockType.todo ||
      TextSystemBlockType.quote => true,
      _ => false,
    };
  }

  static String _layoutTextForBlock(TextSystemBlock block, int blockIndex) {
    if (block.type == TextSystemBlockType.listItem || block.type == TextSystemBlockType.todo) {
      return block.text.isEmpty ? ' ' : block.text;
    }
    return TextSystemLayoutStyleResolver.visibleTextForBlock(block, blockIndex);
  }

  static double _textMaxWidthForBlock(TextSystemBlock block, double contentWidthPx) {
    if (block.type == TextSystemBlockType.listItem || block.type == TextSystemBlockType.todo) {
      return math.max(48.0, contentWidthPx - 30.0);
    }
    return contentWidthPx;
  }

  static double _measureTextHeight({
    required String text,
    required TextStyle style,
    required TextDirection textDirection,
    required TextScaler textScaler,
    required double maxWidth,
    required double minimumHeight,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: textDirection,
      textScaler: textScaler,
    )..layout(maxWidth: maxWidth);
    return math.max(minimumHeight, painter.height);
  }

  static int _splitOffsetForHeight({
    required String text,
    required TextStyle style,
    required TextDirection textDirection,
    required TextScaler textScaler,
    required double maxWidth,
    required double maxHeight,
  }) {
    if (text.length <= 1 || maxHeight <= 0) return 0;

    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: textDirection,
      textScaler: textScaler,
    )..layout(maxWidth: maxWidth);

    if (painter.height <= maxHeight) return text.length;

    final rawOffset = painter.getPositionForOffset(Offset(maxWidth, maxHeight)).offset;
    final bounded = rawOffset.clamp(0, text.length).toInt();
    if (bounded <= 0) {
      // Hard fallback for pathological cases: very large type, very narrow
      // pages, or long unbreakable text should still produce a visible
      // fragment instead of disappearing as an oversized zero-width/zero-range
      // layout case. This may split inside a word, but it preserves the page
      // writer invariant that text remains visible inside real pages.
      return math.min(1, text.length);
    }

    final semanticBreak = _lastBreakBefore(text, bounded, RegExp(r'[\.\!\?]\s+'));
    if (semanticBreak > bounded * 0.55) return semanticBreak;

    final whitespaceBreak = _lastBreakBefore(text, bounded, RegExp(r'\s+'));
    if (whitespaceBreak > bounded * 0.55) return whitespaceBreak;

    return bounded;
  }

  static int _lastBreakBefore(String text, int end, RegExp pattern) {
    var breakAt = -1;
    final prefix = text.substring(0, end.clamp(0, text.length).toInt());
    for (final match in pattern.allMatches(prefix)) {
      breakAt = match.end;
    }
    return breakAt;
  }

  static double _minimumBlockHeight(TextStyle style) {
    final fontSize = style.fontSize ?? 14;
    final height = style.height ?? 1.35;
    return fontSize * height;
  }
}

class _PagedFootnoteReference {
  const _PagedFootnoteReference({
    required this.footnoteId,
    required this.anchorBlockId,
    required this.anchorBlockIndex,
    required this.anchorOffset,
    required this.number,
  });

  final String footnoteId;
  final String anchorBlockId;
  final int anchorBlockIndex;
  final int anchorOffset;
  final int number;

  _PagedFootnoteReference copyWith({int? number}) {
    return _PagedFootnoteReference(
      footnoteId: footnoteId,
      anchorBlockId: anchorBlockId,
      anchorBlockIndex: anchorBlockIndex,
      anchorOffset: anchorOffset,
      number: number ?? this.number,
    );
  }
}

class _MutablePagedBlockPage {
  _MutablePagedBlockPage({
    required this.pageNumber,
    this.logicalPageNumber,
    this.sectionIndex = 0,
    this.sectionId,
  });

  final int pageNumber;
  final int? logicalPageNumber;
  final int sectionIndex;
  final String? sectionId;
  final List<TextSystemPagedBlockFragment> fragments = <TextSystemPagedBlockFragment>[];

  bool get isEmpty => fragments.isEmpty;
}
