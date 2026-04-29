import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart' as pdfrx;

import '../../notes/data/note_repository.dart';

class PdfHoverHighlightOverlay extends StatelessWidget {
  final ValueListenable<List<PdfLinkedHighlightRegion>>
      persistentRegionsListenable;
  final ValueListenable<List<PdfSourceRect>> hoverSourceRectsListenable;
  final Rect pageRectInViewer;
  final pdfrx.PdfPage page;
  final ValueChanged<String>? onLinkedHighlightActivated;

  const PdfHoverHighlightOverlay({
    super.key,
    required this.persistentRegionsListenable,
    required this.hoverSourceRectsListenable,
    required this.pageRectInViewer,
    required this.page,
    this.onLinkedHighlightActivated,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: ValueListenableBuilder<List<PdfLinkedHighlightRegion>>(
        valueListenable: persistentRegionsListenable,
        builder: (context, persistentRegions, _) {
          return ValueListenableBuilder<List<PdfSourceRect>>(
            valueListenable: hoverSourceRectsListenable,
            builder: (context, hoverRects, _) {
              final persistentForPage = persistentRegions
                  .where(
                    (region) => region.sourceRects.any(
                      (rect) =>
                          rect.pageNumber == page.pageNumber && rect.isValid,
                    ),
                  )
                  .toList();

              final hoverForPage = hoverRects
                  .where(
                    (rect) =>
                        rect.pageNumber == page.pageNumber && rect.isValid,
                  )
                  .toList();

              if (persistentForPage.isEmpty && hoverForPage.isEmpty) {
                return const SizedBox.shrink();
              }

              final hitBands = _buildHitBands(persistentForPage);

              return Stack(
                children: [
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: PdfHighlightPainter(
                          persistentRegions: persistentForPage,
                          hoverSourceRects: hoverForPage,
                          pageRectInViewer: pageRectInViewer,
                          page: page,
                        ),
                      ),
                    ),
                  ),
                  for (final band in hitBands)
                    Positioned.fromRect(
                      rect: band.rect.inflate(3),
                      child: MouseRegion(
                        cursor: band.region.hasSidecarNote
                            ? SystemMouseCursors.click
                            : MouseCursor.defer,
                        child: GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          onTap: band.region.hasSidecarNote
                              ? () => onLinkedHighlightActivated?.call(
                                    band.region.noteId,
                                  )
                              : null,
                          child: const SizedBox.expand(),
                        ),
                      ),
                    ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  List<_HighlightHitBand> _buildHitBands(
    List<PdfLinkedHighlightRegion> regions,
  ) {
    final bands = <_HighlightHitBand>[];

    for (final region in regions) {
      if (!region.hasSidecarNote) {
        continue;
      }

      final rectsForPage = region.sourceRects
          .where(
            (rect) => rect.pageNumber == page.pageNumber && rect.isValid,
          )
          .toList();

      if (rectsForPage.isEmpty) {
        continue;
      }

      final localRects = _toLocalFlutterRects(rectsForPage);

      for (final rect in _mergeRectsIntoLineBands(localRects)) {
        bands.add(
          _HighlightHitBand(
            rect: rect,
            region: region,
          ),
        );
      }
    }

    return bands;
  }

  List<Rect> _toLocalFlutterRects(List<PdfSourceRect> sourceRects) {
    final output = <Rect>[];

    for (final sourceRect in sourceRects) {
      final pdfRect = pdfrx.PdfRect(
        sourceRect.left,
        sourceRect.top,
        sourceRect.right,
        sourceRect.bottom,
      );

      final rectInViewer = pdfRect.toRectInDocument(
        page: page,
        pageRect: pageRectInViewer,
      );

      final localRect = rectInViewer.shift(
        Offset(
          -pageRectInViewer.left,
          -pageRectInViewer.top,
        ),
      );

      final normalized = Rect.fromLTRB(
        math.min(localRect.left, localRect.right),
        math.min(localRect.top, localRect.bottom),
        math.max(localRect.left, localRect.right),
        math.max(localRect.top, localRect.bottom),
      );

      if (normalized.width <= 0 || normalized.height <= 0) {
        continue;
      }

      output.add(normalized);
    }

    return output;
  }

  List<Rect> _mergeRectsIntoLineBands(List<Rect> rects) {
    final filtered = rects
        .where(
          (rect) =>
              rect.width > 0.5 &&
              rect.height > 0.5 &&
              rect.width.isFinite &&
              rect.height.isFinite,
        )
        .toList();

    if (filtered.isEmpty) {
      return const [];
    }

    filtered.sort((a, b) {
      final centerCompare = a.center.dy.compareTo(b.center.dy);
      if (centerCompare != 0) return centerCompare;
      return a.left.compareTo(b.left);
    });

    final bands = <_MutableHighlightBand>[];

    for (final rect in filtered) {
      final normalized = _normalizeTextRect(rect);
      final candidate = _findCompatibleBand(
        bands: bands,
        rect: normalized,
      );

      if (candidate == null) {
        bands.add(_MutableHighlightBand(normalized));
      } else {
        candidate.merge(normalized);
      }
    }

    return bands.map((band) => band.rect).toList();
  }

  Rect _normalizeTextRect(Rect rect) {
    final height = rect.height;

    final verticalPad = math.max(1.0, height * 0.12);
    final horizontalPad = math.max(1.2, height * 0.10);

    return Rect.fromLTRB(
      rect.left - horizontalPad,
      rect.top - verticalPad,
      rect.right + horizontalPad,
      rect.bottom + verticalPad,
    );
  }

  _MutableHighlightBand? _findCompatibleBand({
    required List<_MutableHighlightBand> bands,
    required Rect rect,
  }) {
    for (final band in bands.reversed) {
      final sameLineTolerance = math.max(
        3.0,
        math.min(rect.height, band.rect.height) * 0.72,
      );

      final verticalDistance = (rect.center.dy - band.centerY).abs();

      if (verticalDistance > sameLineTolerance) {
        continue;
      }

      final horizontalGap = rect.left > band.rect.right
          ? rect.left - band.rect.right
          : band.rect.left > rect.right
              ? band.rect.left - rect.right
              : 0.0;

      final maxWordGap = math.max(
        18.0,
        math.min(rect.height, band.rect.height) * 2.2,
      );

      if (horizontalGap > maxWordGap) {
        continue;
      }

      return band;
    }

    return null;
  }
}

class PdfHighlightPainter extends CustomPainter {
  final List<PdfLinkedHighlightRegion> persistentRegions;
  final List<PdfSourceRect> hoverSourceRects;
  final Rect pageRectInViewer;
  final pdfrx.PdfPage page;

  const PdfHighlightPainter({
    required this.persistentRegions,
    required this.hoverSourceRects,
    required this.pageRectInViewer,
    required this.page,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) {
      return;
    }

    final persistentRects = [
      for (final region in persistentRegions)
        for (final rect in region.sourceRects)
          if (rect.pageNumber == page.pageNumber && rect.isValid) rect,
    ];

    _paintRects(
      canvas: canvas,
      size: size,
      sourceRects: persistentRects,
      opacity: 0.22,
      softOpacity: 0.09,
    );

    _paintRects(
      canvas: canvas,
      size: size,
      sourceRects: hoverSourceRects,
      opacity: 0.38,
      softOpacity: 0.16,
    );
  }

  void _paintRects({
    required Canvas canvas,
    required Size size,
    required List<PdfSourceRect> sourceRects,
    required double opacity,
    required double softOpacity,
  }) {
    if (sourceRects.isEmpty) {
      return;
    }

    final localRects = _toLocalFlutterRects(sourceRects);

    if (localRects.isEmpty) {
      return;
    }

    final highlightBands = _mergeRectsIntoLineBands(localRects);

    if (highlightBands.isEmpty) {
      return;
    }

    final mainPaint = Paint()
      ..color = const Color(0xFFFFD54F).withOpacity(opacity)
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final softPaint = Paint()
      ..color = const Color(0xFFFFF176).withOpacity(softOpacity)
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    for (final band in highlightBands) {
      final visibleBand = band.intersect(Offset.zero & size);

      if (visibleBand.isEmpty) {
        continue;
      }

      final markerRect = _toMarkerStrokeRect(visibleBand);
      final softRect = markerRect.inflate(1.8);

      final radius = Radius.circular(
        math.max(2.0, markerRect.height * 0.28),
      );

      canvas.drawRRect(
        RRect.fromRectAndRadius(softRect, radius),
        softPaint,
      );

      canvas.drawRRect(
        RRect.fromRectAndRadius(markerRect, radius),
        mainPaint,
      );
    }
  }

  List<Rect> _toLocalFlutterRects(List<PdfSourceRect> sourceRects) {
    final output = <Rect>[];

    for (final sourceRect in sourceRects) {
      final pdfRect = pdfrx.PdfRect(
        sourceRect.left,
        sourceRect.top,
        sourceRect.right,
        sourceRect.bottom,
      );

      final rectInViewer = pdfRect.toRectInDocument(
        page: page,
        pageRect: pageRectInViewer,
      );

      final localRect = rectInViewer.shift(
        Offset(
          -pageRectInViewer.left,
          -pageRectInViewer.top,
        ),
      );

      final normalized = Rect.fromLTRB(
        math.min(localRect.left, localRect.right),
        math.min(localRect.top, localRect.bottom),
        math.max(localRect.left, localRect.right),
        math.max(localRect.top, localRect.bottom),
      );

      if (normalized.width <= 0 || normalized.height <= 0) {
        continue;
      }

      output.add(normalized);
    }

    return output;
  }

  List<Rect> _mergeRectsIntoLineBands(List<Rect> rects) {
    final filtered = rects
        .where(
          (rect) =>
              rect.width > 0.5 &&
              rect.height > 0.5 &&
              rect.width.isFinite &&
              rect.height.isFinite,
        )
        .toList();

    if (filtered.isEmpty) {
      return const [];
    }

    filtered.sort((a, b) {
      final centerCompare = a.center.dy.compareTo(b.center.dy);

      if (centerCompare != 0) {
        return centerCompare;
      }

      return a.left.compareTo(b.left);
    });

    final bands = <_MutableHighlightBand>[];

    for (final rect in filtered) {
      final normalized = _normalizeTextRect(rect);
      final candidate = _findCompatibleBand(
        bands: bands,
        rect: normalized,
      );

      if (candidate == null) {
        bands.add(_MutableHighlightBand(normalized));
      } else {
        candidate.merge(normalized);
      }
    }

    return bands.map((band) => band.rect).toList();
  }

  Rect _normalizeTextRect(Rect rect) {
    final height = rect.height;

    final verticalPad = math.max(1.0, height * 0.12);
    final horizontalPad = math.max(1.2, height * 0.10);

    return Rect.fromLTRB(
      rect.left - horizontalPad,
      rect.top - verticalPad,
      rect.right + horizontalPad,
      rect.bottom + verticalPad,
    );
  }

  _MutableHighlightBand? _findCompatibleBand({
    required List<_MutableHighlightBand> bands,
    required Rect rect,
  }) {
    for (final band in bands.reversed) {
      final sameLineTolerance = math.max(
        3.0,
        math.min(rect.height, band.rect.height) * 0.72,
      );

      final verticalDistance = (rect.center.dy - band.centerY).abs();

      if (verticalDistance > sameLineTolerance) {
        continue;
      }

      final horizontalGap = rect.left > band.rect.right
          ? rect.left - band.rect.right
          : band.rect.left > rect.right
              ? band.rect.left - rect.right
              : 0.0;

      final maxWordGap = math.max(
        18.0,
        math.min(rect.height, band.rect.height) * 2.2,
      );

      if (horizontalGap > maxWordGap) {
        continue;
      }

      return band;
    }

    return null;
  }

  Rect _toMarkerStrokeRect(Rect rect) {
    final height = rect.height;

    final top = rect.top + height * 0.16;
    final bottom = rect.bottom - height * 0.04;

    return Rect.fromLTRB(
      rect.left,
      top,
      rect.right,
      math.max(top + 2.0, bottom),
    );
  }

  @override
  bool shouldRepaint(covariant PdfHighlightPainter oldDelegate) {
    return oldDelegate.persistentRegions != persistentRegions ||
        oldDelegate.hoverSourceRects != hoverSourceRects ||
        oldDelegate.pageRectInViewer != pageRectInViewer ||
        oldDelegate.page.pageNumber != page.pageNumber;
  }
}

class _HighlightHitBand {
  final Rect rect;
  final PdfLinkedHighlightRegion region;

  const _HighlightHitBand({
    required this.rect,
    required this.region,
  });
}

class _MutableHighlightBand {
  Rect rect;

  _MutableHighlightBand(this.rect);

  double get centerY => rect.center.dy;

  void merge(Rect other) {
    rect = Rect.fromLTRB(
      math.min(rect.left, other.left),
      math.min(rect.top, other.top),
      math.max(rect.right, other.right),
      math.max(rect.bottom, other.bottom),
    );
  }
}