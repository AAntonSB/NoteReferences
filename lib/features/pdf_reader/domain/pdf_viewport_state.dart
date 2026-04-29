import 'dart:ui';

class PdfViewportState {
  final bool isReady;
  final int currentPage;
  final int pageCount;
  final double zoom;
  final Rect visibleRect;
  final Size documentSize;
  final List<Rect> pageRects;

  PdfViewportState({
    required this.isReady,
    required this.currentPage,
    required this.pageCount,
    required this.zoom,
    required this.visibleRect,
    required this.documentSize,
    required List<Rect> pageRects,
  }) : pageRects = List.unmodifiable(pageRects);

  factory PdfViewportState.initial() {
    return PdfViewportState(
      isReady: false,
      currentPage: 1,
      pageCount: 1,
      zoom: 1.0,
      visibleRect: Rect.zero,
      documentSize: Size.zero,
      pageRects: const [],
    );
  }

  int get safePageCount {
    return pageCount <= 0 ? 1 : pageCount;
  }

  int get safeCurrentPage {
    return currentPage.clamp(1, safePageCount).toInt();
  }

  double get visibleTop {
    return visibleRect == Rect.zero ? 0.0 : visibleRect.top;
  }

  bool get hasUsablePageLayout {
    return isReady &&
        documentSize.height > 0 &&
        visibleRect.height > 0 &&
        pageRects.isNotEmpty;
  }

  bool isEquivalentTo(PdfViewportState other) {
    return isReady == other.isReady &&
        currentPage == other.currentPage &&
        pageCount == other.pageCount &&
        zoom == other.zoom &&
        visibleRect == other.visibleRect &&
        documentSize == other.documentSize &&
        _rectListsEqual(pageRects, other.pageRects);
  }

  static bool _rectListsEqual(List<Rect> a, List<Rect> b) {
    if (a.length != b.length) return false;

    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }

    return true;
  }
}