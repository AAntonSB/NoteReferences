import 'dart:math' as math;

import '../core/text_system_block.dart';
import '../core/text_system_document.dart';
import 'text_system_page_setup.dart';

/// Approximate document pagination metrics for writer-facing feedback.
///
/// This is deliberately not a true layout engine. It estimates page count from
/// page setup, margins, font size, line spacing, paragraph structure, and text
/// length. True page layout metadata and page virtualization come in later page
/// system phases.
class TextSystemPageEstimate {
  const TextSystemPageEstimate({
    required this.pageSetup,
    required this.wordCount,
    required this.characterCount,
    required this.estimatedPages,
    required this.estimatedLines,
    required this.linesPerPage,
    required this.estimatedWordsPerPage,
    required this.contentWidthMm,
    required this.contentHeightMm,
  });

  final TextSystemPageSetup pageSetup;
  final int wordCount;
  final int characterCount;
  final int estimatedPages;
  final int estimatedLines;
  final int linesPerPage;
  final int estimatedWordsPerPage;
  final double contentWidthMm;
  final double contentHeightMm;

  int? get maxPages => pageSetup.constraint.maxPages;

  bool get hasLimit => pageSetup.constraint.hasPageLimit;

  int get overLimitBy {
    final limit = maxPages;
    if (limit == null || limit <= 0) return 0;
    return math.max(0, estimatedPages - limit);
  }

  int? get remainingPages {
    final limit = maxPages;
    if (limit == null || limit <= 0) return null;
    return math.max(0, limit - estimatedPages);
  }

  bool get isOverLimit => overLimitBy > 0;

  String get pageLabel {
    final limit = maxPages;
    if (limit == null || limit <= 0) return '~$estimatedPages pages';
    if (isOverLimit) return '~$estimatedPages / $limit pages · over by $overLimitBy';
    return '~$estimatedPages / $limit pages';
  }

  String get statusLabel {
    final limit = maxPages;
    if (limit == null || limit <= 0) return pageLabel;
    if (isOverLimit) return '$pageLabel · reduce length';
    final remaining = remainingPages ?? 0;
    if (remaining == 0) return '$pageLabel · at limit';
    return '$pageLabel · $remaining remaining';
  }

  String get compactLayoutLabel {
    return '${contentWidthMm.toStringAsFixed(0)} × ${contentHeightMm.toStringAsFixed(0)} mm content · ~$estimatedWordsPerPage words/page';
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'pageSetup': pageSetup.toJson(),
      'wordCount': wordCount,
      'characterCount': characterCount,
      'estimatedPages': estimatedPages,
      'estimatedLines': estimatedLines,
      'linesPerPage': linesPerPage,
      'estimatedWordsPerPage': estimatedWordsPerPage,
      'contentWidthMm': contentWidthMm,
      'contentHeightMm': contentHeightMm,
      'maxPages': maxPages,
      'remainingPages': remainingPages,
      'overLimitBy': overLimitBy,
      'isOverLimit': isOverLimit,
      'pageLabel': pageLabel,
      'statusLabel': statusLabel,
    };
  }
}

class TextSystemPageEstimator {
  const TextSystemPageEstimator._();

  static TextSystemPageEstimate estimate({
    required TextSystemDocument document,
    required TextSystemPageSetup pageSetup,
  }) {
    final wordCount = _wordCount(document.plainText);
    final characterCount = document.plainText.length;
    final contentWidthMm = math.max(
      20.0,
      pageSetup.pageWidthMm - pageSetup.margins.leftMm - pageSetup.margins.rightMm,
    );
    final contentHeightMm = math.max(
      20.0,
      pageSetup.pageHeightMm - pageSetup.margins.topMm - pageSetup.margins.bottomMm,
    );

    final baseFontHeightMm = _ptToMm(pageSetup.defaultFontSize) * pageSetup.lineSpacing;
    final linesPerPage = math.max(1, (contentHeightMm / baseFontHeightMm).floor());

    var estimatedLines = 0;
    for (final block in document.blocks) {
      estimatedLines += _estimateBlockLines(
        block: block,
        contentWidthMm: contentWidthMm,
        pageSetup: pageSetup,
      );
    }

    if (estimatedLines == 0) estimatedLines = 1;

    final estimatedPages = math.max(1, (estimatedLines / linesPerPage).ceil());
    final estimatedWordsPerPage = estimatedPages <= 0 ? wordCount : math.max(1, (wordCount / estimatedPages).round());

    return TextSystemPageEstimate(
      pageSetup: pageSetup,
      wordCount: wordCount,
      characterCount: characterCount,
      estimatedPages: estimatedPages,
      estimatedLines: estimatedLines,
      linesPerPage: linesPerPage,
      estimatedWordsPerPage: estimatedWordsPerPage,
      contentWidthMm: contentWidthMm,
      contentHeightMm: contentHeightMm,
    );
  }

  static int _estimateBlockLines({
    required TextSystemBlock block,
    required double contentWidthMm,
    required TextSystemPageSetup pageSetup,
  }) {
    final text = block.text.trimRight();
    final normalizedLength = text.isEmpty ? 1 : text.length;
    final fontSize = _fontSizeForBlock(block, pageSetup);
    final averageCharWidthMm = _ptToMm(fontSize) * 0.52;
    final charsPerLine = math.max(18, (contentWidthMm / averageCharWidthMm).floor());

    var visibleLength = normalizedLength;
    if (block.type == TextSystemBlockType.listItem) visibleLength += 3;
    if (block.type == TextSystemBlockType.todo) visibleLength += 3;

    final contentLines = math.max(1, (visibleLength / charsPerLine).ceil());
    final paragraphGap = _paragraphGapLines(block, pageSetup);
    return contentLines + paragraphGap;
  }

  static double _fontSizeForBlock(TextSystemBlock block, TextSystemPageSetup pageSetup) {
    if (block.type == TextSystemBlockType.heading) {
      return pageSetup.typography.headingFontSizeForLevel(block.level ?? 2);
    }
    if (block.type == TextSystemBlockType.code) return pageSetup.defaultFontSize * 0.92;
    return pageSetup.defaultFontSize;
  }

  static int _paragraphGapLines(TextSystemBlock block, TextSystemPageSetup pageSetup) {
    final gapAsLineFraction = pageSetup.typography.paragraphSpacingPt /
        (pageSetup.defaultFontSize * pageSetup.lineSpacing);
    final normalGap = gapAsLineFraction >= 0.55 ? 1 : 0;

    return switch (block.type) {
      TextSystemBlockType.heading => switch (block.level ?? 2) {
          1 => 2,
          2 => 1,
          _ => 1,
        },
      TextSystemBlockType.listItem => 0,
      TextSystemBlockType.todo => 0,
      TextSystemBlockType.divider => 1,
      _ => normalGap,
    };
  }

  static int _wordCount(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return 0;
    return trimmed.split(RegExp(r'\s+')).where((word) => word.isNotEmpty).length;
  }

  static double _ptToMm(double pt) => pt * 0.3527777778;
}
