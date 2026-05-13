import 'dart:math' as math;

import '../core/text_system_block.dart';
import '../core/text_system_document.dart';
import 'text_system_page_estimator.dart';
import 'text_system_page_setup.dart';

/// Approximate page-layout metadata for document navigation.
///
/// This is the first bridge between a continuous logical document and a
/// page-aware writing surface. It does not split the editor into page-local
/// text fields. Instead, it estimates which document text units and headings
/// belong to which page so the premium writer can show page numbers, anchors,
/// and page-aware diagnostics.
class TextSystemPageLayout {
  const TextSystemPageLayout({
    required this.pageSetup,
    required this.estimate,
    required this.totalEstimatedLines,
    required this.linesPerPage,
    required this.blockLayouts,
    required this.anchors,
  });

  final TextSystemPageSetup pageSetup;
  final TextSystemPageEstimate estimate;
  final int totalEstimatedLines;
  final int linesPerPage;
  final List<TextSystemPageBlockLayout> blockLayouts;
  final List<TextSystemPageAnchor> anchors;

  int get pageCount => estimate.estimatedPages;

  TextSystemPageAnchor? anchorForBlockId(String blockId) {
    for (final anchor in anchors) {
      if (anchor.blockId == blockId) return anchor;
    }
    return null;
  }

  TextSystemPageBlockLayout? blockLayoutForBlockId(String blockId) {
    for (final layout in blockLayouts) {
      if (layout.blockId == blockId) return layout;
    }
    return null;
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'pageSetup': pageSetup.toJson(),
      'estimate': estimate.toJson(),
      'totalEstimatedLines': totalEstimatedLines,
      'linesPerPage': linesPerPage,
      'pageCount': pageCount,
      'blockLayouts': [for (final layout in blockLayouts) layout.toJson()],
      'anchors': [for (final anchor in anchors) anchor.toJson()],
    };
  }
}

class TextSystemPageBlockLayout {
  const TextSystemPageBlockLayout({
    required this.blockId,
    required this.blockIndex,
    required this.blockType,
    required this.lineStart,
    required this.lineEnd,
    required this.pageStart,
    required this.pageEnd,
  });

  final String blockId;
  final int blockIndex;
  final TextSystemBlockType blockType;
  final int lineStart;
  final int lineEnd;
  final int pageStart;
  final int pageEnd;

  int get estimatedLines => math.max(1, lineEnd - lineStart);

  String get pageLabel {
    if (pageStart == pageEnd) return 'p. $pageStart';
    return 'p. $pageStart-$pageEnd';
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'blockId': blockId,
      'blockIndex': blockIndex,
      'blockType': blockType.name,
      'lineStart': lineStart,
      'lineEnd': lineEnd,
      'estimatedLines': estimatedLines,
      'pageStart': pageStart,
      'pageEnd': pageEnd,
      'pageLabel': pageLabel,
    };
  }
}

class TextSystemPageAnchor {
  const TextSystemPageAnchor({
    required this.blockId,
    required this.blockIndex,
    required this.title,
    required this.headingLevel,
    required this.pageNumber,
    required this.lineStart,
    required this.lineEnd,
    required this.pageProgress,
  });

  final String blockId;
  final int blockIndex;
  final String title;
  final int headingLevel;
  final int pageNumber;
  final int lineStart;
  final int lineEnd;

  /// Approximate vertical progress on the page from 0 to 1.
  final double pageProgress;

  String get pageLabel => 'p. $pageNumber';

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'blockId': blockId,
      'blockIndex': blockIndex,
      'title': title,
      'headingLevel': headingLevel,
      'pageNumber': pageNumber,
      'pageLabel': pageLabel,
      'lineStart': lineStart,
      'lineEnd': lineEnd,
      'pageProgress': pageProgress,
    };
  }
}

class TextSystemPageLayoutEngine {
  const TextSystemPageLayoutEngine._();

