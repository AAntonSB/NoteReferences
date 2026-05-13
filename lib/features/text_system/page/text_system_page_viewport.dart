import 'dart:math' as math;

/// Scroll-aware page viewport metadata for page-oriented writing surfaces.
///
/// This is a virtualization foundation, not true page virtualization yet. It
/// keeps the editor logically continuous while estimating which pages are
/// visible and which nearby pages would be kept mounted once we introduce real
/// visual page splitting.
class TextSystemPageViewport {
  const TextSystemPageViewport({
    required this.pageCount,
    required this.currentPage,
    required this.firstVisiblePage,
    required this.lastVisiblePage,
    required this.mountedPageStart,
    required this.mountedPageEnd,
    required this.scrollOffsetPx,
    required this.viewportHeightPx,
    required this.pageExtentPx,
    required this.cacheExtentPages,
  });

  final int pageCount;
  final int currentPage;
  final int firstVisiblePage;
  final int lastVisiblePage;
  final int mountedPageStart;
  final int mountedPageEnd;
  final double scrollOffsetPx;
  final double viewportHeightPx;
  final double pageExtentPx;
  final int cacheExtentPages;

  int get visiblePageCount => math.max(0, lastVisiblePage - firstVisiblePage + 1);
  int get mountedPageCount => math.max(0, mountedPageEnd - mountedPageStart + 1);

  String get currentPageLabel => 'Page $currentPage of ~$pageCount';

  String get visibleRangeLabel {
    if (firstVisiblePage == lastVisiblePage) return 'visible p. $firstVisiblePage';
    return 'visible p. $firstVisiblePage-$lastVisiblePage';
  }

  String get mountedRangeLabel {
    if (mountedPageStart == mountedPageEnd) return 'render window p. $mountedPageStart';
    return 'render window p. $mountedPageStart-$mountedPageEnd';
  }

  String get statusLabel => '$currentPageLabel · $visibleRangeLabel · $mountedRangeLabel';

  String get signature => [
        pageCount,
        currentPage,
        firstVisiblePage,
        lastVisiblePage,
        mountedPageStart,
        mountedPageEnd,
        viewportHeightPx.round(),
        pageExtentPx.round(),
      ].join(':');

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'pageCount': pageCount,
      'currentPage': currentPage,
      'firstVisiblePage': firstVisiblePage,
      'lastVisiblePage': lastVisiblePage,
      'visiblePageCount': visiblePageCount,
      'mountedPageStart': mountedPageStart,
      'mountedPageEnd': mountedPageEnd,
      'mountedPageCount': mountedPageCount,
      'scrollOffsetPx': scrollOffsetPx,
      'viewportHeightPx': viewportHeightPx,
      'pageExtentPx': pageExtentPx,
      'cacheExtentPages': cacheExtentPages,
      'currentPageLabel': currentPageLabel,
      'visibleRangeLabel': visibleRangeLabel,
      'mountedRangeLabel': mountedRangeLabel,
      'statusLabel': statusLabel,
    };
  }
}

class TextSystemPageViewportPlanner {
  const TextSystemPageViewportPlanner._();

  static TextSystemPageViewport fromScroll({
    required int pageCount,
    required double scrollOffsetPx,
    required double viewportHeightPx,
    required double pageExtentPx,
    int cacheExtentPages = 2,
  }) {
    final safePageCount = math.max(1, pageCount);
    final safePageExtent = math.max(1.0, pageExtentPx);
    final safeViewportHeight = math.max(1.0, viewportHeightPx);
    final safeScrollOffset = math.max(0.0, scrollOffsetPx);

    final firstVisiblePage = _clampPage(
      (safeScrollOffset / safePageExtent).floor() + 1,
      safePageCount,
    );
    final lastVisiblePage = _clampPage(
      ((safeScrollOffset + safeViewportHeight) / safePageExtent).ceil(),
      safePageCount,
    );
    final currentPage = _clampPage(
      ((safeScrollOffset + safeViewportHeight * 0.35) / safePageExtent).floor() + 1,
      safePageCount,
    );

    final mountedPageStart = _clampPage(firstVisiblePage - cacheExtentPages, safePageCount);
    final mountedPageEnd = _clampPage(lastVisiblePage + cacheExtentPages, safePageCount);

    return TextSystemPageViewport(
      pageCount: safePageCount,
      currentPage: currentPage,
      firstVisiblePage: firstVisiblePage,
      lastVisiblePage: math.max(firstVisiblePage, lastVisiblePage),
      mountedPageStart: mountedPageStart,
      mountedPageEnd: math.max(mountedPageStart, mountedPageEnd),
      scrollOffsetPx: safeScrollOffset,
      viewportHeightPx: safeViewportHeight,
      pageExtentPx: safePageExtent,
      cacheExtentPages: cacheExtentPages,
    );
  }

  static int _clampPage(int page, int pageCount) {
    return page.clamp(1, math.max(1, pageCount)).toInt();
  }
}
