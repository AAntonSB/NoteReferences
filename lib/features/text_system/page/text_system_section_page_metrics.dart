import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../core/text_system_block.dart';
import '../core/text_system_document.dart';
import 'text_system_page_map.dart';

/// Page-aware section metrics derived from the passive [TextSystemPageMap].
///
/// This layer is read-only. It interprets the measured page map for navigation,
/// progress, and document-planning UI, but it must never mutate the document or
/// create transactions.
@immutable
class TextSystemSectionPageMetricsResult {
  const TextSystemSectionPageMetricsResult({
    required this.documentRevision,
    required this.measuredPages,
    required this.targetPages,
    required this.sections,
  });

  final int documentRevision;
  final double measuredPages;
  final double targetPages;
  final List<TextSystemSectionPageMetric> sections;

  int get sectionCount => sections.length;
  double get remainingPages => math.max(0, targetPages - measuredPages);
  double get completionRatio {
    if (targetPages <= 0) return 0;
    return (measuredPages / targetPages).clamp(0.0, 1.0).toDouble();
  }

  bool get isOverTarget => measuredPages > targetPages && targetPages > 0;

  String get measuredPagesLabel => _formatPages(measuredPages);
  String get targetPagesLabel => _formatPages(targetPages);
  String get remainingPagesLabel => _formatPages(remainingPages);

  String get progressLabel {
    final percent = (completionRatio * 100).round();
    if (isOverTarget) {
      return '$measuredPagesLabel / $targetPagesLabel pages · over target by ${_formatPages(measuredPages - targetPages)}';
    }
    return '$measuredPagesLabel / $targetPagesLabel pages · $percent% · $remainingPagesLabel remaining';
  }

  TextSystemSectionPageMetric? metricForBlockId(String blockId) {
    for (final section in sections) {
      if (section.blockId == blockId) return section;
    }
    return null;
  }

  List<TextSystemSectionPageMetric> get longestSections {
    final copy = sections.toList(growable: false);
    copy.sort((a, b) => b.pageSpan.compareTo(a.pageSpan));
    return copy.take(5).toList(growable: false);
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'documentRevision': documentRevision,
      'measuredPages': measuredPages,
      'targetPages': targetPages,
      'remainingPages': remainingPages,
      'completionRatio': completionRatio,
      'progressLabel': progressLabel,
      'sections': [for (final section in sections) section.toJson()],
    };
  }

  static TextSystemSectionPageMetricsResult compute({
    required TextSystemDocument document,
    required TextSystemPageMap pageMap,
    required double targetPages,
  }) {
    final headingBlockIndexes = <int>[];
    for (var i = 0; i < document.blocks.length; i++) {
      final block = document.blocks[i];
      if (block.type == TextSystemBlockType.heading && block.text.trim().isNotEmpty) {
        headingBlockIndexes.add(i);
      }
    }

    final sections = <TextSystemSectionPageMetric>[];

    for (var headingListIndex = 0; headingListIndex < headingBlockIndexes.length; headingListIndex++) {
      final startBlockIndex = headingBlockIndexes[headingListIndex];
      final heading = document.blocks[startBlockIndex];
      final level = heading.level ?? 2;
      var endBlockIndex = document.blocks.length - 1;

      for (var nextHeadingListIndex = headingListIndex + 1;
          nextHeadingListIndex < headingBlockIndexes.length;
          nextHeadingListIndex++) {
        final candidateIndex = headingBlockIndexes[nextHeadingListIndex];
        final candidate = document.blocks[candidateIndex];
        final candidateLevel = candidate.level ?? 2;
        if (candidateLevel <= level) {
          endBlockIndex = candidateIndex - 1;
          break;
        }
      }

      final fragments = pageMap.fragments
          .where((fragment) => fragment.blockIndex >= startBlockIndex && fragment.blockIndex <= endBlockIndex)
          .toList(growable: false);

      final headingFragment = pageMap.firstFragmentForBlockId(heading.id);
      final resolvedFragments = fragments.isNotEmpty
          ? fragments
          : headingFragment == null
              ? const <TextSystemPageFragment>[]
              : <TextSystemPageFragment>[headingFragment];

      final startPage = resolvedFragments.isEmpty
          ? 1
          : resolvedFragments.map((fragment) => fragment.pageNumber).reduce(math.min);
      final endPage = resolvedFragments.isEmpty
          ? startPage
          : resolvedFragments.map((fragment) => fragment.pageNumber).reduce(math.max);
      final startY = resolvedFragments.isEmpty
          ? 0.0
          : resolvedFragments.map((fragment) => fragment.contentStartY).reduce(math.min);
      final endY = resolvedFragments.isEmpty
          ? 0.0
          : resolvedFragments.map((fragment) => fragment.contentEndY).reduce(math.max);
      final pageSpan = resolvedFragments.isEmpty
          ? 0.0
          : math.max(0.05, (endY - startY) / math.max(1.0, pageMap.contentHeightPx));

      sections.add(
        TextSystemSectionPageMetric(
          blockId: heading.id,
          title: heading.text.trim(),
          level: level,
          headingBlockIndex: startBlockIndex,
          endBlockIndex: endBlockIndex,
          startPage: startPage,
          endPage: endPage,
          startContentY: startY,
          endContentY: endY,
          pageSpan: pageSpan,
          fragmentCount: resolvedFragments.length,
          todoCount: _metadataInt(heading.metadata, 'todoCount'),
          noteCount: _metadataInt(heading.metadata, 'noteCount'),
          dueSoonCount: _metadataInt(heading.metadata, 'dueSoonCount'),
          overdueCount: _metadataInt(heading.metadata, 'overdueCount'),
        ),
      );
    }

    return TextSystemSectionPageMetricsResult(
      documentRevision: pageMap.documentRevision,
      measuredPages: math.max(1.0, pageMap.totalContentHeightPx / math.max(1.0, pageMap.contentHeightPx)),
      targetPages: math.max(1.0, targetPages),
      sections: sections,
    );
  }

  static int _metadataInt(Map<String, Object?> metadata, String key) {
    final value = metadata[key];
    if (value is int) return value;
    if (value is num) return value.toInt();
    return 0;
  }

  static String _formatPages(double pages) {
    if (pages >= 10) return pages.toStringAsFixed(0);
    return pages.toStringAsFixed(1);
  }
}