  static TextSystemPageLayout layout({
    required TextSystemDocument document,
    required TextSystemPageSetup pageSetup,
    TextSystemPageEstimate? estimate,
  }) {
    final effectiveEstimate = estimate ?? TextSystemPageEstimator.estimate(document: document, pageSetup: pageSetup);
    final linesPerPage = math.max(1, effectiveEstimate.linesPerPage);
    final blockLayouts = <TextSystemPageBlockLayout>[];
    final anchors = <TextSystemPageAnchor>[];
    var cursorLine = 0;

    for (var i = 0; i < document.blocks.length; i++) {
      final block = document.blocks[i];
      final blockLines = _estimateBlockLines(
        block: block,
        contentWidthMm: effectiveEstimate.contentWidthMm,
        pageSetup: pageSetup,
      );
      final lineStart = cursorLine;
      final lineEnd = math.max(lineStart + 1, lineStart + blockLines);
      final pageStart = _pageForLine(lineStart, linesPerPage);
      final pageEnd = _pageForLine(math.max(lineStart, lineEnd - 1), linesPerPage);

      final blockLayout = TextSystemPageBlockLayout(
        blockId: block.id,
        blockIndex: i,
        blockType: block.type,
        lineStart: lineStart,
        lineEnd: lineEnd,
        pageStart: pageStart,
        pageEnd: pageEnd,
      );
      blockLayouts.add(blockLayout);

      if (block.type == TextSystemBlockType.heading && block.text.trim().isNotEmpty) {
        anchors.add(
          TextSystemPageAnchor(
            blockId: block.id,
            blockIndex: i,
            title: block.text.trim(),
            headingLevel: block.level ?? 2,
            pageNumber: pageStart,
            lineStart: lineStart,
            lineEnd: lineEnd,
            pageProgress: _progressOnPage(lineStart, linesPerPage),
          ),
        );
      }

      cursorLine = lineEnd;
    }

    return TextSystemPageLayout(
      pageSetup: pageSetup,
      estimate: effectiveEstimate,
      totalEstimatedLines: math.max(1, cursorLine),
      linesPerPage: linesPerPage,
      blockLayouts: blockLayouts,
      anchors: anchors,
    );
  }

  static int _pageForLine(int line, int linesPerPage) {
    return (math.max(0, line) ~/ math.max(1, linesPerPage)) + 1;
  }

  static double _progressOnPage(int line, int linesPerPage) {
    final safeLinesPerPage = math.max(1, linesPerPage);
    return ((math.max(0, line) % safeLinesPerPage) / safeLinesPerPage).clamp(0.0, 1.0).toDouble();
  }

  static int _estimateBlockLines({
    required TextSystemBlock block,
    required double contentWidthMm,
    required TextSystemPageSetup pageSetup,
  }) {
    final text = block.text.trimRight();
    final normalizedLength = text.isEmpty ? 1 : text.length;
    final fontSize = _fontSizeForBlock(block, pageSetup.defaultFontSize);
    final averageCharWidthMm = _ptToMm(fontSize) * 0.52;
    final charsPerLine = math.max(18, (contentWidthMm / averageCharWidthMm).floor());

    var visibleLength = normalizedLength;
    if (block.type == TextSystemBlockType.listItem) visibleLength += 3;
    if (block.type == TextSystemBlockType.todo) visibleLength += 3;

    final contentLines = math.max(1, (visibleLength / charsPerLine).ceil());
    return contentLines + _paragraphGapLines(block);
  }

  static double _fontSizeForBlock(TextSystemBlock block, double defaultFontSize) {
    if (block.type == TextSystemBlockType.heading) {
      return switch (block.level ?? 2) {
        1 => defaultFontSize * 1.85,
        2 => defaultFontSize * 1.45,
        _ => defaultFontSize * 1.22,
      };
    }
    if (block.type == TextSystemBlockType.code) return defaultFontSize * 0.92;
    return defaultFontSize;
  }

  static int _paragraphGapLines(TextSystemBlock block) {
    return switch (block.type) {
      TextSystemBlockType.heading => switch (block.level ?? 2) {
          1 => 2,
          2 => 1,
          _ => 1,
        },
      TextSystemBlockType.listItem => 0,
      TextSystemBlockType.todo => 0,
      TextSystemBlockType.divider => 1,
      _ => 1,
    };
  }

  static double _ptToMm(double pt) => pt * 0.3527777778;
}
