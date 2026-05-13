import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'text_system_page_map.dart';
import 'text_system_page_viewport.dart';

/// Non-interactive hybrid page-break overlay for the feature-length writer.
///
/// This is intentionally a read-only presentation layer. It paints measured
/// page boundaries over the continuous fluent editor, but it never owns focus,
/// never handles pointer events, and never mutates the document. That keeps
/// native selection, Shift-selection, caret placement, headings, commands, and
/// transactions attached to the single fluent editing surface.
class TextSystemHybridPageBreakOverlay extends StatelessWidget {
  const TextSystemHybridPageBreakOverlay({
    super.key,
    required this.pageMap,
    required this.viewport,
    required this.pageWidth,
    required this.contentLeft,
    required this.contentRight,
    required this.topOffset,
    this.gutterLabelWidth = 126,
    this.showDetailedLabels = true,
  });

  final TextSystemPageMap pageMap;
  final TextSystemPageViewport viewport;
  final double pageWidth;
  final double contentLeft;
  final double contentRight;

  /// Y offset of the beginning of the continuous content flow inside the canvas.
  final double topOffset;

  /// Width of the label painted in the left outside-page gutter.
  final double gutterLabelWidth;
  final bool showDetailedLabels;

  List<TextSystemPageBreakMarker> get _visibleMarkers {
    final startPage = math.max(1, viewport.mountedPageStart - 1);
    final endPage = math.max(startPage, viewport.mountedPageEnd + 1);

    return pageMap.breakMarkers
        .where(
          (marker) =>
              marker.afterPageNumber >= startPage &&
              marker.beforePageNumber <= endPage,
        )
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final markers = _visibleMarkers;
    if (markers.isEmpty) return const SizedBox.shrink();

    return IgnorePointer(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (final marker in markers)
            _HybridPageBreakMarker(
              marker: marker,
              top: topOffset + marker.contentOffsetY,
              pageWidth: pageWidth,
              contentLeft: contentLeft,
              contentRight: contentRight,
              gutterLabelWidth: gutterLabelWidth,
              isNearCurrentPage: marker.beforePageNumber == viewport.currentPage ||
                  marker.afterPageNumber == viewport.currentPage,
              showDetailedLabel: showDetailedLabels && pageMap.pageCount <= 20,
            ),
        ],
      ),
    );
  }
}

class _HybridPageBreakMarker extends StatelessWidget {
  const _HybridPageBreakMarker({
    required this.marker,
    required this.top,
    required this.pageWidth,
    required this.contentLeft,
    required this.contentRight,
    required this.gutterLabelWidth,
    required this.isNearCurrentPage,
    required this.showDetailedLabel,
  });

  final TextSystemPageBreakMarker marker;
  final double top;
  final double pageWidth;
  final double contentLeft;
  final double contentRight;
  final double gutterLabelWidth;
  final bool isNearCurrentPage;
  final bool showDetailedLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final accent = isNearCurrentPage ? colorScheme.primary : colorScheme.outline;
    final lineAlpha = isNearCurrentPage ? 0.42 : 0.25;
    final chipAlpha = isNearCurrentPage ? 0.96 : 0.90;
    final contentWidth = math.max(24.0, pageWidth - contentLeft - contentRight);
    final label = showDetailedLabel ? marker.transitionLabel : 'p. ${marker.afterPageNumber}';

    return Positioned(
      left: 0,
      top: top - 16,
      width: pageWidth,
      height: 32,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: contentLeft,
            top: 15.5,
            width: contentWidth,
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: accent.withValues(alpha: lineAlpha),
                    width: isNearCurrentPage ? 1.4 : 1,
                  ),
                ),
              ),
              child: const SizedBox(height: 1),
            ),
          ),
          Positioned(
            left: -gutterLabelWidth - 12,
            top: 2,
            width: gutterLabelWidth,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: (isNearCurrentPage ? colorScheme.primaryContainer : colorScheme.surface)
                    .withValues(alpha: chipAlpha),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: accent.withValues(alpha: isNearCurrentPage ? 0.38 : 0.24),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.keyboard_double_arrow_down_rounded,
                      size: 14,
                      color: isNearCurrentPage
                          ? colorScheme.onPrimaryContainer
                          : colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: isNearCurrentPage
                              ? colorScheme.onPrimaryContainer
                              : colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