@immutable
class TextSystemSectionPageMetric {
  const TextSystemSectionPageMetric({
    required this.blockId,
    required this.title,
    required this.level,
    required this.headingBlockIndex,
    required this.endBlockIndex,
    required this.startPage,
    required this.endPage,
    required this.startContentY,
    required this.endContentY,
    required this.pageSpan,
    required this.fragmentCount,
    this.todoCount = 0,
    this.noteCount = 0,
    this.dueSoonCount = 0,
    this.overdueCount = 0,
  });

  final String blockId;
  final String title;
  final int level;
  final int headingBlockIndex;
  final int endBlockIndex;
  final int startPage;
  final int endPage;
  final double startContentY;
  final double endContentY;
  final double pageSpan;
  final int fragmentCount;
  final int todoCount;
  final int noteCount;
  final int dueSoonCount;
  final int overdueCount;

  String get pageLabel => startPage == endPage ? 'p. $startPage' : 'pp. $startPage–$endPage';
  String get pageSpanLabel => '${_formatPages(pageSpan)} p';
  String get detailedLabel => '$pageLabel · $pageSpanLabel';

  bool get hasProjectSignals => todoCount > 0 || noteCount > 0 || dueSoonCount > 0 || overdueCount > 0;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'blockId': blockId,
      'title': title,
      'level': level,
      'headingBlockIndex': headingBlockIndex,
      'endBlockIndex': endBlockIndex,
      'startPage': startPage,
      'endPage': endPage,
      'pageLabel': pageLabel,
      'pageSpan': pageSpan,
      'pageSpanLabel': pageSpanLabel,
      'fragmentCount': fragmentCount,
      'todoCount': todoCount,
      'noteCount': noteCount,
      'dueSoonCount': dueSoonCount,
      'overdueCount': overdueCount,
    };
  }

  static String _formatPages(double pages) {
    if (pages >= 10) return pages.toStringAsFixed(0);
    return pages.toStringAsFixed(1);
  }
}
