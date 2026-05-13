import 'package:flutter/foundation.dart';

import '../core/text_system_block.dart';
import 'text_system_page_setup.dart';

/// Passive pagination output for the feature-length writer.
///
/// This object is deliberately read-only layout metadata. It must never be used
/// to mutate [TextSystemDocument] directly. The editor remains the source of
/// mutations; pagination only reads the document and describes where the
/// current content would land on physical pages.
@immutable
class TextSystemPageMap {
  const TextSystemPageMap({
    required this.documentRevision,
    required this.setup,
    required this.pageWidthPx,
    required this.pageHeightPx,
    required this.contentWidthPx,
    required this.contentHeightPx,
    required this.totalContentHeightPx,
    required this.pages,
    required this.fragments,
    required this.breakMarkers,
  });

  final int documentRevision;
  final TextSystemPageSetup setup;
  final double pageWidthPx;
  final double pageHeightPx;
  final double contentWidthPx;
  final double contentHeightPx;
  final double totalContentHeightPx;
  final List<TextSystemPageMapPage> pages;
  final List<TextSystemPageFragment> fragments;
  final List<TextSystemPageBreakMarker> breakMarkers;

  int get pageCount => pages.isEmpty ? 1 : pages.length;

  String get pageLabel => '~$pageCount page${pageCount == 1 ? '' : 's'}';

  String get compactMetricsLabel {
    return '${contentWidthPx.round()} × ${contentHeightPx.round()} px content · ${breakMarkers.length} breaks';
  }

  TextSystemPageMapPage pageForNumber(int pageNumber) {
    final safePage = pageNumber.clamp(1, pageCount).toInt();
    return pages.firstWhere(
      (page) => page.pageNumber == safePage,
      orElse: () => pages.isEmpty
          ? TextSystemPageMapPage.empty(pageNumber: 1)
          : pages.last,
    );
  }

  TextSystemPageFragment? firstFragmentForBlockId(String blockId) {
    for (final fragment in fragments) {
      if (fragment.blockId == blockId) return fragment;
    }
    return null;
  }

  List<TextSystemPageFragment> fragmentsForBlockId(String blockId) {
    return fragments
        .where((fragment) => fragment.blockId == blockId)
        .toList(growable: false);
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'documentRevision': documentRevision,
      'setup': setup.toJson(),
      'pageWidthPx': pageWidthPx,
      'pageHeightPx': pageHeightPx,
      'contentWidthPx': contentWidthPx,
      'contentHeightPx': contentHeightPx,
      'totalContentHeightPx': totalContentHeightPx,
      'pageCount': pageCount,
      'pages': [for (final page in pages) page.toJson()],
      'fragments': [for (final fragment in fragments) fragment.toJson()],
      'breakMarkers': [for (final marker in breakMarkers) marker.toJson()],
    };
  }
}

@immutable
class TextSystemPageMapPage {
  const TextSystemPageMapPage({
    required this.pageNumber,
    required this.contentStartY,
    required this.contentEndY,
    required this.fragmentCount,
  });

  const TextSystemPageMapPage.empty({required this.pageNumber})
      : contentStartY = 0,
        contentEndY = 0,
        fragmentCount = 0;

  final int pageNumber;
  final double contentStartY;
  final double contentEndY;
  final int fragmentCount;

  String get label => 'Page $pageNumber';

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'pageNumber': pageNumber,
      'label': label,
      'contentStartY': contentStartY,
      'contentEndY': contentEndY,
      'fragmentCount': fragmentCount,
    };
  }
}

@immutable
class TextSystemPageFragment {
  const TextSystemPageFragment({
    required this.blockId,
    required this.blockIndex,
    required this.blockType,
    required this.pageNumber,
    required this.contentStartY,
    required this.contentEndY,
    required this.blockStartOffset,
    required this.blockEndOffset,
    this.continuesFromPreviousPage = false,
    this.continuesOnNextPage = false,
  });

  final String blockId;
  final int blockIndex;
  final TextSystemBlockType blockType;
  final int pageNumber;
  final double contentStartY;
  final double contentEndY;
  final int blockStartOffset;
  final int blockEndOffset;
  final bool continuesFromPreviousPage;
  final bool continuesOnNextPage;

  double get heightPx => contentEndY - contentStartY;
  String get pageLabel => 'p. $pageNumber';

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'blockId': blockId,
      'blockIndex': blockIndex,
      'blockType': blockType.name,
      'pageNumber': pageNumber,
      'pageLabel': pageLabel,
      'contentStartY': contentStartY,
      'contentEndY': contentEndY,
      'heightPx': heightPx,
      'blockStartOffset': blockStartOffset,
      'blockEndOffset': blockEndOffset,
      'continuesFromPreviousPage': continuesFromPreviousPage,
      'continuesOnNextPage': continuesOnNextPage,
    };
  }
}

@immutable
class TextSystemPageBreakMarker {
  const TextSystemPageBreakMarker({
    required this.beforePageNumber,
    required this.afterPageNumber,
    required this.contentOffsetY,
  });

  final int beforePageNumber;
  final int afterPageNumber;

  /// Y-coordinate inside the continuous content flow, before page top/margins.
  final double contentOffsetY;

  String get label => 'Page $afterPageNumber';
  String get transitionLabel => 'End p. $beforePageNumber · Start p. $afterPageNumber';

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'beforePageNumber': beforePageNumber,
      'afterPageNumber': afterPageNumber,
      'contentOffsetY': contentOffsetY,
      'label': label,
      'transitionLabel': transitionLabel,
    };
  }
}
